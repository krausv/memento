import Foundation

enum SettingsKey {
    static let defaultRate = "defaultHourlyRate"
    static let rounding = "exportRoundingMinutes"
    static let supplierName = "supplierName"
    static let supplierIco = "supplierIco"
    static let reminders = "reminderSettings"
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

    static var supplierName: String? { nonEmpty(SettingsKey.supplierName) }
    static var supplierIco: String? { nonEmpty(SettingsKey.supplierIco) }

    private static func nonEmpty(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
