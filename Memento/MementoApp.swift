import SwiftData
import SwiftUI

@main
struct MementoApp: App {
    private let container: ModelContainer
    @State private var timer: TimerController

    init() {
        // Testy běží v hostitelské aplikaci – nesmí sahat na uživatelská data.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            container = try ModelContainer(
                for: Project.self, ProjectTask.self, TimeEntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: isTesting)
            )
        } catch {
            fatalError("Nepodařilo se otevřít úložiště: \(error)")
        }
        _timer = State(initialValue: TimerController(context: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(timer)
                .modelContainer(container)
        } label: {
            MenuBarLabel()
                .environment(timer)
        }

        Window("Memento", id: MainWindow.id) {
            MainWindow()
                .environment(timer)
                .modelContainer(container)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}
