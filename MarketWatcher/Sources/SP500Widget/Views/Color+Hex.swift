import SwiftUI

extension Color {
    /// Initialise a Color from a CSS-style hex string, e.g. "#1C1C1E" or "1C1C1E".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

extension Color {
    static let chartGreen = Color(hex: "#30D158")
    static let chartRed   = Color(hex: "#FF453A")
    static let widgetBG   = Color(hex: "#1C1C1E")
}
