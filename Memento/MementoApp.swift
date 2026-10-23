import SwiftData
import SwiftUI

@main
struct MementoApp: App {
    private let container: ModelContainer
    private let timer: TimerController
    private let statusItem: StatusItemController?

    init() {
        // Testy běží v hostitelské aplikaci – nesmí sahat na uživatelská data ani na lištu.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Project.self, TimeEntry.self, Tag.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: isTesting)
            )
        } catch {
            fatalError("Nepodařilo se otevřít úložiště: \(error)")
        }
        let timer = MainActor.assumeIsolated { TimerController(context: container.mainContext) }
        self.container = container
        self.timer = timer
        statusItem = isTesting ? nil : MainActor.assumeIsolated { StatusItemController(timer: timer, container: container) }
    }

    // Ikonu v liště i okna řídí StatusItemController; SwiftUI scéna je jen formální.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
