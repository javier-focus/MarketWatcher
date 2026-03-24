import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var viewModel: MarketViewModel

    public init() {}

    public var body: some View {
        ZStack {
            // Full-bleed dark background — NSPanel background is set to .clear
            // in AppDelegate so only this rounded rect is visible.
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.widgetBG)
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)

            content

            // Subtle top-right spinner shown during silent background refreshes
            // (interval switch or auto-refresh after first successful load).
            // Does NOT replace the content — the price and chart stay visible.
            if viewModel.isRefreshing {
                VStack {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white.opacity(0.45))
                            .scaleEffect(0.55)
                            .padding(.top, 10)
                            .padding(.trailing, 12)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 344, minHeight: 164)
        // Extend into the titlebar safe-area so the RoundedRectangle fills the
        // full panel frame with no transparent gap at the top. AppDelegate sets
        // titlebarAppearsTransparent + fullSizeContentView, but SwiftUI still
        // reserves safe-area insets for the (invisible) titlebar unless told not to.
        .ignoresSafeArea()
        // Kick off the first data fetch when the panel becomes visible.
        // Subsequent loads are driven by the Combine sink (interval changes)
        // and the auto-refresh Task inside MarketViewModel.
        .task { await viewModel.load() }
    }

    // MARK: - State-driven content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {

        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)

        case .success(let quote):
            VStack(alignment: .leading, spacing: 4) {
                // displayPrice uses the sticky currentPrice from the ViewModel so
                // the big number doesn't jump when the user switches intervals —
                // only the chart and change chip update while the fetch runs.
                PriceHeaderView(
                    displayPrice:  viewModel.currentPrice ?? quote.currentPrice,
                    lastUpdated:   viewModel.lastUpdated,
                    quote:         quote,
                    selectedIndex: $viewModel.selectedIndex
                )
                SparklineChartView(
                    history:    quote.history,
                    isPositive: quote.isPositive,
                    interval:   quote.interval
                )
                // Absorbs any extra height so the header+chart stay pinned to
                // the top and the interval selector stays pinned to the bottom.
                // Without this, the ZStack centers the VStack and creates large
                // dead zones at the top and bottom edges.
                Spacer(minLength: 0)
                IntervalSelectorView(selected: $viewModel.selectedInterval)
            }
            // Fill the full ZStack frame and anchor to the top-left corner.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            // Smooth cross-fade whenever the quote data is replaced
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: quote)

        case .error(let message):
            VStack(spacing: 12) {
                Spacer()

                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                // Keep the interval selector visible in error state so the user
                // can switch to a working interval (e.g. back to 1D from MTD).
                // The Combine sink in MarketViewModel fires load() automatically
                // on any selectedInterval change — no extra wiring needed here.
                IntervalSelectorView(selected: $viewModel.selectedInterval)
            }
            .padding(16)
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = MarketViewModel(service: PreviewService())
    return ContentView()
        .environmentObject(vm)
        .frame(width: 340, height: 185)
}

// Minimal preview service — not compiled into the production target.
private struct PreviewService: SP500ServiceProtocol {
    func fetch(interval: ChartInterval, index: MarketIndex) async throws -> Quote {
        let now = Date()
        return Quote(
            symbol:        "^GSPC",
            interval:      interval,
            currentPrice:  5_123.41,
            baselinePrice: 4_953.17,
            history: stride(from: -30, through: 0, by: 1).map { offset in
                PricePoint(
                    date:  now.addingTimeInterval(Double(offset) * 3600),
                    close: 4_953.17 + Double.random(in: 0...180)
                )
            }
        )
    }
}
