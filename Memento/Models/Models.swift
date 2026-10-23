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
