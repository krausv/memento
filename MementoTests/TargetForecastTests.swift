import XCTest
@testable import Memento

final class TargetForecastTests: XCTestCase {
    private let calendar = Calendar.prague
    private let schedule = ReminderSettings() // Po–Pá 9–17

    private func date(_ d: Int, _ h: Int = 7, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    private func forecast(amount: Decimal, target: Decimal = 70_000, rate: Decimal = 1000, now: Date) -> TargetForecast? {
        TargetForecast.compute(status: TargetStatus(amount: amount, target: target), hourlyRate: rate,
                               now: now, schedule: schedule)
    }

    func testCapacityCountsRemainingWorkdaysIncludingTodayRemainder() {
        // Středa 21. 10. v 7:00: zbývá celý dnešek (8 h) + čt, pá + 4 týdny od 26. do 30. (5 dnů) = 8 dní.
        let (seconds, days) = TargetForecast.capacityLeft(now: date(21), schedule: schedule)
        XCTAssertEqual(days, 8)
        XCTAssertEqual(seconds, 8 * 8 * 3600)
    }

    func testTodayCapacityShrinksDuringTheDay() {
        // V 13:00 zbývají dnes 4 h.
        let (seconds, days) = TargetForecast.capacityLeft(now: date(21, 13), schedule: schedule)
        XCTAssertEqual(days, 8)
        XCTAssertEqual(seconds, (4 + 7 * 8) * 3600)
        // Po konci pracovní doby dnešek nepočítá.
        let evening = TargetForecast.capacityLeft(now: date(21, 18), schedule: schedule)
        XCTAssertEqual(evening.days, 7)
    }

    func testWeekendHasNoCapacity() {
        // Sobota 31. 10. – už nic nezbývá.
        let (seconds, days) = TargetForecast.capacityLeft(now: date(31, 10), schedule: schedule)
        XCTAssertEqual(seconds, 0)
        XCTAssertEqual(days, 0)
    }

    func testRemainingHoursFromMissingAmount() {
        let f = forecast(amount: 52_700, now: date(21))!
        XCTAssertEqual(f.remainingSeconds, Int(17.3 * 3600))
    }

    func testVerdicts() {
        // Kapacita 64 h; 80 % = 51,2 h.
        XCTAssertEqual(forecast(amount: 30_000, now: date(21))?.verdict, .realistic)   // chybí 40 h
        XCTAssertEqual(forecast(amount: 15_000, now: date(21))?.verdict, .tight)       // chybí 55 h
        XCTAssertEqual(forecast(amount: 0, now: date(21))?.verdict, .unrealistic)      // chybí 70 h
        XCTAssertEqual(forecast(amount: 10_000, now: date(31, 10))?.verdict, .unrealistic, "žádná kapacita")
    }

    func testReachedWhenOnOrOverTarget() {
        let on = forecast(amount: 69_000, now: date(21))!
        XCTAssertEqual(on.verdict, .reached)
        XCTAssertEqual(on.remainingSeconds, 0)
        XCTAssertEqual(forecast(amount: 80_000, now: date(21))?.verdict, .reached)
    }

    func testRequiredPerDay() {
        let f = forecast(amount: 30_000, now: date(21))!
        XCTAssertEqual(f.requiredPerDaySeconds, 40 * 3600 / 8)
        XCTAssertNil(forecast(amount: 0, now: date(31, 10))?.requiredPerDaySeconds)
    }

    func testNoForecastWithoutRate() {
        XCTAssertNil(forecast(amount: 0, rate: 0, now: date(21)))
    }

    func testCustomSchedule() {
        var s = ReminderSettings()
        s.workDays = [2, 4]
        s.workStartMinutes = 10 * 60
        s.workEndMinutes = 14 * 60
        // Po a st do konce října od středy 21. (7:00): st 21., po 26., st 28. = 3 dny po 4 h.
        let (seconds, days) = TargetForecast.capacityLeft(now: date(21), schedule: s)
        XCTAssertEqual(days, 3)
        XCTAssertEqual(seconds, 12 * 3600)
    }

    func testRequiredTodaySplitsRemainingAcrossWorkdays() {
        // Středa 21. 10. v 7:00, chybí 40 h, zbývá 8 pracovních dní → 5 h denně.
        let f = forecast(amount: 30_000, now: date(21))!
        XCTAssertEqual(f.requiredTodaySeconds(), 5 * 3600)
        XCTAssertEqual(f.todayCapacitySeconds, 8 * 3600)
    }

    func testRequiredTodayDecreasesByWorkedTime() {
        // Po 2 h práce dnes je zbývající částka o 2 h nižší (30 000 → 32 000 Kč při 1000 Kč/h),
        // plán na dnes zůstává 5 h, takže zbývají 3 h.
        let f = forecast(amount: 32_000, now: date(21))!
        XCTAssertEqual(f.requiredTodaySeconds(workedToday: 2 * 3600), 3 * 3600)
    }

    func testRequiredTodayIsZeroOutsideWorkingTimeOrWhenReached() {
        XCTAssertEqual(forecast(amount: 30_000, now: date(21, 18))!.requiredTodaySeconds(), 0, "po pracovní době")
        XCTAssertEqual(forecast(amount: 30_000, now: date(24, 10))!.requiredTodaySeconds(), 0, "sobota")
        XCTAssertEqual(forecast(amount: 80_000, now: date(21))!.requiredTodaySeconds(), 0, "cíl splněn")
    }
}
