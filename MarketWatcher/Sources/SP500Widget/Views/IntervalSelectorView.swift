import SwiftUI

struct IntervalSelectorView: View {
    @Binding var selected: ChartInterval

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartInterval.allCases) { interval in
                Button {
                    selected = interval
                } label: {
                    Text(interval.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        // Active pill: white text on translucent white background.
                        // Inactive: gray text, no background — just the label floats.
                        .foregroundColor(selected == interval ? .white : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(selected == interval
                                      ? Color.white.opacity(0.2)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()  // left-align the buttons; Spacer pushes right
        }
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

// MARK: - Preview

#Preview {
    IntervalSelectorView(selected: .constant(.oneDay))
        .padding()
        .background(Color.widgetBG)
        .frame(width: 280)
}
