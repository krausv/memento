import Foundation

enum SettingsKey {
    static let defaultRate = "defaultHourlyRate"
    static let rounding = "exportRoundingMinutes"
    static let supplierName = "supplierName"
    static let supplierIco = "supplierIco"
    static let reminders = "reminderSettings"
    static let autoBackup = "autoBackupSettings"
    static let lastAutoBackup = "autoBackupLast"
    static let autoBackupError = "autoBackupError"
    static let palette = "colorPalette"
}

enum AppSettings {
    static var defaultRate: Decimal {
        get { Decimal(string: UserDefaults.standard.string(forKey: SettingsKey.defaultRate) ?? "") ?? 0 }
        set { UserDefaults.standard.set("\(newValue)", forKey: SettingsKey.defaultRate) }
    }

    static var rounding: RoundingOption {
        RoundingOption(rawValue: UserDefaults.standard.integer(forKey: SettingsKey.rounding)) ?? .none
    }

    /// Uloženo jako JSON, aby se nastavení připomínek četlo a zálohovalo jako jeden celek.
    static var reminders: ReminderSettings {
        get {
            UserDefaults.standard.data(forKey: SettingsKey.reminders)
                .flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) } ?? ReminderSettings()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: SettingsKey.reminders) }
    }

    static func autoBackup(_ defaults: UserDefaults = .standard) -> AutoBackupSettings {
        defaults.data(forKey: SettingsKey.autoBackup)
            .flatMap { try? JSONDecoder().decode(AutoBackupSettings.self, from: $0) } ?? AutoBackupSettings()
    }

    static func setAutoBackup(_ settings: AutoBackupSettings, _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: SettingsKey.autoBackup)
    }

    static func lastAutoBackup(_ defaults: UserDefaults = .standard) -> Date? {
        let value = defaults.double(forKey: SettingsKey.lastAutoBackup)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    static func lastAutoBackupError(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: SettingsKey.autoBackupError)
    }

    /// Úspěch (`date`) smaže poslední chybu, selhání (`error`) ponechá čas poslední úspěšné zálohy.
    static func recordAutoBackup(date: Date?, error: String?, _ defaults: UserDefaults = .standard) {
        if let date { defaults.set(date.timeIntervalSince1970, forKey: SettingsKey.lastAutoBackup) }
        if let error { defaults.set(error, forKey: SettingsKey.autoBackupError) }
        else { defaults.removeObject(forKey: SettingsKey.autoBackupError) }
    }

    static var supplierName: String? { nonEmpty(SettingsKey.supplierName) }
    static var supplierIco: String? { nonEmpty(SettingsKey.supplierIco) }

    private static func nonEmpty(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
