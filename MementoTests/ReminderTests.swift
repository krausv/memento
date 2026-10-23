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
        now: Date, running: Date? = nil, hasNote: Bool = true, lastEnd: Date? = nil,
        settings: ReminderSettings? = nil, state: ReminderState = ReminderState()
    ) -> Reminder? {
        ReminderPolicy.evaluate(now: now, runningSince: running, runningHasNote: hasNote, lastEntryEnd: lastEnd,
                                settings: settings ?? self.settings, state: state)
    }

    private var noteSettings: ReminderSettings {
        var s = ReminderSettings()
        s.remindMissingNote = true
        s.missingNoteMinutes = 15
        return s
    }

    func testMissingNoteFiresAfterThresholdOncePerEntry() {
        let start = date(21, 10)
        XCTAssertNil(evaluate(now: date(21, 10, 14), running: start, hasNote: false, settings: noteSettings))
        XCTAssertEqual(evaluate(now: date(21, 10, 15), running: start, hasNote: false, settings: noteSettings),
                       .missingNote(minutes: 15))

        let notified = ReminderState(missingNoteNotifiedFor: start)
        XCTAssertNil(evaluate(now: date(21, 11), running: start, hasNote: false, settings: noteSettings, state: notified))
        XCTAssertEqual(evaluate(now: date(21, 11), running: date(21, 10, 30), hasNote: false, settings: noteSettings, state: notified),
                       .missingNote(minutes: 15))
    }

    func testMissingNoteSkippedWhenNoteExistsOrDisabledOrNotRunning() {
        let start = date(21, 10)
        XCTAssertNil(evaluate(now: date(21, 12), running: start, hasNote: true, settings: noteSettings))
        XCTAssertNil(evaluate(now: date(21, 12), running: start, hasNote: false, settings: ReminderSettings()))
        var s = noteSettings
        s.remindNotRunning = false
        XCTAssertNil(evaluate(now: date(21, 12), running: nil, settings: s))
    }

    func testMissingNoteWorksOutsideWorkHours() {
        XCTAssertEqual(evaluate(now: date(24, 22), running: date(24, 21), hasNote: false, settings: noteSettings),
                       .missingNote(minutes: 15))
    }

    func testLongRunningTakesPriorityOverMissingNote() {
        var s = noteSettings
        s.remindLongRunning = true
        s.longRunningHours = 1
        XCTAssertEqual(evaluate(now: date(21, 12), running: date(21, 10), hasNote: false, settings: s), .longRunning(hours: 1))
    }

    func testSettingsWithoutNewFieldsStillDecode() throws {
        let old = #"{"remindNotRunning":true,"workDays":[2,3],"workStartMinutes":480,"workEndMinutes":960,"remindLongRunning":true,"longRunningHours":6}"#
        let decoded = try JSONDecoder().decode(ReminderSettings.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.remindNotRunning)
        XCTAssertEqual(decoded.workDays, [2, 3])
        XCTAssertEqual(decoded.longRunningHours, 6)
        XCTAssertFalse(decoded.remindMissingNote)
        XCTAssertEqual(decoded.missingNoteMinutes, 15)
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

    func testSchedulerSendsMissingNoteOnlyWhenNoteIsEmpty() throws {
        let project = Project(name: "A", hourlyRate: 100)
        container.mainContext.insert(project)
        let timer = TimerController(context: container.mainContext, clock: { [unowned self] in self.time })
        var settings = ReminderSettings()
        settings.remindMissingNote = true
        settings.missingNoteMinutes = 10
        let scheduler = ReminderScheduler(timer: timer, clock: { [unowned self] in self.time },
                                          settings: { settings }, notify: { [unowned self] r, _, _ in self.sent.append(r) })
        let entry = try timer.start(project)

        time.addTimeInterval(11 * 60)
        scheduler.check()
        scheduler.check()
        XCTAssertEqual(sent, [.missingNote(minutes: 10)])

        try timer.stop()
        entry.note = "• hotovo"
        let second = try timer.start(project, note: "• s poznámkou")
        time.addTimeInterval(11 * 60)
        scheduler.check()
        XCTAssertEqual(sent.count, 1)
        _ = second
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
