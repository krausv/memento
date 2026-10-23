import SwiftData
import XCTest
@testable import Memento

@MainActor
final class BackupTests: XCTestCase {
    private var defaults: UserDefaults!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "BackupTests-\(UUID())")
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, TimeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func seed(_ context: ModelContext) throws -> (Project, TimeEntry) {
        let project = Project(name: "Alfa", client: "Klient", hourlyRate: Decimal(string: "1234.56")!)
        context.insert(project)
        let entry = TimeEntry(project: project, start: date, end: date.addingTimeInterval(3600), note: "• práce")
        context.insert(entry)
        try context.save()
        defaults.set("700", forKey: SettingsKey.defaultRate)
        defaults.set(15, forKey: SettingsKey.rounding)
        return (project, entry)
    }

    func testRoundTripPreservesDataIncludingDecimalRate() throws {
        let source = try makeContext()
        let (project, entry) = try seed(source)
        let data = try BackupService.encode(try BackupService.makeBackup(context: source, now: date, defaults: defaults))

        let target = try makeContext()
        let backup = try BackupService.decode(data)
        let other = UserDefaults(suiteName: "BackupTests-other-\(UUID())")!
        let summary = try BackupService.restore(backup, mode: .replace, context: target, defaults: other)

        XCTAssertEqual(summary.addedProjects, 1)
        XCTAssertEqual(summary.addedEntries, 1)
        let projects = try target.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.first?.id, project.id)
        XCTAssertEqual(projects.first?.hourlyRate, Decimal(string: "1234.56"))
        let entries = try target.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.first?.id, entry.id)
        XCTAssertEqual(entries.first?.note, "• práce")
        XCTAssertEqual(entries.first?.project?.id, project.id)
        XCTAssertEqual(other.string(forKey: SettingsKey.defaultRate), "700")
        XCTAssertEqual(other.integer(forKey: SettingsKey.rounding), 15)
    }

    func testMergeSkipsExistingAndDoesNotTouchSettings() throws {
        let context = try makeContext()
        _ = try seed(context)
        let backup = try BackupService.makeBackup(context: context, now: date, defaults: defaults)
        defaults.set("1", forKey: SettingsKey.defaultRate)

        let summary = try BackupService.restore(backup, mode: .merge, context: context, defaults: defaults)
        XCTAssertEqual(summary, RestoreSummary(addedProjects: 0, addedEntries: 0, skippedEntries: 1))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimeEntry>()).count, 1)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.defaultRate), "1")
    }

    func testMergeMapsProjectWithSameNameAndKeepsOnlyOneRunningEntry() throws {
        let context = try makeContext()
        let local = Project(name: "alfa", hourlyRate: 100)
        context.insert(local)
        context.insert(TimeEntry(project: local, start: date))
        try context.save()

        let foreignProject = UUID()
        let backup = Backup(
            version: 1, exportedAt: date,
            projects: [.init(id: foreignProject, name: "Alfa", client: nil, hourlyRate: "5", currency: "CZK",
                             isArchived: false, createdAt: date)],
            entries: [
                .init(id: UUID(), projectID: foreignProject, start: date.addingTimeInterval(-7200), end: date.addingTimeInterval(-3600), note: nil),
                .init(id: UUID(), projectID: foreignProject, start: date.addingTimeInterval(10), end: nil, note: nil),
            ],
            settings: .init(defaultRate: "0", roundingMinutes: 0, supplierName: nil, supplierIco: nil)
        )
        let summary = try BackupService.restore(backup, mode: .merge, context: context, defaults: defaults)

        XCTAssertEqual(summary, RestoreSummary(addedProjects: 0, addedEntries: 1, skippedEntries: 1))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).count, 1)
        let open = try context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.end == nil }))
        XCTAssertEqual(open.count, 1)
    }

    func testReplaceRemovesExistingData() throws {
        let context = try makeContext()
        _ = try seed(context)
        let empty = Backup(version: 1, exportedAt: date, projects: [], entries: [],
                           settings: .init(defaultRate: "0", roundingMinutes: 0, supplierName: nil, supplierIco: nil))
        try BackupService.restore(empty, mode: .replace, context: context, defaults: defaults)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TimeEntry>()).isEmpty)
    }

    func testRejectsGarbageAndUnknownVersion() {
        XCTAssertThrowsError(try BackupService.decode(Data("nic".utf8))) {
            XCTAssertEqual($0 as? BackupError, .unreadable)
        }
        XCTAssertThrowsError(try BackupService.decode(Data(#"{"version": 99}"#.utf8))) {
            XCTAssertEqual($0 as? BackupError, .unsupportedVersion(99))
        }
    }

    func testValidationRejectsInconsistentData() {
        let project = Backup.ProjectData(id: UUID(), name: "A", client: nil, hourlyRate: "1", currency: "CZK",
                                         isArchived: false, createdAt: date)
        func backup(_ entries: [Backup.EntryData]) -> Backup {
            Backup(version: 1, exportedAt: date, projects: [project], entries: entries,
                   settings: .init(defaultRate: "0", roundingMinutes: 0, supplierName: nil, supplierIco: nil))
        }
        let orphan = Backup.EntryData(id: UUID(), projectID: UUID(), start: date, end: date.addingTimeInterval(60), note: nil)
        XCTAssertThrowsError(try BackupService.validate(backup([orphan])))

        let backwards = Backup.EntryData(id: UUID(), projectID: project.id, start: date, end: date, note: nil)
        XCTAssertThrowsError(try BackupService.validate(backup([backwards])))

        let running1 = Backup.EntryData(id: UUID(), projectID: project.id, start: date, end: nil, note: nil)
        let running2 = Backup.EntryData(id: UUID(), projectID: project.id, start: date.addingTimeInterval(5), end: nil, note: nil)
        XCTAssertThrowsError(try BackupService.validate(backup([running1, running2])))
        XCTAssertNoThrow(try BackupService.validate(backup([running1])))
    }
}
