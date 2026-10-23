import SwiftData
import XCTest
@testable import Memento

final class BudgetStatusTests: XCTestCase {
    private let calendar = Calendar.prague
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func status(
        hours: Decimal = 10, period: BudgetPeriod = .total, entries: [BudgetStatus.Entry],
        now: Date, rounding: RoundingOption = .none
    ) -> BudgetStatus {
        BudgetStatus.compute(budgetHours: hours, period: period, entries: entries, now: now, rounding: rounding)
    }

    func testLevelsAtThresholds() {
        let now = date(2026, 10, 20, 12)
        func level(_ usedHours: Double) -> Int {
            status(entries: [.init(start: now.addingTimeInterval(-usedHours * 3600), end: now)], now: now).level
        }
        XCTAssertEqual(level(7.9), 0)
        XCTAssertEqual(level(8), BudgetStatus.warningLevel)
        XCTAssertEqual(level(9.99), BudgetStatus.warningLevel)
        XCTAssertEqual(level(10), BudgetStatus.exceededLevel)
        XCTAssertEqual(level(12), BudgetStatus.exceededLevel)
    }

    func testRunningEntryCountsUntilNow() {
        let now = date(2026, 10, 20, 12)
        let s = status(entries: [.init(start: now.addingTimeInterval(-9 * 3600), end: nil)], now: now)
        XCTAssertEqual(s.usedSeconds, 9 * 3600)
        XCTAssertEqual(s.level, BudgetStatus.warningLevel)
    }

    func testMonthlyPeriodCountsOnlyCurrentMonth() {
        let now = date(2026, 10, 20, 12)
        let entries: [BudgetStatus.Entry] = [
            .init(start: date(2026, 9, 30, 8), end: date(2026, 9, 30, 18)),
            .init(start: date(2026, 10, 2, 8), end: date(2026, 10, 2, 10)),
        ]
        XCTAssertEqual(status(period: .monthly, entries: entries, now: now).usedSeconds, 2 * 3600)
        XCTAssertEqual(status(period: .total, entries: entries, now: now).usedSeconds, 12 * 3600)
    }

    func testRoundingIsApplied() {
        let now = date(2026, 10, 20, 12)
        let entry = BudgetStatus.Entry(start: now.addingTimeInterval(-7 * 60), end: now)
        XCTAssertEqual(status(entries: [entry], now: now, rounding: .fifteen).usedSeconds, 15 * 60)
    }

    func testFractionalHoursBudget() {
        let now = date(2026, 10, 20, 12)
        let s = status(hours: Decimal(string: "0.5")!, entries: [.init(start: now.addingTimeInterval(-1800), end: now)], now: now)
        XCTAssertEqual(s.budgetSeconds, 1800)
        XCTAssertEqual(s.level, BudgetStatus.exceededLevel)
    }

    func testPeriodKey() {
        let now = date(2026, 10, 20)
        XCTAssertEqual(BudgetStatus.periodKey(.total, now: now), "total")
        XCTAssertEqual(BudgetStatus.periodKey(.monthly, now: now), "2026-10")
    }
}

final class TargetStatusTests: XCTestCase {
    private let calendar = Calendar.prague
    private let now = Calendar.prague.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!

    private func status(hours: Double, rate: Decimal = 1000, target: Decimal = 70_000, prior: [BudgetStatus.Entry] = []) -> TargetStatus {
        TargetStatus.compute(
            target: target, hourlyRate: rate,
            entries: prior + [.init(start: now.addingTimeInterval(-hours * 3600), end: now)],
            now: now, rounding: .none
        )
    }

    func testToleranceBand() {
        XCTAssertEqual(status(hours: 68.5).position, .under)   // 68 500 < 68 600
        XCTAssertEqual(status(hours: 68.6).position, .on)      // hranice pásma
        XCTAssertEqual(status(hours: 70).position, .on)
        XCTAssertEqual(status(hours: 71.4).position, .on)      // 71 400 = horní hranice
        XCTAssertEqual(status(hours: 71.5).position, .over)
    }

    func testDifferenceAndAmountUseExportRounding() {
        let s = status(hours: 60)
        XCTAssertEqual(s.amount, 60_000)
        XCTAssertEqual(s.difference, -10_000)
        XCTAssertEqual(s.fraction, 60.0 / 70.0, accuracy: 0.0001)
    }

    func testExplicitMonthIsEvaluatedInsteadOfCurrent() {
        let september = BudgetStatus.Entry(
            start: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 8))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 18))!
        )
        let result = TargetStatus.compute(
            target: 10_000, hourlyRate: 1000, entries: [september, .init(start: now.addingTimeInterval(-3600), end: now)],
            now: now, rounding: .none, month: ReportMonth(year: 2026, month: 9)
        )
        XCTAssertEqual(result.amount, 10_000)
        XCTAssertEqual(result.position, .on)
    }

    func testOnlyCurrentMonthCounts() {
        let september = BudgetStatus.Entry(
            start: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 8))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 18))!
        )
        XCTAssertEqual(status(hours: 10, prior: [september]).amount, 10_000)
    }
}

@MainActor
final class BudgetMonitorTests: XCTestCase {
    private var container: ModelContainer!
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    private var sent: [(String, String)] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Project.self, TimeEntry.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sent = []
    }

    private func makeMonitor() -> BudgetMonitor {
        BudgetMonitor(context: container.mainContext, clock: { [unowned self] in self.time },
                      rounding: { .none }, notify: { [unowned self] in self.sent.append(($0, $1)) })
    }

    private func addEntry(_ project: Project, hours: Double) {
        let entry = TimeEntry(project: project, start: time.addingTimeInterval(-hours * 3600), end: time)
        container.mainContext.insert(entry)
    }

    func testNotifiesOncePerLevel() {
        let project = Project(name: "A", hourlyRate: 100)
        project.budgetHours = 10
        container.mainContext.insert(project)
        let monitor = makeMonitor()

        addEntry(project, hours: 5)
        monitor.check()
        XCTAssertTrue(sent.isEmpty)

        addEntry(project, hours: 3.5)
        monitor.check()
        monitor.check()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].0.hasPrefix("Blíží se limit"))

        addEntry(project, hours: 2)
        monitor.check()
        monitor.check()
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[1].0.hasPrefix("Překročen limit"))
    }

    func testMonthlyBudgetAlertsAgainInNewMonth() {
        let project = Project(name: "A", hourlyRate: 100)
        project.budgetHours = 1
        project.budgetPeriod = BudgetPeriod.monthly.rawValue
        container.mainContext.insert(project)
        let monitor = makeMonitor()

        addEntry(project, hours: 2)
        monitor.check()
        XCTAssertEqual(sent.count, 1)

        time.addTimeInterval(40 * 24 * 3600)
        monitor.check() // nový měsíc, žádné záznamy → úroveň 0, bez upozornění
        XCTAssertEqual(sent.count, 1)
        addEntry(project, hours: 2)
        monitor.check()
        XCTAssertEqual(sent.count, 2)
    }

    func testRaisingBudgetRearmsAlerts() {
        let project = Project(name: "A", hourlyRate: 100)
        project.budgetHours = 1
        container.mainContext.insert(project)
        let monitor = makeMonitor()
        addEntry(project, hours: 2)
        monitor.check()
        XCTAssertEqual(sent.count, 1)

        project.budgetHours = 20
        project.syncBudgetAlertState(now: time, rounding: .none)
        monitor.check()
        XCTAssertEqual(sent.count, 1)
        addEntry(project, hours: 17)
        monitor.check()
        XCTAssertEqual(sent.count, 2)
    }

    func testIgnoresArchivedAndUnlimitedProjects() {
        let archived = Project(name: "A", hourlyRate: 100)
        archived.budgetHours = 1
        archived.isArchived = true
        let unlimited = Project(name: "B", hourlyRate: 100)
        container.mainContext.insert(archived)
        container.mainContext.insert(unlimited)
        addEntry(archived, hours: 5)
        addEntry(unlimited, hours: 5)
        makeMonitor().check()
        XCTAssertTrue(sent.isEmpty)
    }

    func testTargetNotifiesWhenReachedAndWhenExceeded() {
        let project = Project(name: "ABC", hourlyRate: 1000)
        project.targetAmount = 10_000
        container.mainContext.insert(project)
        // Čas v testu je 15. 1. 2027; všechny záznamy končí „teď“, takže jsou v aktuálním měsíci.
        let monitor = makeMonitor()

        addEntry(project, hours: 5)
        monitor.check()
        XCTAssertTrue(sent.isEmpty)

        addEntry(project, hours: 5)
        monitor.check()
        monitor.check()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].0.hasPrefix("Měsíční cíl dosažen"))

        addEntry(project, hours: 3)
        monitor.check()
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[1].0.hasPrefix("Měsíční cíl překročen"))
    }

    func testTargetIsRearmedInNewMonth() {
        let project = Project(name: "ABC", hourlyRate: 1000)
        project.targetAmount = 1000
        container.mainContext.insert(project)
        let monitor = makeMonitor()
        addEntry(project, hours: 1)
        monitor.check()
        XCTAssertEqual(sent.count, 1)

        time.addTimeInterval(40 * 24 * 3600)
        monitor.check()
        addEntry(project, hours: 1)
        monitor.check()
        XCTAssertEqual(sent.count, 2)
    }
}
