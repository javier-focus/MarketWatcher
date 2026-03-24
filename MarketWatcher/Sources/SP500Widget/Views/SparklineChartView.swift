import Charts
import SwiftUI

struct SparklineChartView: View {
    let history:    [PricePoint]
    let isPositive: Bool
    let interval:   ChartInterval

    var body: some View {
        Chart(history, id: \.date) { point in
            // Gradient fill beneath the line — top opacity 0.35 fades to clear.
            AreaMark(
                x: .value("Time",  point.date),
                y: .value("Price", point.close)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [chartColor.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint:   .bottom
                )
            )

            // Line on top of the fill.
            LineMark(
                x: .value("Time",  point.date),
                y: .value("Price", point.close)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(chartColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

        }
        // Tight Y domain — 0.2 % headroom so data fills the frame without
        // the line hugging the very top/bottom edge.
        .chartYScale(domain: yMin...yMax)
        // X axis: interval-specific stride marks with subtle chrome.
        .chartXAxis {
            switch interval {
            case .oneDay:
                // Fine grid every hour so every hour boundary gets a line …
                AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.12))
                }
                // … but labels only every 2 hours to avoid crowding.
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xLabel(for: date))
                                .font(.caption2)
                                .foregroundStyle(Color.gray)
                        }
                    }
                }
            default:
                // One grid line + one label per natural boundary for WTD/MTD/YTD.
                AxisMarks(values: xAxisStride) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.12))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xLabel(for: date))
                                .font(.caption2)
                                .foregroundStyle(Color.gray)
                        }
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        // Clear the plot background and add 4 pt bottom breathing room so the
        // area fill doesn't bleed flush to the bottom edge of the chart frame.
        .chartPlotStyle { plot in
            plot.background(.clear)
                .padding(.bottom, 4)
        }
        .chartBackground { _ in Color.clear }
        .frame(height: 62)
        .animation(.easeInOut(duration: 0.3), value: history)
    }

    // MARK: - Derived values

    private var chartColor: Color {
        isPositive ? .chartGreen : .chartRed
    }

    private var yMin: Double {
        // 0.2 % below the data minimum — tight but avoids clipping.
        (history.map(\.close).min() ?? 0) * 0.998
    }

    private var yMax: Double {
        // 0.2 % above the data maximum for symmetry.
        (history.map(\.close).max() ?? 1) * 1.002
    }

    // MARK: - X axis configuration

    /// Stride values for WTD / MTD / YTD — 1D is handled inline with two
    /// separate AxisMarks blocks (grid every hour, label every 2 hours).
    private var xAxisStride: AxisMarkValues {
        switch interval {
        case .oneDay: return .stride(by: .hour,  count: 2)  // unused; handled above
        case .wtd:    return .stride(by: .day,   count: 1)  // Mon Tue Wed …
        case .mtd:    return .stride(by: .day,   count: 7)  // 1  8  15  22
        case .ytd:    return .stride(by: .month, count: 1)  // Jan Feb Mar …
        }
    }

    /// Format a tick date for its interval context.
    private func xLabel(for date: Date) -> String {
        let f = DateFormatter()
        switch interval {
        case .oneDay: f.dateFormat = "ha"   // "9AM", "12PM", "3PM"
        case .wtd:    f.dateFormat = "EEE"  // "Mon", "Tue"
        case .mtd:    f.dateFormat = "d"    // "1", "8", "15", "22"
        case .ytd:    f.dateFormat = "MMM"  // "Jan", "Feb", "Mar"
        }
        return f.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let now = Date()
    let history: [PricePoint] = stride(from: -78, through: 0, by: 1).map { i in
        PricePoint(
            date:  now.addingTimeInterval(Double(i) * 300),  // 5-min bars, ~6.5 h
            close: 5_000 + Double(i) * 0.8 + Double.random(in: -12...12)
        )
    }
    return SparklineChartView(
        history:    history,
        isPositive: true,
        interval:   .oneDay
    )
    .padding()
    .background(Color.widgetBG)
    .frame(width: 340)
}
