import Foundation

/// Fakturovaná částka v jedné měně.
struct CurrencyAmount: Equatable {
    var currency: String
    var amount: Decimal
}

/// Vstup pro výpočet částek – čistá hodnota bez závislosti na SwiftData.
struct BillingEntry: Equatable {
    var projectKey: UUID
    var currency: String
    var hourlyRate: Decimal
    var start: Date
    /// `nil` = běží, počítá se do `now`.
    var end: Date?
    /// Navazuje na předchozí záznam (Pokračovat) – počítá se spolu s ním jako jeden záznam.
    var continuesPrevious = false
}

enum Billing {
    /// Sekundy záznamu po zaokrouhlení z exportu.
    static func seconds(_ entry: BillingEntry, now: Date, rounding: RoundingOption) -> Int {
        let raw = max(0, Int(((entry.end ?? now).timeIntervalSince(entry.start)).rounded()))
        return rounding.apply(toSeconds: raw)
    }

    /// Částky podle měn. Počítá se stejně jako ve výkazu: sekundy se sečtou za projekt a měsíc
    /// a na haléře se zaokrouhlí až součet, takže měsíční součty sedí s PDF.
    static func totals(
        _ entries: [BillingEntry], now: Date, rounding: RoundingOption, calendar: Calendar = .prague
    ) -> [CurrencyAmount] {
        struct Key: Hashable { var project: UUID; var month: ReportMonth }
        var byKey: [Key: [BillingEntry]] = [:]
        for entry in entries {
            byKey[Key(project: entry.projectKey, month: ReportMonth(containing: entry.start, calendar: calendar)), default: []]
                .append(entry)
        }
        var seconds: [Key: Int] = [:]
        var info: [Key: BillingEntry] = [:]
        for (key, list) in byKey {
            // Navázané záznamy se zaokrouhlují společně, stejně jako řádek ve výkazu.
            for chain in EntryChains.group(
                list, project: { _ in nil }, start: \.start, end: { $0.end ?? now }, continues: \.continuesPrevious
            ) {
                let raw = chain.reduce(0) { $0 + max(0, Int((($1.end ?? now).timeIntervalSince($1.start)).rounded())) }
                seconds[key, default: 0] += rounding.apply(toSeconds: raw)
            }
            info[key] = list[0]
        }
        var byCurrency: [String: Decimal] = [:]
        for (key, total) in seconds {
            guard let entry = info[key] else { continue }
            byCurrency[entry.currency, default: 0] += (Decimal(total) * entry.hourlyRate / 3600).rounded(scale: 2)
        }
        return byCurrency.map { CurrencyAmount(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }

    /// `18 750,00 Kč` nebo `18 750,00 Kč + 120,00 €` při víc měnách.
    static func text(_ amounts: [CurrencyAmount]) -> String {
        amounts.isEmpty ? "—" : amounts.map { CzFormat.money($0.amount, currency: $0.currency) }.joined(separator: " + ")
    }
}
