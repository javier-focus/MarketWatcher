import Foundation

/// A single price sample returned by the chart API.
public struct PricePoint: Equatable {
    public let date:  Date
    public let close: Double

    public init(date: Date, close: Double) {
        self.date  = date
        self.close = close
    }
}

/// A fully resolved quote ready for display.
///
/// `baselinePrice` is set by `YahooFinanceService`:
///   - `.oneDay`               → `meta.previousClose` from the Yahoo response
///   - `.wtd / .mtd / .ytd`   → `history.first?.close` (first point of the period)
public struct Quote: Equatable {
    public let symbol:        String
    public let interval:      ChartInterval
    public let currentPrice:  Double
    public let baselinePrice: Double
    public let history:       [PricePoint]

    public init(
        symbol:        String,
        interval:      ChartInterval,
        currentPrice:  Double,
        baselinePrice: Double,
        history:       [PricePoint]
    ) {
        self.symbol        = symbol
        self.interval      = interval
        self.currentPrice  = currentPrice
        self.baselinePrice = baselinePrice
        self.history       = history
    }

    public var pointsChange: Double { currentPrice - baselinePrice }

    public var percentChange: Double {
        guard baselinePrice != 0 else { return 0 }
        return (pointsChange / baselinePrice) * 100
    }

    public var isPositive: Bool { pointsChange >= 0 }
}
