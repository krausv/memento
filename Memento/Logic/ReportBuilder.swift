import Foundation

enum RoundingOption: Int, CaseIterable, Identifiable {
    case none = 0
    case five = 5
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    var title: String {
        switch self {
        case .none: "Žádné"
        case .five: "Na 5 minut nahoru"
        case .fifteen: "Na 15 minut nahoru"
        case .thirty: "Na 30 minut nahoru"
        }
    }

    /// Zaokrouhlí počet sekund nahoru na násobek zvolené jednotky.
    func apply(toSeconds seconds: Int) -> Int {
        guard minutes > 0, seconds > 0 else { return seconds }
        let step = minutes * 60
        return (seconds + step - 1) / step * step
    }
}

struct ReportMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: ReportMonth, rhs: ReportMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(containing date: Date, calendar: Calendar = .prague) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year!, month: parts.month!)
    }

    /// Záznam patří do měsíce, ve kterém začal.
    func contains(_ start: Date, calendar: Calendar = .prague) -> Bool {
        ReportMonth(containing: start, calendar: calendar) == self
    }

    func previous() -> ReportMonth {
        month == 1 ? ReportMonth(year: year - 1, month: 12) : ReportMonth(year: year, month: month - 1)
    }

    var firstDay: Date {
        Calendar.prague.date(from: DateComponents(year: year, month: month, day: 1))!
    }
}

/// Vstup pro `ReportBuilder` – čistá hodnota bez závislosti na SwiftData.
struct ReportEntry: Equatable {
    var note: String?
    var start: Date
    var end: Date
    /// Záznam vznikl navázáním (Pokračovat) na předchozí; ve výkazu se s ním sloučí do jednoho řádku.
    var continuesPrevious = false
}

struct Report: Equatable {
    struct Row: Equatable {
        let start: Date
        let end: Date
        let note: String?
        /// Již po zaokrouhlení nastaveném v exportu.
        let seconds: Int
    }

    let projectName: String
    let client: String?
    let month: ReportMonth
    let currency: String
    let hourlyRate: Decimal
    let rows: [Row]
    let totalSeconds: Int
    /// Přesný součet sekund × sazba, zaokrouhleno na haléře až na konci.
    let amount: Decimal

    static func hours(fromSeconds seconds: Int) -> Decimal {
        (Decimal(seconds) / 3600).rounded(scale: 2)
    }

    var totalHours: Decimal { Report.hours(fromSeconds: totalSeconds) }
}

struct ReportBuilder {
    var calendar: Calendar = .prague

    func build(
        projectName: String,
        client: String?,
        currency: String,
        hourlyRate: Decimal,
        month: ReportMonth,
        rounding: RoundingOption,
        entries: [ReportEntry]
    ) -> Report {
        // Navázané záznamy (stejná poznámka, jen přerušené měření) se ve výkazu ukážou jako jeden řádek:
        // od začátku prvního do konce posledního, délka je součet skutečně odpracovaného času.
        let inMonth = entries.filter { month.contains($0.start, calendar: calendar) }
        let rows = EntryChains.group(
            inMonth, project: { _ in nil }, start: \.start, end: { $0.end }, continues: \.continuesPrevious
        ).map { chain -> Report.Row in
            let raw = chain.reduce(0) { $0 + max(0, Int($1.end.timeIntervalSince($1.start).rounded())) }
            let note = chain.last(where: { !($0.note ?? "").isEmpty })?.note ?? chain.last?.note
            return Report.Row(
                start: chain[0].start, end: chain.map(\.end).max() ?? chain[0].end,
                note: note, seconds: rounding.apply(toSeconds: raw)
            )
        }

        let total = rows.reduce(0) { $0 + $1.seconds }
        let amount = (Decimal(total) * hourlyRate / 3600).rounded(scale: 2)

        return Report(
            projectName: projectName,
            client: client,
            month: month,
            currency: currency,
            hourlyRate: hourlyRate,
            rows: rows,
            totalSeconds: total,
            amount: amount
        )
    }
}
