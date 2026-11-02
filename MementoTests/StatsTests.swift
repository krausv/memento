import XCTest
@testable import Memento

final class StatsTests: XCTestCase {
    private let calendar = Calendar.prague
    private func date(_ m: Int, _ d: Int, _ h: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: m, day: d, hour: h))!
    }

    private func entry(_ project: String, _ start: Date, hours: Double, tags: [String] = []) -> StatsEntry {
        StatsEntry(projectName: project, tags: tags, start: start, end: start.addingTimeInterval(hours * 3600))
    }

    private func build(_ period: StatsPeriod, anchor: Date, _ entries: [StatsEntry], now: Date? = nil) -> Stats {
        StatsBuilder.build(period: period, anchor: anchor, entries: entries, now: now ?? anchor)
    }

    func testWeekStartsOnMondayAndHasSevenBuckets() {
        // 21. 10. 2026 je středa → týden 19.–25. 10.
        let stats = build(.week, anchor: date(10, 21), [])
        XCTAssertEqual(stats.buckets.count, 7)
        XCTAssertEqual(stats.buckets.first, date(10, 19))
        XCTAssertEqual(calendar.component(.weekday, from: stats.buckets[0]), 2)
        XCTAssertEqual(stats.totalSeconds, 0)
    }

    func testMonthAndYearBuckets() {
        XCTAssertEqual(build(.month, anchor: date(10, 5), []).buckets.count, 31)
        XCTAssertEqual(build(.month, anchor: date(2, 5), []).buckets.count, 28)
        XCTAssertEqual(build(.year, anchor: date(10, 5), []).buckets.count, 12)
    }

    func testTotalsByProjectAndOrdering() {
        let stats = build(.week, anchor: date(10, 21), [
            entry("A", date(10, 19, 8), hours: 2),
            entry("B", date(10, 20, 8), hours: 5),
            entry("A", date(10, 21, 8), hours: 1.5),
            entry("A", date(10, 26, 8), hours: 9), // příští týden
        ])
        XCTAssertEqual(stats.totalSeconds, Int(8.5 * 3600))
        XCTAssertEqual(stats.entryCount, 3)
        XCTAssertEqual(stats.byProject.map(\.name), ["B", "A"])
        XCTAssertEqual(stats.byProject.map(\.seconds), [5 * 3600, Int(3.5 * 3600)])
        XCTAssertEqual(stats.workedDays, 3)
        XCTAssertEqual(stats.averagePerWorkedDay, Int(8.5 * 3600) / 3)
    }

    func testPointsGroupByBucketAndProject() {
        let stats = build(.week, anchor: date(10, 21), [
            entry("A", date(10, 19, 8), hours: 1),
            entry("A", date(10, 19, 12), hours: 2),
            entry("B", date(10, 19, 15), hours: 1),
        ])
        XCTAssertEqual(stats.points.count, 2)
        XCTAssertEqual(stats.points.first { $0.project == "A" }?.seconds, 3 * 3600)
    }

    func testYearGroupsByMonth() {
        let stats = build(.year, anchor: date(6, 1), [
            entry("A", date(1, 5, 8), hours: 1),
            entry("A", date(1, 25, 8), hours: 2),
            entry("A", date(3, 1, 8), hours: 4),
        ])
        XCTAssertEqual(stats.points.map(\.seconds), [3 * 3600, 4 * 3600])
        XCTAssertEqual(stats.points.map(\.bucket), [date(1, 1), date(3, 1)])
    }

    func testEntryBelongsToStartDayAndMonth() {
        // 31. 10. 22:00 → 1. 11. 03:00 patří celé do října.
        let e = entry("A", date(10, 31, 22), hours: 5)
        XCTAssertEqual(build(.month, anchor: date(10, 1), [e]).totalSeconds, 5 * 3600)
        XCTAssertEqual(build(.month, anchor: date(11, 1), [e]).totalSeconds, 0)
    }

    func testRunningEntryCountsUntilNow() {
        let running = StatsEntry(projectName: "A", tags: [], start: date(10, 21, 8), end: nil)
        let stats = build(.week, anchor: date(10, 21), [running], now: date(10, 21, 11))
        XCTAssertEqual(stats.totalSeconds, 3 * 3600)
    }

    func testTagsCountPerTagAndUntagged() {
        let stats = build(.week, anchor: date(10, 21), [
            entry("A", date(10, 19, 8), hours: 2, tags: ["Schůzka", "Klient"]),
            entry("A", date(10, 20, 8), hours: 1),
        ])
        XCTAssertEqual(stats.byTag.first { $0.name == "Schůzka" }?.seconds, 2 * 3600)
        XCTAssertEqual(stats.byTag.first { $0.name == "Klient" }?.seconds, 2 * 3600)
        XCTAssertEqual(stats.byTag.first { $0.name == Stats.untaggedName }?.seconds, 3600)
        XCTAssertEqual(stats.totalSeconds, 3 * 3600)
    }

    func testShift() {
        let next = StatsBuilder.shift(date(10, 21), period: .week, by: 1)
        XCTAssertEqual(StatsBuilder.interval(for: .week, containing: next).start, date(10, 26))
        XCTAssertEqual(StatsBuilder.interval(for: .month, containing: StatsBuilder.shift(date(1, 31), period: .month, by: 1)).start, date(2, 1))
        XCTAssertEqual(StatsBuilder.interval(for: .year, containing: StatsBuilder.shift(date(10, 1), period: .year, by: -1)).start, date(1, 1, year: 2025))
    }

    func testWorkHoursSplit() {
        // Po 5. 10. 2026: 8:00–10:00 → 1 h mimo (8–9) a 1 h v pracovní době (9–10).
        let r = WorkHours.split(start: date(10, 5, 8), end: date(10, 5, 10), schedule: ReminderSettings())
        XCTAssertEqual(r, WorkHours.Split(inside: 3600, outside: 3600))
        // Sobota 10. 10. je celá mimo.
        let weekend = WorkHours.split(start: date(10, 10, 10), end: date(10, 10, 12), schedule: ReminderSettings())
        XCTAssertEqual(weekend, WorkHours.Split(inside: 0, outside: 7200))
        // Přes půlnoc: 16:00–18:00 v pracovní/mimo, pátek → sobota.
        let night = WorkHours.split(start: date(10, 9, 16), end: date(10, 10, 1), schedule: ReminderSettings())
        XCTAssertEqual(night, WorkHours.Split(inside: 3600, outside: 8 * 3600))
    }

    func testStatsSplitsWorkHours() {
        let stats = StatsBuilder.build(
            period: .week, anchor: date(10, 5, 12),
            entries: [entry("A", date(10, 5, 8), hours: 2)], now: date(10, 5, 12), schedule: ReminderSettings()
        )
        XCTAssertEqual(stats.outsideWorkSeconds, 3600)
        XCTAssertEqual(stats.workPoints.map(\.seconds).reduce(0, +), stats.totalSeconds)
        XCTAssertEqual(stats.workPoints.count, 2)
    }
}
