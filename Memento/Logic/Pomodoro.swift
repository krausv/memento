import Foundation
import Observation

struct PomodoroSettings: Codable, Equatable {
    /// Režim 1: oznámení na hranici fází.
    var notifications = false
    /// Režim 2: plovoucí okno s vizuálním časovačem.
    var visualTimer = false
    var workMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    /// Po kolika dokončených pomodorech přijde dlouhá pauza.
    var cyclesBeforeLongBreak = 4
    /// Další fáze naváže sama; jinak se čeká na reakci v oznámení.
    var autoAdvance = false

    init() {}

    /// Cyklus běží, pokud je zapnutý aspoň jeden režim.
    var isActive: Bool { notifications || visualTimer }

    private enum LegacyKeys: String, CodingKey { case enabled }

    /// Vlastní dekódování, aby se při přidání nového pole nezahodilo už uložené nastavení.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroSettings()
        // Dřívější verze měla jediný přepínač `enabled` (tehdy existovala jen oznámení).
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .enabled)
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? legacy ?? d.notifications
        visualTimer = try c.decodeIfPresent(Bool.self, forKey: .visualTimer) ?? d.visualTimer
        workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? d.workMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        cyclesBeforeLongBreak = try c.decodeIfPresent(Int.self, forKey: .cyclesBeforeLongBreak) ?? d.cyclesBeforeLongBreak
        autoAdvance = try c.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? d.autoAdvance
    }
}

enum PomodoroPhase: Equatable {
    case work, shortBreak, longBreak

    var isBreak: Bool { self != .work }
}

struct PomodoroState: Equatable {
    var phase: PomodoroPhase = .work
    var phaseStart: Date
    /// Prodloužení fáze po „Ještě 5 minut“.
    var extra: TimeInterval = 0
    /// Dokončených pomodor v aktuální sérii (po dlouhé pauze se počítá znovu).
    var completed = 0
    /// Konec fáze už byl oznámen a čeká se na reakci uživatele.
    var awaiting = false
}

enum PomodoroPolicy {
    static let snooze: TimeInterval = 5 * 60

    static func duration(of phase: PomodoroPhase, settings: PomodoroSettings) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .work: minutes = settings.workMinutes
        case .shortBreak: minutes = settings.shortBreakMinutes
        case .longBreak: minutes = settings.longBreakMinutes
        }
        return TimeInterval(max(1, minutes)) * 60
    }

    static func endDate(of state: PomodoroState, settings: PomodoroSettings) -> Date {
        state.phaseStart.addingTimeInterval(duration(of: state.phase, settings: settings) + state.extra)
    }

    static func isDue(_ state: PomodoroState, now: Date, settings: PomodoroSettings) -> Bool {
        !state.awaiting && now >= endDate(of: state, settings: settings)
    }

    /// Další fáze, která začíná v `moment`: práce → (krátká | dlouhá) pauza → práce.
    static func advance(_ state: PomodoroState, settings: PomodoroSettings, at moment: Date) -> PomodoroState {
        switch state.phase {
        case .work:
            let done = state.completed + 1
            let long = done >= max(1, settings.cyclesBeforeLongBreak)
            return PomodoroState(phase: long ? .longBreak : .shortBreak, phaseStart: moment, completed: done)
        case .shortBreak:
            return PomodoroState(phase: .work, phaseStart: moment, completed: state.completed)
        case .longBreak:
            return PomodoroState(phase: .work, phaseStart: moment, completed: 0)
        }
    }

    /// Přeskočí (nadcházející nebo běžící) pauzu a rovnou začne další pomodoro.
    static func skipBreak(_ state: PomodoroState, settings: PomodoroSettings, at moment: Date) -> PomodoroState {
        var next = advance(state, settings: settings, at: moment)
        if next.phase.isBreak { next = advance(next, settings: settings, at: moment) }
        return next
    }

    /// Zbývající čas fáze (po konci 0).
    static func remaining(_ state: PomodoroState, now: Date, settings: PomodoroSettings) -> TimeInterval {
        max(0, endDate(of: state, settings: settings).timeIntervalSince(now))
    }

    /// Podíl uplynulé části fáze, 0…1.
    static func progress(_ state: PomodoroState, now: Date, settings: PomodoroSettings) -> Double {
        let total = duration(of: state.phase, settings: settings) + state.extra
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(state.phaseStart) / total))
    }

    /// Akce, které dává smysl nabídnout ve stavu `state` (stejné jako tlačítka v oznámení).
    static func availableActions(_ state: PomodoroState) -> [PomodoroAction] {
        if state.awaiting {
            return state.phase == .work ? [.startNext, .snooze, .skipBreak] : [.startNext, .snooze]
        }
        return state.phase.isBreak ? [.skipBreak] : []
    }

    /// „Ještě 5 minut“: fáze skončí za `snooze` od `now`.
    static func snoozed(_ state: PomodoroState, settings: PomodoroSettings, now: Date) -> PomodoroState {
        var next = state
        next.awaiting = false
        next.extra = now.timeIntervalSince(state.phaseStart) - duration(of: state.phase, settings: settings) + snooze
        return next
    }
}

/// Co se uživateli oznamuje na hranici fází.
enum PomodoroNotice: Equatable {
    /// Práce skončila, čeká se na spuštění pauzy.
    case breakDue(PomodoroPhase, completed: Int)
    /// Pauza skončila, čeká se na spuštění práce.
    case workDue
    /// Pauza začala sama (automatické navazování).
    case breakStarted(PomodoroPhase, completed: Int)
    /// Další pomodoro začalo samo.
    case workStarted

    func text(settings: PomodoroSettings) -> (title: String, body: String) {
        let work = Int(PomodoroPolicy.duration(of: .work, settings: settings) / 60)
        func minutes(_ phase: PomodoroPhase) -> Int { Int(PomodoroPolicy.duration(of: phase, settings: settings) / 60) }
        switch self {
        case .breakDue(let phase, let completed):
            return (phase == .longBreak ? "Čas na dlouhou pauzu" : "Čas na pauzu",
                    "Pomodoro č. \(completed) hotovo. \(phase == .longBreak ? "Dlouhá" : "Krátká") pauza \(minutes(phase)) min.")
        case .workDue:
            return ("Pauza skončila", "Můžeš pokračovat – další pomodoro (\(work) min).")
        case .breakStarted(let phase, let completed):
            return (phase == .longBreak ? "Začíná dlouhá pauza" : "Začíná pauza",
                    "Pomodoro č. \(completed) hotovo. Pauza \(minutes(phase)) min.")
        case .workStarted:
            return ("Zpátky do práce", "Začíná další pomodoro (\(work) min).")
        }
    }
}

enum PomodoroAction {
    /// Spustí následující fázi hned.
    case startNext
    case snooze
    case skipBreak
}

/// Sleduje cyklus Pomodora vázaný na běžící časovač: začíná se spuštěním časovače, končí jeho zastavením.
/// Jen připomíná – měření času nijak neovlivňuje.
@MainActor
@Observable
final class PomodoroScheduler {
    @ObservationIgnored private let timer: TimerController
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let settings: () -> PomodoroSettings
    @ObservationIgnored private let notify: (PomodoroNotice, String, String) -> Void
    @ObservationIgnored private var ticker: Timer?
    private(set) var state: PomodoroState?
    /// Má být vidět plovoucí okno (cyklus běží a je zapnutý vizuální časovač).
    private(set) var showsVisual = false

    /// Aktuální nastavení – pohled z něj bere délky fází a počet pomodor v sérii.
    var currentSettings: PomodoroSettings { settings() }

    init(
        timer: TimerController,
        clock: @escaping () -> Date = Date.init,
        settings: @escaping () -> PomodoroSettings = { AppSettings.pomodoro },
        notify: @escaping (PomodoroNotice, String, String) -> Void
    ) {
        self.timer = timer
        self.clock = clock
        self.settings = settings
        self.notify = notify
    }

    func start(interval: TimeInterval = 1) {
        guard ticker == nil else { return }
        let ticker = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func check() {
        let now = clock()
        let config = settings()
        defer {
            let visible = config.visualTimer && state != nil
            if showsVisual != visible { showsVisual = visible }
        }
        guard config.isActive, timer.runningEntry != nil else {
            if state != nil { state = nil }
            return
        }
        guard var current = state else {
            state = PomodoroState(phaseStart: now)
            return
        }
        guard PomodoroPolicy.isDue(current, now: now, settings: config) else { return }

        let upcoming = PomodoroPolicy.advance(current, settings: config, at: now)
        let notice: PomodoroNotice
        if config.autoAdvance {
            state = upcoming
            notice = upcoming.phase.isBreak
                ? .breakStarted(upcoming.phase, completed: upcoming.completed) : .workStarted
        } else {
            current.awaiting = true
            state = current
            notice = upcoming.phase.isBreak
                ? .breakDue(upcoming.phase, completed: upcoming.completed) : .workDue
        }
        guard config.notifications else { return }
        let text = notice.text(settings: config)
        notify(notice, text.title, text.body)
    }

    /// Reakce na tlačítko v oznámení; zastaralá oznámení (fáze už pokročila) se ignorují.
    func perform(_ action: PomodoroAction) {
        guard let current = state else { return }
        let now = clock()
        let config = settings()
        switch action {
        case .startNext:
            guard current.awaiting else { return }
            state = PomodoroPolicy.advance(current, settings: config, at: now)
        case .snooze:
            guard current.awaiting else { return }
            state = PomodoroPolicy.snoozed(current, settings: config, now: now)
        case .skipBreak:
            // Práce, která ještě neskončila, se přeskakovat nemá.
            guard current.awaiting || current.phase.isBreak else { return }
            state = PomodoroPolicy.skipBreak(current, settings: config, at: now)
        }
    }
}
