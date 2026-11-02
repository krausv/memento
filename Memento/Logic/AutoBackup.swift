import AppKit
import Foundation
import SwiftData

enum AutoBackupFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly

    var id: String { rawValue }
    var title: String { self == .daily ? "Denně" : "Týdně" }
    var interval: TimeInterval { self == .daily ? 24 * 3600 : 7 * 24 * 3600 }
}

/// Nastavení je jen místní (cesta ke složce nedává smysl na jiném Macu), proto není součástí zálohy.
struct AutoBackupSettings: Codable, Equatable {
    var enabled = false
    var folderPath: String?
    var frequency = AutoBackupFrequency.weekly
    /// Kolik posledních automatických záloh ve složce zůstane; starší se smažou.
    var keepCount = 10
}

enum AutoBackupError: LocalizedError, Equatable {
    case noFolder
    case folderUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noFolder: "Není zvolená složka pro zálohy."
        case .folderUnavailable(let path): "Složka pro zálohy není dostupná: \(path)"
        }
    }
}

enum AutoBackupPolicy {
    /// Malá rezerva, aby záloha po restartu nepřeskočila o pár minut.
    static let tolerance: TimeInterval = 5 * 60

    static func isDue(now: Date, lastBackup: Date?, settings: AutoBackupSettings) -> Bool {
        guard settings.enabled, settings.folderPath != nil else { return false }
        guard let last = lastBackup else { return true }
        return now.timeIntervalSince(last) >= settings.frequency.interval - tolerance
    }

    /// Nejmenší odstup záloh vyvolaných změnou, ať se při častém přepínání nezaplní složka.
    static let changeGap: TimeInterval = 15 * 60

    /// Záloha po změně dat (start/stop měření): hned, ale nejvýš jednou za `changeGap`.
    static func isDueAfterChange(now: Date, lastBackup: Date?, settings: AutoBackupSettings) -> Bool {
        guard settings.enabled, settings.folderPath != nil else { return false }
        guard let last = lastBackup else { return true }
        return now.timeIntervalSince(last) >= changeGap
    }

    static let prefix = "memento-auto-"

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .prague
        formatter.timeZone = Calendar.prague.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(prefix)\(formatter.string(from: date)).json"
    }

    /// Jen vlastní soubory podle přesného vzoru názvu – cokoli jiného ve složce se nikdy nemaže.
    static func isAutoBackupName(_ name: String) -> Bool {
        name.range(of: #"^memento-auto-\d{4}-\d{2}-\d{2}-\d{4}\.json$"#, options: .regularExpression) != nil
    }

    /// Názvy ke smazání: vše kromě `keep` nejnovějších (název obsahuje čas, takže stačí řadit podle něj).
    static func namesToPrune(_ names: [String], keep: Int) -> [String] {
        let backups = names.filter(isAutoBackupName).sorted(by: >)
        return Array(backups.dropFirst(max(1, keep)))
    }
}

enum AutoBackupService {
    @MainActor
    @discardableResult
    static func run(
        context: ModelContext,
        settings: AutoBackupSettings,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws -> URL {
        guard let path = settings.folderPath else { throw AutoBackupError.noFolder }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: path)
        else { throw AutoBackupError.folderUnavailable(path) }

        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let backup = try BackupService.makeBackup(context: context, now: now, defaults: defaults)
        let url = folder.appendingPathComponent(AutoBackupPolicy.fileName(for: now))
        try BackupService.encode(backup).write(to: url, options: .atomic)

        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for name in AutoBackupPolicy.namesToPrune(names, keep: settings.keepCount) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        return url
    }
}

extension AutoBackupService {
    /// Záložní složka pro zálohy před aktualizací, když není zapnutá automatická záloha do vlastní složky.
    static var fallbackFolder: URL {
        StoreLocation.appSupport()
            .appendingPathComponent(StoreLocation.folderName, isDirectory: true)
            .appendingPathComponent("Zálohy", isDirectory: true)
    }

    /// Záloha těsně před výměnou aplikace. Použije složku z Nastavení, pokud je zálohování zapnuté a složka
    /// dostupná; jinak složku `fallbackFolder`, takže se udělá vždy. Selhání se vrací jako chyba (aktualizace se pak nespustí).
    @MainActor
    @discardableResult
    static func runBeforeUpdate(
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        fallback: URL = AutoBackupService.fallbackFolder
    ) throws -> URL {
        var settings = AppSettings.autoBackup(defaults)
        var isDirectory: ObjCBool = false
        let configuredUsable = settings.enabled && settings.folderPath.map {
            FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
                && FileManager.default.isWritableFile(atPath: $0)
        } == true
        if configuredUsable {
            let url = try run(context: context, settings: settings, now: now, defaults: defaults)
            AppSettings.recordAutoBackup(date: now, error: nil, defaults)
            return url
        }
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        settings.folderPath = fallback.path
        settings.keepCount = max(settings.keepCount, 5)
        return try run(context: context, settings: settings, now: now, defaults: defaults)
    }
}

/// Spouští automatickou zálohu, když je „na řadě“: po startu, po probuzení Macu a pak jednou za hodinu.
@MainActor
final class AutoBackupScheduler {
    private let context: ModelContext
    private let clock: () -> Date
    private let defaults: UserDefaults
    private let notifyFailure: (String) -> Void
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        context: ModelContext,
        clock: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard,
        notifyFailure: @escaping (String) -> Void
    ) {
        self.context = context
        self.clock = clock
        self.defaults = defaults
        self.notifyFailure = notifyFailure
    }

    func start(interval: TimeInterval = 3600) {
        guard ticker == nil else { return }
        let ticker = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        checkNow()
    }

    func checkNow() {
        let settings = AppSettings.autoBackup(defaults)
        let now = clock()
        guard AutoBackupPolicy.isDue(now: now, lastBackup: AppSettings.lastAutoBackup(defaults), settings: settings) else { return }
        perform(settings: settings, now: now)
    }

    /// Volá se po změně měření: zálohuje i mimo denní/týdenní plán, aby se neztratila práce od poslední zálohy.
    func checkAfterChange() {
        let settings = AppSettings.autoBackup(defaults)
        let now = clock()
        guard AutoBackupPolicy.isDueAfterChange(now: now, lastBackup: AppSettings.lastAutoBackup(defaults), settings: settings) else { return }
        perform(settings: settings, now: now)
    }

    /// Společné pro automatický běh i tlačítko „Zálohovat teď“; chybu zapíše, aby ji Nastavení ukázalo.
    @discardableResult
    func perform(settings: AutoBackupSettings, now: Date) -> Bool {
        do {
            try AutoBackupService.run(context: context, settings: settings, now: now)
            AppSettings.recordAutoBackup(date: now, error: nil, defaults)
            return true
        } catch {
            let wasFailing = AppSettings.lastAutoBackupError(defaults) != nil
            AppSettings.recordAutoBackup(date: nil, error: error.localizedDescription, defaults)
            // Chyba se oznámí jednou; další hodinové pokusy už neotravují.
            if !wasFailing { notifyFailure(error.localizedDescription) }
            return false
        }
    }
}
