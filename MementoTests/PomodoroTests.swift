import SwiftData
import XCTest
@testable import Memento

final class PomodoroPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings = PomodoroSettings()

    override func setUp() {
        settings = PomodoroSettings()
        settings.notifications = true
    }

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testWorkPhaseIsDueAfterConfiguredLength() {
        let state = PomodoroState(phaseStart: t0)
        XCTAssertFalse(PomodoroPolicy.isDue(state, now: at(24.9), settings: settings))
        XCTAssertTrue(PomodoroPolicy.isDue(state, now: at(25), settings: settings))
    }

    func testAwaitingStateIsNotDueAgain() {
        var state = PomodoroState(phaseStart: t0)
        state.awaiting = true
        XCTAssertFalse(PomodoroPolicy.isDue(state, now: at(60), settings: settings))
    }

    func testShortBreaksThenLongBreakAfterConfiguredCycles() {
        settings.cyclesBeforeLongBreak = 3
        var state = PomodoroState(phaseStart: t0)
        for done in 1...2 {
            state = PomodoroPolicy.advance(state, settings: settings, at: t0)
            XCTAssertEqual(state.phase, .shortBreak)
            XCTAssertEqual(state.completed, done)
            state = PomodoroPolicy.advance(state, settings: settings, at: t0)
            XCTAssertEqual(state.phase, .work)
            XCTAssertEqual(state.completed, done)
        }
        state = PomodoroPolicy.advance(state, settings: settings, at: t0)
        XCTAssertEqual(state.phase, .longBreak)
        XCTAssertEqual(state.completed, 3)
    }

    func testLongBreakResetsSeries() {
        var state = PomodoroState(phase: .longBreak, phaseStart: t0, completed: 4)
        state = PomodoroPolicy.advance(state, settings: settings, at: at(15))
        XCTAssertEqual(state.phase, .work)
        XCTAssertEqual(state.completed, 0)
        XCTAssertEqual(state.phaseStart, at(15))
    }

    func testBreakLengthsFollowSettings() {
        settings.shortBreakMinutes = 7
        settings.longBreakMinutes = 20
        XCTAssertEqual(PomodoroPolicy.duration(of: .shortBreak, settings: settings), 7 * 60)
        XCTAssertEqual(PomodoroPolicy.duration(of: .longBreak, settings: settings), 20 * 60)
        settings.workMinutes = 0
        XCTAssertEqual(PomodoroPolicy.duration(of: .work, settings: settings), 60, "minimum je 1 minuta")
    }

    func testSnoozeEndsFiveMinutesFromNow() {
        var state = PomodoroState(phaseStart: t0)
        state.awaiting = true
        let snoozed = PomodoroPolicy.snoozed(state, settings: settings, now: at(27))
        XCTAssertFalse(snoozed.awaiting)
        XCTAssertEqual(PomodoroPolicy.endDate(of: snoozed, settings: settings), at(32))
        XCTAssertTrue(PomodoroPolicy.isDue(snoozed, now: at(32), settings: settings))
    }

    func testSkipBreakStartsNextWorkAndCountsFinishedPomodoro() {
        var state = PomodoroState(phaseStart: t0, completed: 1)
        state.awaiting = true
        let next = PomodoroPolicy.skipBreak(state, settings: settings, at: at(26))
        XCTAssertEqual(next.phase, .work)
        XCTAssertEqual(next.completed, 2)
        XCTAssertEqual(next.phaseStart, at(26))
    }

    func testSkippingLongBreakResetsSeries() {
        var state = PomodoroState(phaseStart: t0, completed: 3)
        state.awaiting = true
        let next = PomodoroPolicy.skipBreak(state, settings: settings, at: at(26))
        XCTAssertEqual(next.phase, .work)
        XCTAssertEqual(next.completed, 0)
    }

    func testSkipRunningBreak() {
        let state = PomodoroState(phase: .shortBreak, phaseStart: t0, completed: 1)
        let next = PomodoroPolicy.skipBreak(state, settings: settings, at: at(2))
        XCTAssertEqual(next.phase, .work)
        XCTAssertEqual(next.completed, 1)
    }

    func testDecodingOldSettingsKeepsDefaults() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(decoded.notifications)
        XCTAssertFalse(decoded.visualTimer)
        XCTAssertEqual(decoded.workMinutes, 25)
        XCTAssertEqual(decoded.cyclesBeforeLongBreak, 4)
    }

    func testRemainingAndProgress() {
        let state = PomodoroState(phaseStart: t0)
        XCTAssertEqual(PomodoroPolicy.remaining(state, now: at(10), settings: settings), 15 * 60)
        XCTAssertEqual(PomodoroPolicy.progress(state, now: at(10), settings: settings), 0.4, accuracy: 0.0001)
        XCTAssertEqual(PomodoroPolicy.remaining(state, now: at(40), settings: settings), 0)
        XCTAssertEqual(PomodoroPolicy.progress(state, now: at(40), settings: settings), 1)
        XCTAssertEqual(PomodoroPolicy.progress(state, now: at(-5), settings: settings), 0)
    }

    func testAvailableActions() {
        var work = PomodoroState(phaseStart: t0)
        XCTAssertEqual(PomodoroPolicy.availableActions(work), [])
        work.awaiting = true
        XCTAssertEqual(PomodoroPolicy.availableActions(work), [.startNext, .snooze, .skipBreak])
        var pause = PomodoroState(phase: .shortBreak, phaseStart: t0)
        XCTAssertEqual(PomodoroPolicy.availableActions(pause), [.skipBreak])
        pause.awaiting = true
        XCTAssertEqual(PomodoroPolicy.availableActions(pause), [.startNext, .snooze])
    }

    func testLegacyEnabledMapsToNotifications() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: Data(#"{"enabled":true,"visualTimer":true}"#.utf8))
        XCTAssertTrue(decoded.notifications)
        XCTAssertTrue(decoded.visualTimer)
        XCTAssertTrue(decoded.isActive)
    }

    func testNoticeTexts() {
        XCTAssertEqual(PomodoroNotice.breakDue(.shortBreak, completed: 2).text(settings: settings).title, "Čas na pauzu")
        XCTAssertEqual(PomodoroNotice.breakDue(.longBreak, completed: 4).text(settings: settings).body,
                       "Pomodoro č. 4 hotovo. Dlouhá pauza 15 min.")
        XCTAssertEqual(PomodoroNotice.workDue.text(settings: settings).body, "Můžeš pokračovat – další pomodoro (25 min).")
    }
}

@MainActor
final class PomodoroSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings = PomodoroSettings()
    private var notices: [PomodoroNotice] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Project.self, TimeEntry.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        settings = PomodoroSettings()
        settings.notifications = true
        notices = []
    }

    private func makeTimer() -> (TimerController, Project) {
        let project = Project(name: "A", hourlyRate: 1000)
        container.mainContext.insert(project)
        return (TimerController(context: container.mainContext, clock: { [unowned self] in self.time }), project)
    }

    private func makeScheduler(_ timer: TimerController) -> PomodoroScheduler {
        PomodoroScheduler(timer: timer, clock: { [unowned self] in self.time }, settings: { [unowned self] in self.settings }) {
            [unowned self] notice, _, _ in self.notices.append(notice)
        }
    }

    private func advance(_ minutes: Double, _ scheduler: PomodoroScheduler) {
        time.addTimeInterval(minutes * 60)
        scheduler.check()
    }

    func testNothingHappensWithoutRunningTimerOrWhenDisabled() throws {
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        scheduler.check()
        XCTAssertNil(scheduler.state)

        settings.notifications = false
        settings.visualTimer = false
        _ = try timer.start(project)
        scheduler.check()
        XCTAssertNil(scheduler.state)
    }

    func testManualCycle() throws {
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        XCTAssertEqual(scheduler.state?.phase, .work)

        advance(24, scheduler)
        XCTAssertTrue(notices.isEmpty)
        advance(1, scheduler)
        XCTAssertEqual(notices, [.breakDue(.shortBreak, completed: 1)])

        // Bez reakce se oznámení neopakuje.
        advance(10, scheduler)
        XCTAssertEqual(notices.count, 1)

        scheduler.perform(.startNext)
        XCTAssertEqual(scheduler.state?.phase, .shortBreak)
        advance(5, scheduler)
        XCTAssertEqual(notices.last, .workDue)

        scheduler.perform(.startNext)
        XCTAssertEqual(scheduler.state?.phase, .work)
        XCTAssertEqual(scheduler.state?.completed, 1)
    }

    func testSnoozeDelaysNextNotice() throws {
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        advance(25, scheduler)
        scheduler.perform(.snooze)
        advance(4, scheduler)
        XCTAssertEqual(notices.count, 1)
        advance(1, scheduler)
        XCTAssertEqual(notices.count, 2)
        XCTAssertEqual(notices.last, .breakDue(.shortBreak, completed: 1))
    }

    func testAutoAdvanceSwitchesPhasesWithoutWaiting() throws {
        settings.autoAdvance = true
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        advance(25, scheduler)
        XCTAssertEqual(notices, [.breakStarted(.shortBreak, completed: 1)])
        XCTAssertEqual(scheduler.state?.phase, .shortBreak)
        advance(5, scheduler)
        XCTAssertEqual(notices.last, .workStarted)
        XCTAssertEqual(scheduler.state?.phase, .work)
    }

    func testVisualOnlyModeRunsCycleWithoutNotifying() throws {
        settings.notifications = false
        settings.visualTimer = true
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        advance(25, scheduler)
        XCTAssertTrue(notices.isEmpty)
        XCTAssertEqual(scheduler.state?.awaiting, true)
        scheduler.perform(.startNext)
        XCTAssertEqual(scheduler.state?.phase, .shortBreak)
    }

    func testStaleActionsAreIgnored() throws {
        let (timer, project) = makeTimer()
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        advance(10, scheduler)
        let before = scheduler.state
        scheduler.perform(.startNext)
        scheduler.perform(.snooze)
        scheduler.perform(.skipBreak)
        XCTAssertEqual(scheduler.state, before)
    }

    func testStoppingTimerEndsCycleAndSwitchingProjectKeepsIt() throws {
        let (timer, project) = makeTimer()
        let other = Project(name: "B", hourlyRate: 500)
        container.mainContext.insert(other)
        let scheduler = makeScheduler(timer)
        _ = try timer.start(project)
        scheduler.check()
        let started = scheduler.state?.phaseStart

        advance(10, scheduler)
        _ = try timer.start(other)
        scheduler.check()
        XCTAssertEqual(scheduler.state?.phaseStart, started)

        try timer.stop()
        scheduler.check()
        XCTAssertNil(scheduler.state)
    }
}
