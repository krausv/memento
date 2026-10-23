import Foundation
import SwiftData

/// Verzovaný přenosný formát zálohy. Záměrně JSON, ne kopie souboru SwiftData:
/// ta je u běžící databáze nespolehlivá a nepřenese se mezi verzemi schématu.
struct Backup: Codable, Equatable {
    static let currentVersion = 1

    struct ProjectData: Codable, Equatable {
        var id: UUID
        var name: String
        var client: String?
        /// Řetězec, ne číslo – JSON čísla by `Decimal` zaokrouhlila přes `Double`.
        var hourlyRate: String
        var currency: String
        var isArchived: Bool
        var createdAt: Date
    }

    struct EntryData: Codable, Equatable {
        var id: UUID
        var projectID: UUID
        var start: Date
        var end: Date?
        var note: String?
    }

    struct SettingsData: Codable, Equatable {
        var defaultRate: String
        var roundingMinutes: Int
        var supplierName: String?
        var supplierIco: String?
    }

    var version: Int
    var exportedAt: Date
    var projects: [ProjectData]
    var entries: [EntryData]
    var settings: SettingsData
}

enum BackupError: LocalizedError, Equatable {
    case unreadable
    case unsupportedVersion(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "Soubor není platná záloha Memento."
        case .unsupportedVersion(let v): "Záloha má verzi \(v), tato aplikace umí verzi \(Backup.currentVersion)."
        case .invalid(let reason): "Záloha je poškozená: \(reason)"
        }
    }
}

enum RestoreMode {
    /// Přidá, co v aplikaci chybí (podle UUID); nic nemaže ani nepřepisuje.
    case merge
    /// Smaže všechna data a nahradí je zálohou, včetně nastavení.
    case replace
}

struct RestoreSummary: Equatable {
    var addedProjects = 0
    var addedEntries = 0
    var skippedEntries = 0
}

enum BackupService {
    // MARK: Export

    @MainActor
    static func makeBackup(context: ModelContext, now: Date = Date(), defaults: UserDefaults = .standard) throws -> Backup {
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.start)]))
        return Backup(
            version: Backup.currentVersion,
            exportedAt: now,
            projects: projects.map {
                .init(id: $0.id, name: $0.name, client: $0.client, hourlyRate: "\($0.hourlyRate)",
                      currency: $0.currency, isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            entries: entries.compactMap { entry in
                guard let project = entry.project else { return nil }
                return .init(id: entry.id, projectID: project.id, start: entry.start, end: entry.end, note: entry.note)
            },
            settings: .init(
                defaultRate: defaults.string(forKey: SettingsKey.defaultRate) ?? "0",
                roundingMinutes: defaults.integer(forKey: SettingsKey.rounding),
                supplierName: defaults.string(forKey: SettingsKey.supplierName),
                supplierIco: defaults.string(forKey: SettingsKey.supplierIco)
            )
        )
    }

    static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: Import

    /// Načte a zkontroluje zálohu. Nic nezapisuje.
    static func decode(_ data: Data) throws -> Backup {
        struct Header: Decodable { var version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw BackupError.unreadable }
        guard header.version == Backup.currentVersion else { throw BackupError.unsupportedVersion(header.version) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data) else { throw BackupError.unreadable }
        try validate(backup)
        return backup
    }

    static func validate(_ backup: Backup) throws {
        var ids = Set<UUID>()
        var names = Set<String>()
        for project in backup.projects {
            guard ids.insert(project.id).inserted else { throw BackupError.invalid("duplicitní projekt") }
            guard names.insert(project.name.lowercased()).inserted else {
                throw BackupError.invalid("projekt „\(project.name)“ je v záloze dvakrát")
            }
            guard let rate = Decimal(string: project.hourlyRate, locale: Locale(identifier: "en_US_POSIX")), rate >= 0 else {
                throw BackupError.invalid("neplatná sazba projektu „\(project.name)“")
            }
        }
        var entryIDs = Set<UUID>()
        var running = 0
        for entry in backup.entries {
            guard entryIDs.insert(entry.id).inserted else { throw BackupError.invalid("duplicitní záznam") }
            guard ids.contains(entry.projectID) else { throw BackupError.invalid("záznam odkazuje na neexistující projekt") }
            if let end = entry.end {
                guard end > entry.start else { throw BackupError.invalid("záznam, který nekončí po začátku") }
            } else {
                running += 1
            }
        }
        guard running <= 1 else { throw BackupError.invalid("víc běžících záznamů") }
    }

    @MainActor
    @discardableResult
    static func restore(
        _ backup: Backup, mode: RestoreMode, context: ModelContext, defaults: UserDefaults = .standard
    ) throws -> RestoreSummary {
        try validate(backup)
        var summary = RestoreSummary()

        if mode == .replace {
            for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
            try context.save()
        }

        var projects: [UUID: Project] = [:]
        let existing = try context.fetch(FetchDescriptor<Project>())
        var byName = Dictionary(existing.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for project in existing { projects[project.id] = project }

        // Mapování ID z přenosu na lokální projekt (kvůli sloučení projektů se stejným názvem).
        var localProject: [UUID: Project] = [:]
        for data in backup.projects {
            if let match = projects[data.id] ?? byName[data.name.lowercased()] {
                localProject[data.id] = match
                continue
            }
            let project = Project(
                name: data.name, client: data.client,
                hourlyRate: Decimal(string: data.hourlyRate, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
                currency: data.currency
            )
            project.id = data.id
            project.isArchived = data.isArchived
            project.createdAt = data.createdAt
            context.insert(project)
            localProject[data.id] = project
            byName[data.name.lowercased()] = project
            summary.addedProjects += 1
        }

        let existingEntries = Set(try context.fetch(FetchDescriptor<TimeEntry>()).map(\.id))
        var hasRunning = try context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.end == nil })).isEmpty == false
        for data in backup.entries {
            guard !existingEntries.contains(data.id), let project = localProject[data.projectID] else {
                summary.skippedEntries += 1
                continue
            }
            // Dva běžící záznamy by porušily pravidlo „jeden časovač“.
            if data.end == nil {
                if hasRunning { summary.skippedEntries += 1; continue }
                hasRunning = true
            }
            let entry = TimeEntry(project: project, start: data.start, end: data.end, note: data.note)
            entry.id = data.id
            context.insert(entry)
            summary.addedEntries += 1
        }
        try context.save()

        if mode == .replace {
            defaults.set(backup.settings.defaultRate, forKey: SettingsKey.defaultRate)
            defaults.set(backup.settings.roundingMinutes, forKey: SettingsKey.rounding)
            set(backup.settings.supplierName, forKey: SettingsKey.supplierName, in: defaults)
            set(backup.settings.supplierIco, forKey: SettingsKey.supplierIco, in: defaults)
        }
        return summary
    }

    private static func set(_ value: String?, forKey key: String, in defaults: UserDefaults) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
