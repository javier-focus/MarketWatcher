import Foundation

/// All market indexes the widget can display.
public enum MarketIndex: String, CaseIterable, Identifiable {
    case sp500       = "^GSPC"
    case nasdaq      = "^IXIC"
    case dowJones    = "^DJI"
    case russell2000 = "^RUT"
    case vix         = "^VIX"
    case bitcoin     = "BTC-USD"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sp500:        return "S&P 500"
        case .nasdaq:       return "Nasdaq"
        case .dowJones:     return "Dow Jones"
        case .russell2000:  return "Russell 2000"
        case .vix:          return "VIX"
        case .bitcoin:      return "Bitcoin"
        }
    }

    /// Bitcoin trades 24/7; all other indexes follow NYSE market hours.
    public var tradesAroundTheClock: Bool { self == .bitcoin }

    /// Percent-encodes `^` → `%5E` so the symbol is safe in a URL path component.
    /// `BTC-USD` requires no encoding — the hyphen is valid in a URL path.
    public var urlEncodedSymbol: String {
        rawValue.replacingOccurrences(of: "^", with: "%5E")
    }
}
