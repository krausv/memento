import Foundation
import SwiftData

// Třída se jmenuje ProjectTask, aby nestínila Swift.Task ze Swift Concurrency.

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var client: String?
    var hourlyRate: Decimal = 0
    var currency: String = "CZK"
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    var tasks: [ProjectTask] = []

    init(name: String, client: String? = nil, hourlyRate: Decimal, currency: String = "CZK") {
        self.name = name
        self.client = client
        self.hourlyRate = hourlyRate
        self.currency = currency
    }
}

@Model
final class ProjectTask {
    var id: UUID = UUID()
    var name: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.task)
    var entries: [TimeEntry] = []

    init(name: String, project: Project) {
        self.name = name
        self.project = project
    }

    /// Úkol je nabízen k výběru jen když není archivovaný on ani jeho projekt.
    var isSelectable: Bool { !isArchived && !(project?.isArchived ?? false) }

    var displayName: String { "\(project?.name ?? "?") › \(name)" }
}

@Model
final class TimeEntry {
    var id: UUID = UUID()
    var start: Date = Date()
    /// `nil` = právě běží.
    var end: Date?
    var note: String?
    var task: ProjectTask?

    init(task: ProjectTask, start: Date, end: Date? = nil, note: String? = nil) {
        self.task = task
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
