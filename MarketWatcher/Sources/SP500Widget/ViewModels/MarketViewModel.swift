import Combine
import Foundation

// MARK: - ViewState

public enum ViewState {
    case loading
    case success(Quote)
    case error(String)
}

extension ViewState: Equatable {
    public static func == (lhs: ViewState, rhs: ViewState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):               return true
        case (.success(let a), .success(let b)): return a == b
        case (.error(let a),   .error(let b)):   return a == b
        default:                                 return false
        }
    }
}

// MARK: - MarketViewModel

@MainActor
public final class MarketViewModel: ObservableObject {

    @Published public var selectedInterval: ChartInterval = .oneDay

    /// Currently displayed market index. Persisted to UserDefaults ("selectedIndex").
    /// Changing this resets the price and triggers a full fresh load.
    @Published public var selectedIndex: MarketIndex = {
        let raw = UserDefaults.standard.string(forKey: "selectedIndex") ?? ""
        return MarketIndex(rawValue: raw) ?? .sp500
    }()

    @Published public var state: ViewState = .loading

    /// The most recent market price, updated on every successful fetch.
    /// Kept separate from `state` so it persists across interval switches —
    /// the big price number stays visible and stable while the chart re-fetches.
    /// Reset to nil on index change so the full loading spinner is shown.
    @Published public private(set) var currentPrice: Double? = nil

    /// Set to `true` while silently re-fetching after the first successful load.
    /// The UI shows a subtle spinner instead of blanking to a full loading screen.
    @Published public private(set) var isRefreshing: Bool = false

    /// Timestamp of the last successful data fetch, for the "Updated" label.
    /// Reset to nil on index change alongside `currentPrice`.
    @Published public private(set) var lastUpdated: Date? = nil

    // Stored so tests can `await vm.pendingLoadTask?.value` after changing
    // selectedInterval or selectedIndex, giving the spawned Task time to complete.
    public private(set) var pendingLoadTask: Task<Void, Never>?

    private let service: any SP500ServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var consecutiveRateLimitErrors = 0

    // Two independent Combine sinks — one for interval changes, one for index
    // changes — keep the ViewModel's reload logic fully owned here, independent
    // of the View layer.  Both use dropFirst() to skip the initial emission at
    // subscription time; the first load() is triggered explicitly by the View's .task.
    private var intervalCancellable: AnyCancellable?
    private var indexCancellable:    AnyCancellable?

    public init(service: any SP500ServiceProtocol = YahooFinanceService()) {
        self.service = service

        // Interval change: keep current price visible (isRefreshing overlay).
        intervalCancellable = $selectedInterval
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.pendingLoadTask = Task { await self.load() }
            }

        // Index change: reset price + timestamp so the full spinner is shown
        // for the new index, then persist the selection and reload.
        indexCancellable = $selectedIndex
            .dropFirst()
            .sink { [weak self] newIndex in
                guard let self else { return }
                UserDefaults.standard.set(newIndex.rawValue, forKey: "selectedIndex")
                self.currentPrice = nil
                self.lastUpdated  = nil
                self.pendingLoadTask = Task { await self.load() }
            }
    }

    deinit {
        refreshTask?.cancel()
        pendingLoadTask?.cancel()
        intervalCancellable?.cancel()
        indexCancellable?.cancel()
    }

    // MARK: - Public API

    public func load() async {
        refreshTask?.cancel()

        // First load (or after index change): show the full loading spinner.
        // Subsequent interval switches / auto-refreshes: keep the last
        // successful state visible and show only a subtle spinner overlay.
        if currentPrice == nil {
            state = .loading
        } else {
            isRefreshing = true
        }

        do {
            let quote = try await service.fetch(interval: selectedInterval,
                                                index:    selectedIndex)
            currentPrice  = quote.currentPrice
            lastUpdated   = Date()
            consecutiveRateLimitErrors = 0
            isRefreshing  = false
            state = .success(quote)
            scheduleRefresh(isRateLimited: false)
        } catch SP500Error.rateLimited {
            isRefreshing = false
            state = .error(humanReadable(SP500Error.rateLimited))
            scheduleRefresh(isRateLimited: true, isError: false)
        } catch {
            isRefreshing = false
            state = .error(humanReadable(error))
            scheduleRefresh(isRateLimited: false, isError: true)
        }
    }

    // MARK: - Auto-refresh

    private func scheduleRefresh(isRateLimited: Bool, isError: Bool = false) {
        refreshTask?.cancel()

        let delay: UInt64
        if isRateLimited {
            // Exponential back-off: 5 min → 10 min → 20 min, then capped.
            let delayMinutes = min(5 * (1 << consecutiveRateLimitErrors), 20)
            consecutiveRateLimitErrors = min(consecutiveRateLimitErrors + 1, 2)
            print("[MarketViewModel] Rate limited (\(consecutiveRateLimitErrors)×). Retrying in \(delayMinutes) min.")
            delay = UInt64(delayMinutes) * 60_000_000_000
        } else if isError {
            delay = 30_000_000_000  // 30 s — recover quickly from transient network errors
        } else {
            delay = 5 * 60_000_000_000  // 5 min normal refresh
        }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil  // prevent load() from cancelling this task
            await self.load()
        }
    }

    // MARK: - Human-readable error messages

    private func humanReadable(_ error: Error) -> String {
        switch error as? SP500Error {
        case .rateLimited:
            return "Too many requests. Retrying automatically in a few minutes."
        case .networkError:
            return "Connection error. Check your network and try again."
        case .marketClosed:
            // BTC trades 24/7 — "market closed" makes no sense for it.
            if selectedIndex.tradesAroundTheClock {
                return "No data available for this period."
            }
            return "Market is closed. Data will refresh when trading resumes."
        case .emptyData:
            return "No data available for this period."
        case .decodingError:
            return "Couldn't load \(selectedIndex.displayName) data. Please try again."
        case .invalidURL:
            return "Configuration error. Please restart the app."
        case nil:
            return "Something went wrong. Please try again."
        }
    }
}
