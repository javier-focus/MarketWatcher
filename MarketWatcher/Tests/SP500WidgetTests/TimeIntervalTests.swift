import XCTest
@testable import MarketWatcher

final class TimeIntervalTests: XCTestCase {

    // Fixed ET calendar — same one the production code uses
    private let cal = Calendar.etCalendar

    // Convenience: build a noon-ET date to stay clear of DST boundary edge cases
    private func etDate(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return cal.date(from: c)!
    }

    private func ymd(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    // MARK: - 1D

    func testOneDayStartIsSameCalendarDay() {
        let wednesday = etDate(year: 2025, month: 3, day: 19)
        let start = ChartInterval.oneDay.startDate(relativeTo: wednesday, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.year,  2025)
        XCTAssertEqual(result.month, 3)
        XCTAssertEqual(result.day,   19)
    }

    // MARK: - WTD

    func testWTD_givenWednesday_returnsMonday() {
        // Wed 19 Mar 2025 → Mon 17 Mar 2025
        let wednesday = etDate(year: 2025, month: 3, day: 19)
        let start = ChartInterval.wtd.startDate(relativeTo: wednesday, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.day, 17)
        XCTAssertEqual(cal.component(.weekday, from: start), 2) // 2 = Monday
    }

    func testWTD_givenFriday_returnsMonday() {
        // Fri 21 Mar 2025 → Mon 17 Mar 2025
        let friday = etDate(year: 2025, month: 3, day: 21)
        let start = ChartInterval.wtd.startDate(relativeTo: friday, calendar: cal)
        XCTAssertEqual(ymd(start).day, 17)
    }

    func testWTD_givenMonday_returnsSameDay() {
        // Mon 17 Mar 2025 → Mon 17 Mar 2025 (no rollback)
        let monday = etDate(year: 2025, month: 3, day: 17)
        let start = ChartInterval.wtd.startDate(relativeTo: monday, calendar: cal)
        XCTAssertEqual(ymd(start).day, 17)
    }

    func testWTD_givenSunday_returnsPreviousMonday() {
        // Sun 23 Mar 2025 → Mon 17 Mar 2025
        let sunday = etDate(year: 2025, month: 3, day: 23)
        let start = ChartInterval.wtd.startDate(relativeTo: sunday, calendar: cal)
        XCTAssertEqual(ymd(start).day, 17)
    }

    func testWTD_givenTuesday_returnsMonday() {
        let tuesday = etDate(year: 2025, month: 3, day: 18)
        let start = ChartInterval.wtd.startDate(relativeTo: tuesday, calendar: cal)
        XCTAssertEqual(ymd(start).day, 17)
    }

    func testWTD_rollsBackAcrossMonthBoundary() {
        // Wed 2 Apr 2025 → Mon 31 Mar 2025
        let wednesday = etDate(year: 2025, month: 4, day: 2)
        let start = ChartInterval.wtd.startDate(relativeTo: wednesday, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.month, 3)
        XCTAssertEqual(result.day,   31)
    }

    // MARK: - MTD

    func testMTD_givenMidMonth_returnsFirstOfMonth() {
        let midMonth = etDate(year: 2025, month: 3, day: 15)
        let start = ChartInterval.mtd.startDate(relativeTo: midMonth, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.year,  2025)
        XCTAssertEqual(result.month, 3)
        XCTAssertEqual(result.day,   1)
    }

    func testMTD_givenFirstOfMonth_returnsSameDay() {
        let firstOfMonth = etDate(year: 2025, month: 3, day: 1)
        let start = ChartInterval.mtd.startDate(relativeTo: firstOfMonth, calendar: cal)
        XCTAssertEqual(ymd(start).day, 1)
    }

    func testMTD_givenLastDayOfMonth_returnsFirstOfMonth() {
        let lastDay = etDate(year: 2025, month: 3, day: 31)
        let start = ChartInterval.mtd.startDate(relativeTo: lastDay, calendar: cal)
        XCTAssertEqual(ymd(start).day, 1)
    }

    // MARK: - YTD

    func testYTD_givenMidYear_returnsJanFirst() {
        let midYear = etDate(year: 2025, month: 7, day: 15)
        let start = ChartInterval.ytd.startDate(relativeTo: midYear, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.year,  2025)
        XCTAssertEqual(result.month, 1)
        XCTAssertEqual(result.day,   1)
    }

    func testYTD_givenJanFirst_returnsSameDay() {
        let janFirst = etDate(year: 2025, month: 1, day: 1)
        let start = ChartInterval.ytd.startDate(relativeTo: janFirst, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.month, 1)
        XCTAssertEqual(result.day,   1)
    }

    func testYTD_givenDecember_returnsJanFirstSameYear() {
        let dec = etDate(year: 2025, month: 12, day: 31)
        let start = ChartInterval.ytd.startDate(relativeTo: dec, calendar: cal)
        let result = ymd(start)
        XCTAssertEqual(result.year,  2025)
        XCTAssertEqual(result.month, 1)
        XCTAssertEqual(result.day,   1)
    }
}
