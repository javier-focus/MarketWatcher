import SwiftUI

// Passes the chip's rendered width up through the view tree so the Picker
// can be constrained to match it. Uses `nextValue()` (not `max`) so the
// most-recently-measured value always wins — there is only one chip in the tree.
private struct ChipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PriceHeaderView: View {
    let displayPrice:    Double   // sticky — doesn't change on interval switch
    let lastUpdated:     Date?
    let quote:           Quote    // used for change chip only (pointsChange / percentChange)
    @Binding var selectedIndex: MarketIndex

    /// Captured from the chip's GeometryReader; drives the Picker's frame width.
    /// Starts at 0 (no constraint) until the first layout pass completes.
    @State private var chipWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // ── Left column ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {

                // Picker width is pinned to the chip width measured below.
                // Using .frame(width:) on a native NSPopUpButton is the only
                // approach that reliably overrides its intrinsic content size —
                // .fixedSize / .frame(maxWidth:) are both ignored by AppKit.
                Picker("Index", selection: $selectedIndex) {
                    ForEach(MarketIndex.allCases) { index in
                        Text(index.displayName).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: chipWidth > 0 ? chipWidth : nil, alignment: .leading)

                // Measure the chip's rendered width on every layout pass and
                // propagate it upward via the preference key.
                changeChip
                    .overlay(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ChipWidthKey.self,
                                value: geo.size.width
                            )
                        }
                    )
            }
            // Read the preference one level up so it's available to the Picker sibling.
            // Guard against no-op updates to prevent layout thrash.
            .onPreferenceChange(ChipWidthKey.self) { w in
                if w != chipWidth { chipWidth = w }
            }

            Spacer()

            // ── Right column ───────────────────────────────────────────────
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedPrice)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let date = lastUpdated {
                    Text(updatedLabel(date))
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Change chip

    private var changeChip: some View {
        Text(chipText)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(chipColor)
            )
    }

    // MARK: - Formatted values

    private var formattedPrice: String {
        priceFormatter.string(from: NSNumber(value: displayPrice)) ?? "--"
    }

    private var chipText: String {
        let pts  = quote.pointsChange
        let pct  = quote.percentChange
        let sign = pts >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pts))  \(sign)\(String(format: "%.2f", pct))%"
    }

    private var chipColor: Color {
        quote.isPositive ? .chartGreen : .chartRed
    }

    private func updatedLabel(_ date: Date) -> String {
        "Updated \(timeFormatter.string(from: date))"
    }

    // MARK: - Formatters

    private var priceFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle           = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let quote = Quote(
        symbol:        "^GSPC",
        interval:      .oneDay,
        currentPrice:  5_123.41,
        baselinePrice: 5_098.20,
        history: [
            PricePoint(date: now.addingTimeInterval(-300), close: 5_098.20),
            PricePoint(date: now,                          close: 5_123.41)
        ]
    )
    return PriceHeaderView(
        displayPrice:  5_123.41,
        lastUpdated:   now,
        quote:         quote,
        selectedIndex: .constant(.sp500)
    )
    .padding()
    .background(Color.widgetBG)
}
