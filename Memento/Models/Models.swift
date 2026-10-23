import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var client: String?
    var hourlyRate: Decimal = 0
    var currency: String = "CZK"
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// Rozpočet v hodinách; `nil` = bez limitu. Období viz `BudgetPeriod`.
    var budgetHours: Decimal?
    var budgetPeriod: String = BudgetPeriod.total.rawValue
    /// Poslední oznámená úroveň (0 / 80 / 100) v období `budgetAlertKey`, aby se upozornění neopakovala.
    var budgetAlertLevel: Int = 0
    var budgetAlertKey: String?
    /// Měsíční cíl fakturace v měně projektu; `nil` = bez cíle.
    var targetAmount: Decimal?
    /// Poslední oznámená poloha vůči cíli (`TargetStatus.Position.level`) v měsíci `targetAlertKey`.
    var targetAlertLevel: Int = 0
    var targetAlertKey: String?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project)
    var entries: [TimeEntry] = []

    init(name: String, client: String? = nil, hourlyRate: Decimal, currency: String = "CZK") {
        self.name = name
        self.client = client
        self.hourlyRate = hourlyRate
        self.currency = currency
    }
}

@Model
final class TimeEntry {
    var id: UUID = UUID()
    var start: Date = Date()
    /// `nil` = právě běží.
    var end: Date?
    /// Volný popis práce; nahrazuje úkoly.
    var note: String?
    var project: Project?
    /// Štítky napříč projekty; vztah M:N, smazání štítku ho jen odebere ze záznamů.
    var tags: [Tag] = []

    init(project: Project, start: Date, end: Date? = nil, note: String? = nil) {
        self.project = project
        self.start = start
        self.end = end
        self.note = note
    }

    var isRunning: Bool { end == nil }

    func duration(at now: Date = Date()) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    var duration: TimeInterval { duration() }
}

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    /// Klíč do `TagColor`.
    var colorName: String = TagColor.blue.rawValue
    var createdAt: Date = Date()

    @Relationship(inverse: \TimeEntry.tags)
    var entries: [TimeEntry] = []

    init(name: String, color: TagColor = .blue) {
        self.name = name
        self.colorName = color.rawValue
    }

    var color: TagColor { TagColor(rawValue: colorName) ?? .blue }
}
