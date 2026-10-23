import AppKit
import Foundation

struct ReminderSettings: Codable, Equatable {
    var remindNotRunning = false
    /// Dny podle `Calendar.weekday` (1 = neděle … 7 = sobota); výchozí pondělí–pátek.
    var workDays: Set<Int> = [2, 3, 4, 5, 6]
    var workStartMinutes = 9 * 60
    var workEndMinutes = 17 * 60
    var remindLongRunning = false
    var longRunningHours = 8
}

enum Reminder: Equatable {
    case notRunning
    case longRunning(hours: Int)
}

struct ReminderState: Equatable {
    var lastNotRunning: Date?
    /// Začátek záznamu, pro který už upozornění na dlouhý běh odešlo (jednou za záznam).
    var longRunningNotifiedFor: Date?
}

enum ReminderPolicy {
    /// Připomínka „neběží časovač“ se opakuje nejčastěji jednou za hodinu.
    static let minInterval: TimeInterval = 3600
    /// Krátce po zastavení (oběd, hovor) se nepřipomíná.
    static let gracePeriod: TimeInterval = 15 * 60

    static func isWorkTime(_ now: Date, settings: ReminderSettings, calendar: Calendar = .prague) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = parts.weekday, settings.workDays.contains(weekday) else { return false }
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes >= settings.workStartMinutes && minutes < settings.workEndMinutes
    }

    static func evaluate(
        now: Date,
        runningSince: Date?,
        lastEntryEnd: Date?,
        settings: ReminderSettings,
        state: ReminderState,
        calendar: Calendar = .prague
    ) -> Reminder? {
        if let start = runningSince {
            guard settings.remindLongRunning, settings.longRunningHours > 0,
                  state.longRunningNotifiedFor != start,
                  now.timeIntervalSince(start) >= TimeInterval(settings.longRunningHours) * 3600
            else { return nil }
            return .longRunning(hours: settings.longRunningHours)
        }

        guard settings.remindNotRunning, isWorkTime(now, settings: settings, calendar: calendar) else { return nil }
        if let last = state.lastNotRunning, now.timeIntervalSince(last) < minInterval { return nil }
        if let end = lastEntryEnd, now.timeIntervalSince(end) < gracePeriod { return nil }
        return .notRunning
    }
}

/// Jednou za minutu a po probuzení Macu vyhodnotí `ReminderPolicy` a případně pošle upozornění.
@MainActor
final class ReminderScheduler {
    private let timer: TimerController
    private let clock: () -> Date
    private let settings: () -> ReminderSettings
    private let notify: (Reminder, String, String) -> Void
    private var state = ReminderState()
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        timer: TimerController,
        clock: @escaping () -> Date = Date.init,
        settings: @escaping () -> ReminderSettings = { AppSettings.reminders },
        notify: @escaping (Reminder, String, String) -> Void
    ) {
        self.timer = timer
        self.clock = clock
        self.settings = settings
        self.notify = notify
    }

    func start(interval: TimeInterval = 60) {
        guard ticker == nil else { return }
        let ticker = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        let now = clock()
        let running = timer.runningEntry
        let lastEnd = running == nil ? timer.lastResumableEntry()?.end : nil
        let reminder = ReminderPolicy.evaluate(
            now: now, runningSince: running?.start, lastEntryEnd: lastEnd,
            settings: settings(), state: state
        )
        switch reminder {
        case nil:
            break
        case .notRunning:
            // Bez projektu by připomínka neměla co nabídnout.
            guard !timer.selectableProjects().isEmpty else { return }
            state.lastNotRunning = now
            notify(.notRunning, "Neběží časovač", "V pracovní době nesleduješ čas. Spustit časovač?")
        case .longRunning(let hours):
            state.longRunningNotifiedFor = running?.start
            let name = running?.project?.name ?? "Projekt"
            notify(.longRunning(hours: hours), "Časovač běží už \(hours) h", "\(name) – nezapomněl jsi ho zastavit?")
        }
    }
}
