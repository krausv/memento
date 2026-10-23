import SwiftData
import XCTest
@testable import Memento

final class AutoBackupPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func settings(_ frequency: AutoBackupFrequency = .weekly, enabled: Bool = true, folder: String? = "/tmp") -> AutoBackupSettings {
        AutoBackupSettings(enabled: enabled, folderPath: folder, frequency: frequency, keepCount: 10)
    }

    func testNotDueWhenDisabledOrWithoutFolder() {
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, lastBackup: nil, settings: settings(enabled: false)))
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, lastBackup: nil, settings: settings(folder: nil)))
    }

    func testDueWithoutPreviousBackup() {
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, lastBackup: nil, settings: settings()))
    }

    func testDailyAndWeeklyIntervals() {
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, lastBackup: dayAgo, settings: settings(.daily)))
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, lastBackup: now.addingTimeInterval(-12 * 3600), settings: settings(.daily)))
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, lastBackup: dayAgo, settings: settings(.weekly)))
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, lastBackup: now.addingTimeInterval(-7 * 24 * 3600), settings: settings(.weekly)))
    }

    func testPruneKeepsNewestAndNeverTouchesForeignFiles() {
        let names = [
            "memento-auto-2026-10-01-0900.json", "memento-auto-2026-10-03-0900.json",
            "memento-auto-2026-10-02-0900.json", "memento-auto-2026-10-04-0900.json",
            "moje-vlastni-zaloha.json", "memento-auto-final.json", "memento-zaloha-2026-10-01.json", "poznamky.txt",
        ]
        XCTAssertEqual(AutoBackupPolicy.namesToPrune(names, keep: 2),
                       ["memento-auto-2026-10-02-0900.json", "memento-auto-2026-10-01-0900.json"])
        XCTAssertTrue(AutoBackupPolicy.namesToPrune(names, keep: 10).isEmpty)
        XCTAssertEqual(AutoBackupPolicy.namesToPrune(names, keep: 0).count, 3, "vždy zůstane aspoň jedna záloha")
    }

    func testFileNameMatchesOwnPattern() {
        XCTAssertTrue(AutoBackupPolicy.isAutoBackupName(AutoBackupPolicy.fileName(for: now)))
    }
}

@MainActor
final class AutoBackupServiceTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("memento-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "AutoBackupTests-\(UUID())")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, TimeEntry.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Project(name: "A", hourlyRate: 100))
        try context.save()
        return context
    }

    func testWritesReadableBackupAndPrunesOld() throws {
        let context = try makeContext()
        var settings = AutoBackupSettings(enabled: true, folderPath: folder.path, frequency: .daily, keepCount: 2)
        let foreign = folder.appendingPathComponent("moje.json")
        try Data("x".utf8).write(to: foreign)

        var last: URL?
        for day in 0..<4 {
            last = try AutoBackupService.run(
                context: context, settings: settings,
                now: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400), defaults: defaults)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names.filter(AutoBackupPolicy.isAutoBackupName).count, 2)
        XCTAssertTrue(names.contains("moje.json"))

        let backup = try BackupService.decode(Data(contentsOf: try XCTUnwrap(last)))
        XCTAssertEqual(backup.projects.map(\.name), ["A"])
        settings.keepCount = 1
    }

    func testFailsClearlyWhenFolderMissingOrUnset() throws {
        let context = try makeContext()
        XCTAssertThrowsError(try AutoBackupService.run(context: context, settings: AutoBackupSettings(), defaults: defaults)) {
            XCTAssertEqual($0 as? AutoBackupError, .noFolder)
        }
        let missing = folder.appendingPathComponent("neexistuje").path
        XCTAssertThrowsError(try AutoBackupService.run(
            context: context, settings: AutoBackupSettings(enabled: true, folderPath: missing), defaults: defaults)
        ) {
            XCTAssertEqual($0 as? AutoBackupError, .folderUnavailable(missing))
        }
    }

    func testSchedulerRunsWhenDueRecordsAndReportsFailureOnce() throws {
        let context = try makeContext()
        var settings = AutoBackupSettings(enabled: true, folderPath: folder.path, frequency: .daily, keepCount: 5)
        AppSettings.setAutoBackup(settings, defaults)
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var failures: [String] = []
        let scheduler = AutoBackupScheduler(context: context, clock: { time }, defaults: defaults) { failures.append($0) }

        scheduler.checkNow()
        XCTAssertEqual(AppSettings.lastAutoBackup(defaults), time)
        scheduler.checkNow() // ještě není na řadě
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)

        settings.folderPath = folder.appendingPathComponent("pryc").path
        AppSettings.setAutoBackup(settings, defaults)
        time.addTimeInterval(2 * 86_400)
        scheduler.checkNow()
        scheduler.checkNow()
        XCTAssertEqual(failures.count, 1)
        XCTAssertNotNil(AppSettings.lastAutoBackupError(defaults))
        XCTAssertNotNil(AppSettings.lastAutoBackup(defaults), "čas poslední úspěšné zálohy zůstane")
    }
}
