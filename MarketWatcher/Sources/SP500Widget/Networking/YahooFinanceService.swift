import Foundation

// MARK: - Service protocol

/// Abstraction over the network layer, enabling mock injection in tests.
/// Both `YahooFinanceService` (actor) and test mocks conform to this.
public protocol SP500ServiceProtocol: Sendable {
    func fetch(interval: ChartInterval, index: MarketIndex) async throws -> Quote
}

// MARK: - Errors

public enum SP500Error: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case emptyData
    case marketClosed
    case rateLimited          // HTTP 429 from Yahoo Finance
}

// MARK: - Private Decodable types

private struct YahooResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooResult]?
}

private struct YahooResult: Decodable {
    let meta:       YahooMeta
    let timestamp:  [TimeInterval]?
    let indicators: YahooIndicators
}

private struct YahooMeta: Decodable {
    let regularMarketPrice: Double
    // Present for intraday intervals (5m, 1h) only.
    // Absent for daily-bar intervals (1d) used by MTD and YTD — must be optional.
    let previousClose:      Double?
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    let close: [Double?]
}

// MARK: - Service

public actor YahooFinanceService {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    public func fetch(interval: ChartInterval, index: MarketIndex) async throws -> Quote {
        let url = try buildURL(for: interval, index: index)

        // Debug: log every outgoing request so URLs can be verified in a browser.
        print("[YahooFinanceService] → \(index.displayName) \(interval.rawValue) \(url.absoluteString)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            print("[YahooFinanceService] Network error: \(error)")
            throw SP500Error.networkError(error)
        }

        // Gate on HTTP status before attempting JSON decoding.
        // Without this check, 429/403 HTML bodies fail decoding and surface
        // as a misleading error message.
        if let http = response as? HTTPURLResponse {
            print("[YahooFinanceService] HTTP \(http.statusCode) ← \(index.displayName) \(interval.rawValue)")
            switch http.statusCode {
            case 200:
                break   // fall through to decode
            case 429:
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                print("[YahooFinanceService] Rate limited. Body: \(body.prefix(200))")
                throw SP500Error.rateLimited
            default:
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                print("[YahooFinanceService] Unexpected HTTP \(http.statusCode). Body: \(body.prefix(200))")
                throw SP500Error.networkError(URLError(.badServerResponse))
            }
        }

        return try decode(data: data, interval: interval, index: index)
    }

    // MARK: - URL construction

    private func buildURL(for interval: ChartInterval, index: MarketIndex) throws -> URL {
        let now       = Date()
        let startDate = interval.startDate()
        let spanDays  = now.timeIntervalSince(startDate) / 86_400

        var components = URLComponents()
        components.scheme = "https"
        components.host   = "query1.finance.yahoo.com"
        // Set the percent-encoded path directly so `^` is never passed raw.
        // `index.urlEncodedSymbol` converts `^GSPC` → `%5EGSPC`; BTC-USD is unchanged.
        components.percentEncodedPath = "/v8/finance/chart/\(index.urlEncodedSymbol)"
        components.queryItems = [
            URLQueryItem(name: "interval",       value: yahooIntervalParam(spanDays: spanDays)),
            URLQueryItem(name: "period1",        value: String(Int(startDate.timeIntervalSince1970))),
            URLQueryItem(name: "period2",        value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "includePrePost", value: "false")
        ]

        guard let url = components.url else { throw SP500Error.invalidURL }
        return url
    }

    /// Choose bar resolution based on the requested time span rather than a
    /// hardcoded mapping from ChartInterval.  This way WTD on a Monday (span
    /// ≈ 0–0.7 days) automatically uses the same 5-minute bars as 1D instead
    /// of the coarser 1-hour bars — making the two charts visually identical.
    ///
    ///   < 2 days  →  5m   (1D, or WTD when the week just started today)
    ///   < 8 days  →  1h   (WTD spanning Tue–Fri)
    ///   ≥ 8 days  →  1d   (MTD, YTD)
    private func yahooIntervalParam(spanDays: Double) -> String {
        if spanDays < 2 { return "5m" }
        if spanDays < 8 { return "1h" }
        return "1d"
    }

    // MARK: - Decoding

    private func decode(data: Data, interval: ChartInterval, index: MarketIndex) throws -> Quote {
        let response: YahooResponse
        do {
            response = try JSONDecoder().decode(YahooResponse.self, from: data)
        } catch {
            print("[YahooFinanceService] Decoding error: \(error)")
            throw SP500Error.decodingError(error)
        }

        // Empty result array → market closed / no data for this period
        guard let result = response.chart.result?.first else {
            throw SP500Error.marketClosed
        }

        let timestamps = result.timestamp ?? []
        let closes     = result.indicators.quote.first?.close ?? []

        // Zip timestamps with closes and drop any null close values.
        let points: [PricePoint] = zip(timestamps, closes).compactMap { ts, close in
            guard let close else { return nil }
            return PricePoint(date: Date(timeIntervalSince1970: ts), close: close)
        }

        // Fewer than 2 valid points means we can't draw a meaningful chart.
        guard points.count >= 2 else {
            throw SP500Error.marketClosed
        }

        // Baseline rule (set here, not in the ViewModel):
        //
        //   1D  → previousClose = prior session's closing price (Friday for Monday).
        //   WTD → previousClose = last Friday's close, i.e. "start of this week."
        //         Both 1D and WTD use intraday bars (5m or 1h) so previousClose is
        //         always present, including for BTC-USD.
        //   MTD / YTD → daily bars (1d) omit previousClose entirely; use the first
        //         point of the fetched period as the change baseline.
        let baselinePrice: Double
        switch interval {
        case .oneDay, .wtd:
            // previousClose is always present for intraday (5m / 1h) responses.
            // Fall back to first point only if the field is unexpectedly absent.
            baselinePrice = result.meta.previousClose ?? points[0].close
        case .mtd, .ytd:
            baselinePrice = points[0].close
        }

        return Quote(
            symbol:        index.rawValue,
            interval:      interval,
            currentPrice:  result.meta.regularMarketPrice,
            baselinePrice: baselinePrice,
            history:       points
        )
    }
}

// MARK: - SP500ServiceProtocol conformance
extension YahooFinanceService: SP500ServiceProtocol {}
