import SwiftData
import XCTest
@testable import Memento

final class ReminderPolicyTests: XCTestCase {
    private let calendar = Calendar.prague
    // 21. 10. 2026 je středa, 24. 10. sobota.
    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    private var settings: ReminderSettings {
        var s = ReminderSettings()
        s.remindNotRunning = true
        s.remindLongRunning = true
        return s
    }

    private func evaluate(
        now: Date, running: Date? = nil, lastEnd: Date? = nil,
        settings: ReminderSettings? = nil, state: ReminderState = ReminderState()
    ) -> Reminder? {
        ReminderPolicy.evaluate(now: now, runningSince: running, lastEntryEnd: lastEnd,
                                settings: settings ?? self.settings, state: state)
    }

    func testRemindsOnlyInWorkHoursOnWorkDays() {
        XCTAssertEqual(evaluate(now: date(21, 10)), .notRunning)
        XCTAssertEqual(evaluate(now: date(21, 9)), .notRunning)
        XCTAssertNil(evaluate(now: date(21, 8, 59)))
        XCTAssertNil(evaluate(now: date(21, 17)), "konec pracovní doby je vyloučen")
        XCTAssertNil(evaluate(now: date(24, 10)), "sobota")
    }

    func testDisabledSettingsNeverRemind() {
        var s = settings
        s.remindNotRunning = false
        XCTAssertNil(evaluate(now: date(21, 10), settings: s))
    }

    func testAtMostOncePerHour() {
        let state = ReminderState(lastNotRunning: date(21, 10))
        XCTAssertNil(evaluate(now: date(21, 10, 59), state: state))
        XCTAssertEqual(evaluate(now: date(21, 11), state: state), .notRunning)
    }

    func testGracePeriodAfterStop() {
        XCTAssertNil(evaluate(now: date(21, 10, 10), lastEnd: date(21, 10)))
        XCTAssertEqual(evaluate(now: date(21, 10, 15), lastEnd: date(21, 10)), .notRunning)
    }

    func testRunningTimerNeverGetsNotRunningReminder() {
        XCTAssertNil(evaluate(now: date(21, 10), running: date(21, 9)))
    }

    func testLongRunningFiresOncePerEntry() {
        let start = date(21, 8)
        XCTAssertNil(evaluate(now: date(21, 15, 59), running: start))
        XCTAssertEqual(evaluate(now: date(21, 16), running: start), .longRunning(hours: 8))

        let notified = ReminderState(longRunningNotifiedFor: start)
        XCTAssertNil(evaluate(now: date(21, 18), running: start, state: notified))
        XCTAssertEqual(evaluate(now: date(21, 18), running: date(21, 9), state: notified), .longRunning(hours: 8))
    }

    func testLongRunningIgnoresWorkHours() {
        XCTAssertEqual(evaluate(now: date(24, 23), running: date(24, 10)), .longRunning(hours: 8))
    }
}

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var time = Calendar.prague.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!
    private var sent: [Reminder] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Project.self, TimeEntry.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sent = []
    }

    private func make() -> (ReminderScheduler, TimerController) {
        let timer = TimerController(context: container.mainContext, clock: { [unowned self] in self.time })
        var settings = ReminderSettings()
        settings.remindNotRunning = true
        let scheduler = ReminderScheduler(timer: timer, clock: { [unowned self] in self.time },
                                          settings: { settings }, notify: { [unowned self] r, _, _ in self.sent.append(r) })
        return (scheduler, timer)
    }

    func testNoReminderWithoutProjects() {
        let (scheduler, _) = make()
        scheduler.check()
        XCTAssertTrue(sent.isEmpty)
    }

    func testRemindsOnceThenWaitsAnHour() {
        container.mainContext.insert(Project(name: "A", hourlyRate: 100))
        let (scheduler, _) = make()
        scheduler.check()
        scheduler.check()
        XCTAssertEqual(sent, [.notRunning])

        time.addTimeInterval(3600)
        scheduler.check()
        XCTAssertEqual(sent.count, 2)
    }

    func testStartDefaultResumesOrStartsFirstProject() throws {
        let project = Project(name: "A", hourlyRate: 100)
        container.mainContext.insert(project)
        let (_, timer) = make()
        let entry = try XCTUnwrap(try timer.startDefault())
        XCTAssertTrue(entry.project === project)
        XCTAssertTrue(timer.runningEntry === entry)
    }
}
