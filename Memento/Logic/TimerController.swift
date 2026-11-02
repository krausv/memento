import Foundation
import Observation
import SwiftData

/// Start/stop/přepnutí časovače. Běžící záznam je uložen hned při startu (`end == nil`),
/// takže přežije ukončení aplikace i restart; po spuštění se jen znovu načte.
@MainActor
@Observable
final class TimerController {
    private let context: ModelContext
    private let clock: () -> Date
    private var ticker: Timer?

    /// Volá se po každém startu a zastavení (např. kontrola limitů).
    var onChange: (() -> Void)?

    private(set) var runningEntry: TimeEntry?
    /// Aktualizuje se každou sekundu, dokud časovač běží.
    private(set) var now: Date

    init(context: ModelContext, clock: @escaping () -> Date = Date.init) {
        self.context = context
        self.clock = clock
        self.now = clock()
        refresh()
    }

    var elapsed: TimeInterval {
        runningEntry?.duration(at: now) ?? 0
    }

    var elapsedText: String { CzFormat.elapsed(elapsed) }

    /// Znovu načte běžící záznam z úložiště. Kdyby jich běželo víc (poškozená data),
    /// starší se ukončí v okamžiku začátku následujícího.
    func refresh() {
        let descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.end == nil },
            sortBy: [SortDescriptor(\.start)]
        )
        let open = (try? context.fetch(descriptor)) ?? []
        if open.count > 1 {
            for (older, newer) in zip(open, open.dropFirst()) { older.end = newer.start }
            try? context.save()
        }
        runningEntry = open.last
        now = clock()
        updateTicker()
    }

    @discardableResult
    func start(_ project: Project, note: String? = nil, tags: [Tag] = []) throws -> TimeEntry {
        let moment = clock()
        if let running = runningEntry {
            running.end = max(moment, running.start)
        }
        let entry = TimeEntry(project: project, start: moment, note: note)
        context.insert(entry)
        entry.tags = tags
        try context.save()
        refresh()
        onChange?()
        return entry
    }

    /// Poslední ukončený záznam, jehož projekt jde ještě spustit.
    func lastResumableEntry() -> TimeEntry? {
        var descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.end != nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.first { $0.project.map { !$0.isArchived } ?? false }
    }

    /// Starší záznam už je jiná práce – spustí se stejný projekt, ale bez poznámky.
    static let resumeWindow: TimeInterval = 2 * 3600

    /// Je poslední záznam dost čerstvý, aby se z něj převzala poznámka?
    func continuesNote(of entry: TimeEntry) -> Bool {
        guard let end = entry.end else { return false }
        return clock().timeIntervalSince(end) <= Self.resumeWindow
    }

    /// Spustí projekt posledního záznamu; poznámku a štítky převezme jen pokud skončil před méně než dvěma hodinami.
    @discardableResult
    func resumeLast() throws -> TimeEntry? {
        guard let last = lastResumableEntry(), let project = last.project else { return nil }
        let fresh = continuesNote(of: last)
        return try start(project, note: fresh ? last.note : nil, tags: fresh ? last.tags : [])
    }

    /// Nejrozumnější start bez volby: navázání na poslední záznam, jinak naposledy použitý projekt.
    @discardableResult
    func startDefault() throws -> TimeEntry? {
        if let resumed = try resumeLast() { return resumed }
        guard let project = selectableProjects().first else { return nil }
        return try start(project)
    }

    func stop() throws {
        guard let running = runningEntry else { return }
        running.end = max(clock(), running.start)
        try context.save()
        refresh()
        onChange?()
    }

    /// Posune začátek běžícího záznamu (typicky když se zapomnělo časovač zapnout).
    /// Nový začátek nesmí být v budoucnu ani zasahovat do jiného záznamu.
    func moveStart(to newStart: Date) throws {
        guard let running = runningEntry, newStart != running.start else { return }
        let moment = clock()
        guard newStart < moment else { throw EntryValidationError.startInFuture }
        let others = ((try? context.fetch(FetchDescriptor<TimeEntry>())) ?? [])
            .map { EntryInterval(id: $0.id, start: $0.start, end: $0.end) }
        try EntryValidator.validate(start: newStart, end: moment, editing: running.id, existing: others, now: moment)
        running.start = newStart
        try context.save()
        now = moment
        onChange?()
    }

    /// Aktivní projekty, naposledy použité první; projekty bez záznamů jsou na konci.
    func selectableProjects() -> [Project] {
        let projects = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var lastUse: [UUID: Date] = [:]
        for project in projects {
            lastUse[project.id] = project.entries.map(\.start).max()
        }
        return projects
            .filter { !$0.isArchived }
            .sorted { (lastUse[$0.id] ?? .distantPast) > (lastUse[$1.id] ?? .distantPast) }
    }

    private func updateTicker() {
        guard runningEntry != nil else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = self?.clock() ?? Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}

enum RunningStart {
    /// Hodnota z výběru data zaokrouhlená dolů na minuty; nezměněný začátek se vrací beze změny
    /// (sekundy původního začátku by se jinak zbytečně ztratily).
    static func rounded(_ picked: Date, original: Date) -> Date {
        let originalMinute = floorMinute(original)
        let pickedMinute = floorMinute(picked)
        return pickedMinute == originalMinute ? original : pickedMinute
    }

    private static func floorMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
