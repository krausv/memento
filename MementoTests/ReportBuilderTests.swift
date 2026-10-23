import XCTest
@testable import Memento

final class ReportBuilderTests: XCTestCase {
    private let calendar = Calendar.prague
    private let builder = ReportBuilder()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func entry(_ start: Date, _ end: Date, note: String? = nil) -> ReportEntry {
        ReportEntry(note: note, start: start, end: end)
    }

    private func report(
        _ entries: [ReportEntry],
        month: ReportMonth = ReportMonth(year: 2026, month: 10),
        rate: Decimal = 1500,
        rounding: RoundingOption = .none
    ) -> Report {
        builder.build(projectName: "P", client: nil, currency: "CZK", hourlyRate: rate,
                      month: month, rounding: rounding, entries: entries)
    }

    func testHoursAndAmount() {
        let r = report([
            entry(date(2026, 10, 5, 8), date(2026, 10, 5, 12, 30)),
            entry(date(2026, 10, 6, 9), date(2026, 10, 6, 17)),
            entry(date(2026, 10, 6, 17), date(2026, 10, 6, 18)),
        ])
        XCTAssertEqual(r.totalSeconds, 48600)
        XCTAssertEqual(r.totalHours, Decimal(string: "13.5"))
        XCTAssertEqual(r.amount, 20250)
    }

    func testAmountRoundsOnlyAtTheEnd() {
        // 3 × 20 s = 60 s; sazba 1000 Kč/h → 16,666… Kč → 16,67
        let start = date(2026, 10, 5, 8)
        let r = report((0..<3).map { i in
            entry(start.addingTimeInterval(Double(i) * 100), start.addingTimeInterval(Double(i) * 100 + 20))
        }, rate: 1000)
        XCTAssertEqual(r.totalSeconds, 60)
        XCTAssertEqual(r.amount, Decimal(string: "16.67"))
    }

    func testRoundingUp() {
        let start = date(2026, 10, 5, 8)
        let entries = [
            entry(start, start.addingTimeInterval(7 * 60)),
            entry(start.addingTimeInterval(3600), start.addingTimeInterval(3600 + 16 * 60)),
        ]
        XCTAssertEqual(report(entries, rounding: .none).totalSeconds, 23 * 60)
        XCTAssertEqual(report(entries, rounding: .five).totalSeconds, (10 + 20) * 60)
        XCTAssertEqual(report(entries, rounding: .fifteen).totalSeconds, (15 + 30) * 60)
        XCTAssertEqual(report(entries, rounding: .thirty).totalSeconds, 60 * 60)
        XCTAssertEqual(RoundingOption.fifteen.apply(toSeconds: 15 * 60), 15 * 60)
        XCTAssertEqual(RoundingOption.fifteen.apply(toSeconds: 0), 0)
    }

    func testEntryAcrossMidnightBelongsToStartDay() {
        let e = entry(date(2026, 10, 5, 22), date(2026, 10, 6, 2))
        let r = report([e])
        XCTAssertEqual(r.totalSeconds, 4 * 3600)
        XCTAssertEqual(calendar.component(.day, from: r.rows[0].start), 5)
    }

    func testEntryAcrossMonthBoundaryBelongsToStartMonth() {
        let e = entry(date(2026, 10, 31, 22), date(2026, 11, 1, 3))
        XCTAssertEqual(report([e], month: ReportMonth(year: 2026, month: 10)).totalSeconds, 5 * 3600)
        XCTAssertEqual(report([e], month: ReportMonth(year: 2026, month: 11)).totalSeconds, 0)
    }

    func testDaylightSavingEnd() {
        // 25. 10. 2026: ve 3:00 CEST se hodiny vrací na 2:00 CET → noc má o hodinu víc.
        let r = report([entry(date(2026, 10, 25, 1, 30), date(2026, 10, 25, 4, 0))])
        XCTAssertEqual(r.totalSeconds, Int(3.5 * 3600))
    }

    func testDaylightSavingStart() {
        // 29. 3. 2026: ve 2:00 CET se hodiny posunou na 3:00 CEST → noc má o hodinu míň.
        let r = report([entry(date(2026, 3, 29, 1, 30), date(2026, 3, 29, 4, 0))],
                       month: ReportMonth(year: 2026, month: 3))
        XCTAssertEqual(r.totalSeconds, Int(1.5 * 3600))
    }

    func testMonthBoundaryUsesPragueTimeZone() {
        // 31. 10. 2026 23:30 pražského času je ještě říjen, i když v UTC je to také 22:30 – ověř opačný směr:
        // 1. 11. 2026 00:30 pražského času je v UTC ještě 31. 10., ale patří do listopadu.
        let e = entry(date(2026, 11, 1, 0, 30), date(2026, 11, 1, 1, 30))
        XCTAssertEqual(report([e], month: ReportMonth(year: 2026, month: 10)).totalSeconds, 0)
        XCTAssertEqual(report([e], month: ReportMonth(year: 2026, month: 11)).totalSeconds, 3600)
    }

    func testFormatting() {
        XCTAssertEqual(CzFormat.hours(seconds: Int(12.5 * 3600)), "12,50 h")
        let money = CzFormat.money(Decimal(18750), currency: "CZK").replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(money, "18 750,00 Kč")
        XCTAssertEqual(CzFormat.month(ReportMonth(year: 2026, month: 10)), "říjen 2026")
    }
}
