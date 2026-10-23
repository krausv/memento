import Foundation

enum SettingsKey {
    static let defaultRate = "defaultHourlyRate"
    static let rounding = "exportRoundingMinutes"
    static let supplierName = "supplierName"
    static let supplierIco = "supplierIco"
}

enum AppSettings {
    static var defaultRate: Decimal {
        get { Decimal(string: UserDefaults.standard.string(forKey: SettingsKey.defaultRate) ?? "") ?? 0 }
        set { UserDefaults.standard.set("\(newValue)", forKey: SettingsKey.defaultRate) }
    }

    static var rounding: RoundingOption {
        RoundingOption(rawValue: UserDefaults.standard.integer(forKey: SettingsKey.rounding)) ?? .none
    }

    static var supplierName: String? { nonEmpty(SettingsKey.supplierName) }
    static var supplierIco: String? { nonEmpty(SettingsKey.supplierIco) }

    private static func nonEmpty(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
