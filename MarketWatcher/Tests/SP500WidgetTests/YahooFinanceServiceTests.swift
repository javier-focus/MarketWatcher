import XCTest
@testable import MarketWatcher

// MARK: - MockURLProtocol

/// Intercepts every URLSession request and dispatches it to `requestHandler`.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - YahooFinanceServiceTests

final class YahooFinanceServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeService() -> YahooFinanceService {
        YahooFinanceService(session: makeMockSession())
    }

    /// Returns a 200 OK response for any URL.
    private func ok200() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    /// Loads a fixture JSON file from the test bundle.
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json",
                                    subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    // MARK: - testDecodes1DFixture

    func testDecodes1DFixture() async throws {
        let data = try fixture("mock_1d")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .oneDay, index: .sp500)

        // mock_1d has 5 timestamps and 4 non-null closes
        XCTAssertEqual(quote.symbol, "^GSPC")
        XCTAssertEqual(quote.interval, .oneDay)
        XCTAssertEqual(quote.history.count, 4)
        XCTAssertEqual(quote.currentPrice, 5123.41, accuracy: 0.001)
    }

    // MARK: - testFiltersNullCloses

    func testFiltersNullCloses() async throws {
        let data = try fixture("mock_1d")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .oneDay, index: .sp500)

        // mock_1d has 1 null at index 2 — exactly 4 valid points remain
        XCTAssertEqual(quote.history.count, 4)
        // Every remaining close must be a finite positive number
        XCTAssertTrue(quote.history.allSatisfy { $0.close.isFinite && $0.close > 0 })
    }

    // MARK: - testDecodesCurrentPrice

    func testDecodesCurrentPrice() async throws {
        let data = try fixture("mock_1d")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .oneDay, index: .sp500)

        XCTAssertEqual(quote.currentPrice, 5123.41, accuracy: 0.001)
    }

    // MARK: - testNetworkError

    func testNetworkError() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await makeService().fetch(interval: .oneDay, index: .sp500)
            XCTFail("Expected SP500Error.networkError to be thrown")
        } catch let error as SP500Error {
            guard case .networkError = error else {
                XCTFail("Wrong SP500Error case: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - testBaselineIs1DPreviousClose

    func testBaselineIs1DPreviousClose() async throws {
        let data = try fixture("mock_1d")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .oneDay, index: .sp500)

        // For 1D, baseline must come from meta.previousClose (5098.20), not history
        XCTAssertEqual(quote.baselinePrice, 5098.20, accuracy: 0.001)
        XCTAssertNotEqual(quote.baselinePrice, quote.history.first!.close)
    }

    // MARK: - testBaselineIsFirstPointForMTD

    func testBaselineIsFirstPointForMTD() async throws {
        // Reuse the YTD fixture — the interval enum controls baseline selection, not the data shape.
        // mock_ytd: first close = 4769.83, meta.previousClose = 5098.20
        let data = try fixture("mock_ytd")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .mtd, index: .sp500)

        // For MTD, baseline must be history.first?.close, not meta.previousClose
        XCTAssertEqual(quote.baselinePrice, 4769.83, accuracy: 0.001)
        XCTAssertNotEqual(quote.baselinePrice, 5098.20)
    }

    // MARK: - testMarketClosedHandling

    func testMarketClosedHandling() async {
        // mock_weekend has result: [] — empty array triggers .marketClosed
        let data = try! fixture("mock_weekend")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        do {
            _ = try await makeService().fetch(interval: .oneDay, index: .sp500)
            XCTFail("Expected SP500Error.marketClosed to be thrown")
        } catch SP500Error.marketClosed {
            // expected — test passes
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - testBaselineIsWTDPreviousClose

    func testBaselineIsWTDPreviousClose() async throws {
        // WTD now uses meta.previousClose (last Friday's close) as baseline —
        // the same rule as 1D.  This ensures that on Monday, when WTD and 1D
        // cover the same time range, they also show the same percentage change.
        //
        // mock_wtd: meta.previousClose = 5098.20, first close = 5050.25
        let data = try fixture("mock_wtd")
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, data) }

        let quote = try await makeService().fetch(interval: .wtd, index: .sp500)

        XCTAssertEqual(quote.baselinePrice, 5098.20, accuracy: 0.001)
        XCTAssertNotEqual(quote.baselinePrice, quote.history.first!.close)
    }

    // MARK: - testDecodingErrorOnBadJSON

    func testDecodingErrorOnBadJSON() async {
        let garbage = Data("not json at all".utf8)
        MockURLProtocol.requestHandler = { [ok = ok200()] _ in (ok, garbage) }

        do {
            _ = try await makeService().fetch(interval: .oneDay, index: .sp500)
            XCTFail("Expected SP500Error.decodingError to be thrown")
        } catch let error as SP500Error {
            guard case .decodingError = error else {
                XCTFail("Wrong SP500Error case: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
