import Foundation
import SwiftData

enum BudgetPeriod: String, CaseIterable, Identifiable {
    case total
    case monthly

    var id: String { rawValue }
    var title: String { self == .total ? "Celkem" : "Měsíčně" }
}

/// Čerpání rozpočtu hodin projektu. Čistá logika bez závislosti na SwiftData.
struct BudgetStatus: Equatable {
    struct Entry {
        var start: Date
        /// `nil` = běží, počítá se do `now`.
        var end: Date?
    }

    static let warningLevel = 80
    static let exceededLevel = 100

    let usedSeconds: Int
    let budgetSeconds: Int

    var fraction: Double { budgetSeconds > 0 ? Double(usedSeconds) / Double(budgetSeconds) : 0 }

    /// 0 = v pořádku, 80 = blíží se limit, 100 = překročeno.
    var level: Int {
        if usedSeconds >= budgetSeconds { return Self.exceededLevel }
        return fraction >= Double(Self.warningLevel) / 100 ? Self.warningLevel : 0
    }

    static func compute(
        budgetHours: Decimal,
        period: BudgetPeriod,
        entries: [Entry],
        now: Date,
        rounding: RoundingOption,
        calendar: Calendar = .prague
    ) -> BudgetStatus {
        let month = ReportMonth(containing: now, calendar: calendar)
        let used = entries
            .filter { period == .total || month.contains($0.start, calendar: calendar) }
            .reduce(0) { sum, entry in
                let raw = max(0, Int(((entry.end ?? now).timeIntervalSince(entry.start)).rounded()))
                return sum + rounding.apply(toSeconds: raw)
            }
        let budget = NSDecimalNumber(decimal: budgetHours * 3600).intValue
        return BudgetStatus(usedSeconds: used, budgetSeconds: budget)
    }

    /// Klíč období, ve kterém se hlídají upozornění: u měsíčního limitu se každý měsíc začíná znovu.
    static func periodKey(_ period: BudgetPeriod, now: Date, calendar: Calendar = .prague) -> String {
        guard period == .monthly else { return "total" }
        let month = ReportMonth(containing: now, calendar: calendar)
        return String(format: "%04d-%02d", month.year, month.month)
    }
}

/// Měsíční objem fakturace vůči cíli: pod / na / nad hranicí.
struct TargetStatus: Equatable {
    enum Position: Int {
        case under = 0, on, over
        var level: Int { rawValue }
    }

    /// „Na hranici“ je pásmo kolem cíle ±2 %, protože přesné trefení částky na haléř je nereálné.
    static let tolerance = Decimal(string: "0.02")!

    let amount: Decimal
    let target: Decimal

    var position: Position {
        if amount < target * (1 - Self.tolerance) { return .under }
        if amount > target * (1 + Self.tolerance) { return .over }
        return .on
    }

    /// Kladné = nad cílem, záporné = chybí do cíle.
    var difference: Decimal { amount - target }

    var fraction: Double { target > 0 ? NSDecimalNumber(decimal: amount / target).doubleValue : 0 }

    /// Částka za záznamy aktuálního měsíce, počítaná stejně jako ve výkazu (zaokrouhlení po záznamech, haléře až na konci).
    static func compute(
        target: Decimal,
        hourlyRate: Decimal,
        entries: [BudgetStatus.Entry],
        now: Date,
        rounding: RoundingOption,
        calendar: Calendar = .prague
    ) -> TargetStatus {
        let month = ReportMonth(containing: now, calendar: calendar)
        let seconds = entries
            .filter { month.contains($0.start, calendar: calendar) }
            .reduce(0) { sum, entry in
                let raw = max(0, Int(((entry.end ?? now).timeIntervalSince(entry.start)).rounded()))
                return sum + rounding.apply(toSeconds: raw)
            }
        let amount = (Decimal(seconds) * hourlyRate / 3600).rounded(scale: 2)
        return TargetStatus(amount: amount, target: target)
    }
}

extension Project {
    func targetStatus(now: Date, rounding: RoundingOption) -> TargetStatus? {
        guard let target = targetAmount, target > 0 else { return nil }
        return TargetStatus.compute(
            target: target, hourlyRate: hourlyRate,
            entries: entries.map { .init(start: $0.start, end: $0.end) },
            now: now, rounding: rounding
        )
    }

    var budgetPeriodValue: BudgetPeriod { BudgetPeriod(rawValue: budgetPeriod) ?? .total }

    func budgetStatus(now: Date, rounding: RoundingOption) -> BudgetStatus? {
        guard let hours = budgetHours, hours > 0 else { return nil }
        return BudgetStatus.compute(
            budgetHours: hours, period: budgetPeriodValue,
            entries: entries.map { .init(start: $0.start, end: $0.end) },
            now: now, rounding: rounding
        )
    }

    /// Nastaví stav upozornění podle aktuálního čerpání, aniž by se cokoli oznámilo
    /// (po změně limitu nebo po obnově ze zálohy).
    func syncBudgetAlertState(now: Date, rounding: RoundingOption) {
        budgetAlertKey = BudgetStatus.periodKey(budgetPeriodValue, now: now)
        budgetAlertLevel = budgetStatus(now: now, rounding: rounding)?.level ?? 0
        targetAlertKey = BudgetStatus.periodKey(.monthly, now: now)
        targetAlertLevel = targetStatus(now: now, rounding: rounding)?.position.level ?? 0
    }
}

/// Hlídá limity a posílá upozornění při 80 % a při překročení. Každá úroveň se v daném období oznámí jednou.
@MainActor
final class BudgetMonitor {
    private let context: ModelContext
    private let clock: () -> Date
    private let rounding: () -> RoundingOption
    private let notify: (String, String) -> Void
    private var ticker: Timer?

    init(
        context: ModelContext,
        clock: @escaping () -> Date = Date.init,
        rounding: @escaping () -> RoundingOption = { AppSettings.rounding },
        notify: @escaping (String, String) -> Void
    ) {
        self.context = context
        self.clock = clock
        self.rounding = rounding
        self.notify = notify
    }

    /// Běžící záznam může limit překročit i bez zásahu uživatele, proto i periodická kontrola.
    func start(interval: TimeInterval = 30) {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        check()
    }

    func check() {
        let now = clock()
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var changed = false
        for project in projects where !project.isArchived {
            if checkTarget(of: project, now: now) { changed = true }
            guard let status = project.budgetStatus(now: now, rounding: rounding()) else { continue }
            let key = BudgetStatus.periodKey(project.budgetPeriodValue, now: now)
            if project.budgetAlertKey != key {
                project.budgetAlertKey = key
                project.budgetAlertLevel = 0
                changed = true
            }
            if status.level > project.budgetAlertLevel {
                project.budgetAlertLevel = status.level
                changed = true
                notify(Self.title(for: project, level: status.level), Self.body(for: project, status: status))
            } else if status.level < project.budgetAlertLevel {
                // Limit se zvýšil nebo se záznamy smazaly – upozornění může zase přijít.
                project.budgetAlertLevel = status.level
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Vrací `true`, pokud se změnil uložený stav upozornění.
    private func checkTarget(of project: Project, now: Date) -> Bool {
        guard let status = project.targetStatus(now: now, rounding: rounding()) else { return false }
        var changed = false
        let key = BudgetStatus.periodKey(.monthly, now: now)
        if project.targetAlertKey != key {
            project.targetAlertKey = key
            project.targetAlertLevel = 0
            changed = true
        }
        let level = status.position.level
        if level > project.targetAlertLevel {
            project.targetAlertLevel = level
            changed = true
            notify(Self.targetTitle(for: project, position: status.position), Self.targetBody(for: project, status: status))
        } else if level < project.targetAlertLevel {
            project.targetAlertLevel = level
            changed = true
        }
        return changed
    }

    static func targetTitle(for project: Project, position: TargetStatus.Position) -> String {
        position == .over ? "Měsíční cíl překročen: \(project.name)" : "Měsíční cíl dosažen: \(project.name)"
    }

    static func targetBody(for project: Project, status: TargetStatus) -> String {
        "Fakturace tento měsíc \(CzFormat.money(status.amount, currency: project.currency)) z cíle \(CzFormat.money(status.target, currency: project.currency))."
    }

    static func title(for project: Project, level: Int) -> String {
        level >= BudgetStatus.exceededLevel
            ? "Překročen limit: \(project.name)"
            : "Blíží se limit: \(project.name)"
    }

    static func body(for project: Project, status: BudgetStatus) -> String {
        let percent = Int((status.fraction * 100).rounded(.down))
        let scope = project.budgetPeriodValue == .monthly ? " tento měsíc" : ""
        return "Vyčerpáno\(scope) \(percent) % (\(CzFormat.hours(seconds: status.usedSeconds)) z \(CzFormat.hours(seconds: status.budgetSeconds)))."
    }
}
