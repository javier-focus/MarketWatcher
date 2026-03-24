import Foundation

public enum ChartInterval: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case wtd    = "WTD"
    case mtd    = "MTD"
    case ytd    = "YTD"

    public var id: String { rawValue }

    /// Returns the period start date for this interval.
    /// All arithmetic is performed in the America/New_York timezone.
    /// Accepts `reference` and `calendar` as parameters for testability.
    public func startDate(
        relativeTo reference: Date = Date(),
        calendar: Calendar = .etCalendar
    ) -> Date {
        let startOfToday = calendar.startOfDay(for: reference)

        switch self {
        case .oneDay:
            return startOfToday

        case .wtd:
            // weekday: 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat
            // daysFromMonday: Mon=0 Tue=1 Wed=2 Thu=3 Fri=4 Sat=5 Sun=6
            let weekday = calendar.component(.weekday, from: startOfToday)
            let daysFromMonday = (weekday + 5) % 7
            return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfToday)!

        case .mtd:
            let components = calendar.dateComponents([.year, .month], from: reference)
            return calendar.date(from: components)!

        case .ytd:
            var components = DateComponents()
            components.year  = calendar.component(.year, from: reference)
            components.month = 1
            components.day   = 1
            return calendar.date(from: components)!
        }
    }
}

extension Calendar {
    public static let etCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()
}
