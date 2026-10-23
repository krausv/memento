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
        var seconds: [Key: Int] = [:]
        var info: [Key: BillingEntry] = [:]
        for entry in entries {
            let key = Key(project: entry.projectKey, month: ReportMonth(containing: entry.start, calendar: calendar))
            seconds[key, default: 0] += Self.seconds(entry, now: now, rounding: rounding)
            info[key] = entry
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
