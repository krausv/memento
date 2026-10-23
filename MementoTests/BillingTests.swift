import XCTest
@testable import Memento

final class BillingTests: XCTestCase {
    private let calendar = Calendar.prague
    private let now = Calendar.prague.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    private func date(_ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    private func entry(_ project: UUID, rate: Decimal = 1000, currency: String = "CZK", start: Date, seconds: Int) -> BillingEntry {
        BillingEntry(projectKey: project, currency: currency, hourlyRate: rate, start: start, end: start.addingTimeInterval(Double(seconds)))
    }

    func testAmountMatchesReportBuilder() {
        // 3 × 20 s při 1000 Kč/h: součet 60 s → 16,67 Kč, ne 3 × 5,56 = 16,68.
        let project = UUID()
        let entries = (0..<3).map { entry(project, start: date(10, 5).addingTimeInterval(Double($0) * 100), seconds: 20) }
        let totals = Billing.totals(entries, now: now, rounding: .none)
        XCTAssertEqual(totals, [CurrencyAmount(currency: "CZK", amount: Decimal(string: "16.67")!)])

        let report = ReportBuilder().build(
            projectName: "P", client: nil, currency: "CZK", hourlyRate: 1000,
            month: ReportMonth(year: 2026, month: 10), rounding: .none,
            entries: entries.map { ReportEntry(note: nil, start: $0.start, end: $0.end!) })
        XCTAssertEqual(totals.first?.amount, report.amount)
    }

    func testRoundingFromExportIsApplied() {
        let project = UUID()
        let totals = Billing.totals([entry(project, start: date(10, 5), seconds: 7 * 60)], now: now, rounding: .fifteen)
        XCTAssertEqual(totals.first?.amount, 250)
    }

    func testRoundsPerProjectAndMonthThenSums() {
        let a = UUID(), b = UUID()
        let totals = Billing.totals([
            entry(a, start: date(9, 30), seconds: 3600),
            entry(a, start: date(10, 1), seconds: 3600),
            entry(b, rate: 500, start: date(10, 2), seconds: 7200),
        ], now: now, rounding: .none)
        XCTAssertEqual(totals, [CurrencyAmount(currency: "CZK", amount: 3000)])
    }

    func testSeparateCurrenciesAreNotMixed() {
        let totals = Billing.totals([
            entry(UUID(), rate: 1000, currency: "CZK", start: date(10, 1), seconds: 3600),
            entry(UUID(), rate: 50, currency: "EUR", start: date(10, 1), seconds: 3600),
        ], now: now, rounding: .none)
        XCTAssertEqual(totals.map(\.currency), ["CZK", "EUR"])
        XCTAssertEqual(totals.map(\.amount), [1000, 50])
    }

    func testRunningEntryCountsUntilNow() {
        let running = BillingEntry(projectKey: UUID(), currency: "CZK", hourlyRate: 1000, start: now.addingTimeInterval(-1800), end: nil)
        XCTAssertEqual(Billing.totals([running], now: now, rounding: .none).first?.amount, 500)
    }

    func testEmptyAndText() {
        XCTAssertTrue(Billing.totals([], now: now, rounding: .none).isEmpty)
        XCTAssertEqual(Billing.text([]), "—")
        let text = Billing.text([CurrencyAmount(currency: "CZK", amount: 18750), CurrencyAmount(currency: "EUR", amount: 120)])
        XCTAssertTrue(text.replacingOccurrences(of: "\u{00A0}", with: " ").contains("18 750,00 Kč + "))
    }
}
