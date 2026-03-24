import XCTest
@testable import MarketWatcher

// MARK: - MockSP500Service

/// Synchronous, in-memory service. Thread-safety note: fetchCallCount is only
/// ever mutated/read from the main actor in these tests, so @unchecked Sendable
/// is safe here — we never access it concurrently.
final class MockSP500Service: SP500ServiceProtocol, @unchecked Sendable {
    var result: Result<Quote, Error>
    private(set) var fetchCallCount = 0
    private(set) var lastInterval:  ChartInterval?
    private(set) var lastIndex:     MarketIndex?

    init(result: Result<Quote, Error>) {
        self.result = result
    }

    func fetch(interval: ChartInterval, index: MarketIndex) async throws -> Quote {
        fetchCallCount += 1
        lastInterval = interval
        lastIndex    = index
        return try result.get()
    }
}

// MARK: - Shared fixture

private func sampleQuote(interval: ChartInterval = .oneDay,
                         index:    MarketIndex    = .sp500) -> Quote {
    let t = Date()
    return Quote(
        symbol:        index.rawValue,
        interval:      interval,
        currentPrice:  5123.41,
        baselinePrice: 5098.20,
        history: [
            PricePoint(date: t.addingTimeInterval(-300), close: 5098.20),
            PricePoint(date: t,                          close: 5123.41)
        ]
    )
}

// MARK: - Tests

// Marking the whole class @MainActor keeps every test on the main actor,
// matching MarketViewModel's own isolation and avoiding data-race warnings.
@MainActor
final class MarketViewModelTests: XCTestCase {

    // MARK: testInitialStateIsLoading

    func testInitialStateIsLoading() {
        let vm = MarketViewModel(service: MockSP500Service(result: .success(sampleQuote())))
        // dropFirst() in the Combine sinks means no load is triggered at init —
        // state must remain .loading until the View calls load() in onAppear.
        guard case .loading = vm.state else {
            XCTFail("Expected .loading on fresh init, got \(vm.state)")
            return
        }
    }

    // MARK: testSuccessStatePopulatesQuote

    func testSuccessStatePopulatesQuote() async {
        let expected = sampleQuote()
        let vm = MarketViewModel(service: MockSP500Service(result: .success(expected)))

        await vm.load()

        guard case .success(let quote) = vm.state else {
            XCTFail("Expected .success, got \(vm.state)")
            return
        }
        XCTAssertEqual(quote.symbol,        "^GSPC")
        XCTAssertEqual(quote.currentPrice,  5123.41, accuracy: 0.001)
        XCTAssertEqual(quote.baselinePrice, 5098.20, accuracy: 0.001)
        XCTAssertEqual(quote.history.count, 2)
    }

    // MARK: testIntervalSwitchTriggersRefetch

    func testIntervalSwitchTriggersRefetch() async {
        let mock = MockSP500Service(result: .success(sampleQuote()))
        let vm   = MarketViewModel(service: mock)

        await vm.load()
        XCTAssertEqual(mock.fetchCallCount, 1, "One fetch after explicit load()")

        // The Combine sink fires synchronously, spawning a Task stored in pendingLoadTask.
        vm.selectedInterval = .wtd
        // Awaiting the task gives it time to complete without relying on sleep.
        await vm.pendingLoadTask?.value

        XCTAssertEqual(mock.fetchCallCount,  2,    "Should have fetched again after interval change")
        XCTAssertEqual(mock.lastInterval,    .wtd, "Should have used the new interval")
    }

    // MARK: testIndexSwitchResetsAndRefetches

    func testIndexSwitchResetsAndRefetches() async {
        let mock = MockSP500Service(result: .success(sampleQuote()))
        let vm   = MarketViewModel(service: mock)

        await vm.load()
        XCTAssertNotNil(vm.currentPrice, "Price populated after first load")
        XCTAssertEqual(mock.fetchCallCount, 1)

        // Switching index must reset currentPrice (so full spinner shows)
        // and trigger a new fetch with the new index.
        vm.selectedIndex = .nasdaq
        await vm.pendingLoadTask?.value

        XCTAssertEqual(mock.fetchCallCount, 2,       "Should have fetched again after index change")
        XCTAssertEqual(mock.lastIndex,      .nasdaq,  "Should have used the new index")
    }

    // MARK: testIndexSwitchClearsPrice

    func testIndexSwitchClearsPrice() async {
        // Use a service that always succeeds so the first load populates currentPrice.
        let mock = MockSP500Service(result: .success(sampleQuote()))
        let vm   = MarketViewModel(service: mock)
        await vm.load()

        // Now make the service fail so the next fetch doesn't repopulate currentPrice.
        mock.result = .failure(SP500Error.networkError(URLError(.notConnectedToInternet)))

        // Changing the index resets currentPrice to nil synchronously (before fetch).
        vm.selectedIndex = .bitcoin
        // currentPrice must be nil at this point — before the Task completes.
        XCTAssertNil(vm.currentPrice, "currentPrice must be cleared on index switch")
        XCTAssertNil(vm.lastUpdated,  "lastUpdated must be cleared on index switch")
    }

    // MARK: testErrorStateOnFailure

    func testErrorStateOnFailure() async {
        let mock = MockSP500Service(
            result: .failure(SP500Error.networkError(URLError(.notConnectedToInternet)))
        )
        let vm = MarketViewModel(service: mock)

        await vm.load()

        guard case .error = vm.state else {
            XCTFail("Expected .error state, got \(vm.state)")
            return
        }
    }

    // MARK: testErrorMessageIsHumanReadable

    func testErrorMessageIsHumanReadable() async {
        let mock = MockSP500Service(
            result: .failure(SP500Error.networkError(URLError(.notConnectedToInternet)))
        )
        let vm = MarketViewModel(service: mock)

        await vm.load()

        guard case .error(let message) = vm.state else {
            XCTFail("Expected .error state")
            return
        }
        // Must not expose Swift internals
        XCTAssertFalse(message.contains("SP500Error"),   "Leaks error type name")
        XCTAssertFalse(message.contains("networkError"), "Leaks enum case name")
        XCTAssertFalse(message.contains("URLError"),     "Leaks URLError type name")
        XCTAssertFalse(message.contains("Code="),        "Leaks URLError code string")
        // Must be a meaningful sentence (not just a short code or empty string)
        XCTAssertGreaterThan(message.count, 10)
    }

    // MARK: testErrorMessageForEachCase

    func testErrorMessageForMarketClosed() async {
        let vm = MarketViewModel(service: MockSP500Service(result: .failure(SP500Error.marketClosed)))
        await vm.load()
        guard case .error(let msg) = vm.state else { XCTFail("Expected .error"); return }
        XCTAssertFalse(msg.contains("marketClosed"))
        XCTAssertGreaterThan(msg.count, 10)
    }

    func testErrorMessageForDecodingError() async {
        let vm = MarketViewModel(
            service: MockSP500Service(result: .failure(SP500Error.decodingError(URLError(.cannotParseResponse))))
        )
        await vm.load()
        guard case .error(let msg) = vm.state else { XCTFail("Expected .error"); return }
        XCTAssertFalse(msg.contains("decodingError"))
        XCTAssertGreaterThan(msg.count, 10)
    }

    // MARK: testTimerCancelledOnDeinit

    func testTimerCancelledOnDeinit() async {
        let mock = MockSP500Service(result: .success(sampleQuote()))
        weak var weakVM: MarketViewModel?

        // Scope block: vm is the only strong reference
        do {
            let vm = MarketViewModel(service: mock)
            weakVM = vm
            await vm.load()
            // vm goes out of scope → reference count hits 0 → deinit called,
            // which cancels refreshTask, intervalCancellable, and indexCancellable.
        }

        // One yield lets the main actor process any actor-hop from deinit
        // before we assert deallocation.
        await Task.yield()

        XCTAssertNil(
            weakVM,
            "MarketViewModel was not deallocated — likely a retain cycle " +
            "in refreshTask or Combine sink (check [weak self] captures)"
        )
    }
}
