import SwiftData
import XCTest
@testable import Memento

@MainActor
final class TimerControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var time = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: Project.self, TimeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeController() -> TimerController {
        TimerController(context: container.mainContext, clock: { [unowned self] in self.time })
    }

    private func makeProject(_ name: String) -> Project {
        let project = Project(name: name, hourlyRate: 1000)
        container.mainContext.insert(project)
        return project
    }

    func testStartAndStop() throws {
        let controller = makeController()
        let project = makeProject("A")
        let entry = try controller.start(project)
        XCTAssertTrue(controller.runningEntry === entry)
        XCTAssertNil(entry.end)

        time.addTimeInterval(90)
        try controller.stop()
        XCTAssertNil(controller.runningEntry)
        XCTAssertEqual(entry.duration, 90)
    }

    func testStartingSecondTimerStopsFirst() throws {
        let controller = makeController()
        let a = makeProject("A"), b = makeProject("B")
        let first = try controller.start(a)
        time.addTimeInterval(600)
        let second = try controller.start(b)

        XCTAssertEqual(first.end, second.start)
        XCTAssertNil(second.end)
        XCTAssertTrue(controller.runningEntry === second)
        let open = try container.mainContext.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.end == nil }))
        XCTAssertEqual(open.count, 1)
    }

    func testRunningTimerSurvivesRestart() throws {
        let project = makeProject("A")
        let entry = try makeController().start(project)
        let afterRestart = makeController()
        XCTAssertTrue(afterRestart.runningEntry === entry)
        time.addTimeInterval(120)
        afterRestart.refresh()
        XCTAssertEqual(afterRestart.elapsed, 120)
    }

    func testSelectableProjectsOrderedByRecentUseAndSkipArchived() throws {
        let controller = makeController()
        let a = makeProject("A"), b = makeProject("B"), c = makeProject("C"), d = makeProject("D")
        for project in [a, b, a, c] {
            try controller.start(project)
            time.addTimeInterval(60)
        }
        try controller.stop()
        c.isArchived = true
        XCTAssertEqual(controller.selectableProjects().map(\.name), ["A", "B", "D"])
        XCTAssertFalse(controller.selectableProjects().contains { $0 === c })
        _ = d
    }

    func testResumeLastCopiesProjectAndNote() throws {
        let controller = makeController()
        let a = makeProject("A"), b = makeProject("B")
        XCTAssertNil(try controller.resumeLast())

        let first = try controller.start(a, note: "• starší")
        time.addTimeInterval(60)
        let second = try controller.start(b, note: "• poslední")
        time.addTimeInterval(60)
        try controller.stop()
        time.addTimeInterval(60)

        let resumed = try XCTUnwrap(try controller.resumeLast())
        XCTAssertTrue(resumed.project === b)
        XCTAssertEqual(resumed.note, "• poslední")
        XCTAssertTrue(controller.runningEntry === resumed)
        _ = (first, second)
    }

    func testResumeLastSkipsArchivedProject() throws {
        let controller = makeController()
        let a = makeProject("A"), b = makeProject("B")
        try controller.start(a, note: "• A")
        time.addTimeInterval(60)
        try controller.start(b, note: "• B")
        time.addTimeInterval(60)
        try controller.stop()
        b.isArchived = true

        let resumed = try XCTUnwrap(try controller.resumeLast())
        XCTAssertTrue(resumed.project === a)
        XCTAssertEqual(resumed.note, "• A")
    }
}
