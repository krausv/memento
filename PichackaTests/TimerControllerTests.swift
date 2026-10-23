import SwiftData
import XCTest
@testable import Pichacka

@MainActor
final class TimerControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var time = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: Project.self, ProjectTask.self, TimeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeController() -> TimerController {
        TimerController(context: container.mainContext, clock: { [unowned self] in self.time })
    }

    private func makeTask(_ name: String) -> ProjectTask {
        let project = Project(name: "P \(name)", hourlyRate: 1000)
        let task = ProjectTask(name: name, project: project)
        container.mainContext.insert(project)
        container.mainContext.insert(task)
        return task
    }

    func testStartAndStop() throws {
        let controller = makeController()
        let task = makeTask("A")
        let entry = try controller.start(task)
        XCTAssertTrue(controller.runningEntry === entry)
        XCTAssertNil(entry.end)

        time.addTimeInterval(90)
        try controller.stop()
        XCTAssertNil(controller.runningEntry)
        XCTAssertEqual(entry.duration, 90)
    }

    func testStartingSecondTimerStopsFirst() throws {
        let controller = makeController()
        let a = makeTask("A"), b = makeTask("B")
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
        let task = makeTask("A")
        let entry = try makeController().start(task)
        let afterRestart = makeController()
        XCTAssertTrue(afterRestart.runningEntry === entry)
        time.addTimeInterval(120)
        afterRestart.refresh()
        XCTAssertEqual(afterRestart.elapsed, 120)
    }

    func testRecentTasksAreUniqueAndSkipArchived() throws {
        let controller = makeController()
        let a = makeTask("A"), b = makeTask("B"), c = makeTask("C")
        for task in [a, b, a, c] {
            try controller.start(task)
            time.addTimeInterval(60)
        }
        try controller.stop()
        c.isArchived = true
        XCTAssertEqual(controller.recentTasks().map(\.name), ["A", "B"])
    }
}
