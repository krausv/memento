import SwiftData
import SwiftUI

@main
struct MementoApp: App {
    private let container: ModelContainer
    private let timer: TimerController
    private let statusItem: StatusItemController?
    private let budgetMonitor: BudgetMonitor?
    private let reminders: ReminderScheduler?
    private let autoBackup: AutoBackupScheduler?

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
        if isTesting {
            budgetMonitor = nil
            reminders = nil
            autoBackup = nil
        } else {
            Notifications.configure()
            let monitor = MainActor.assumeIsolated {
                BudgetMonitor(context: container.mainContext) { Notifications.post(title: $0, body: $1) }
            }
            MainActor.assumeIsolated {
                timer.onChange = { [weak monitor] in monitor?.check() }
                monitor.start()
            }
            budgetMonitor = monitor

            let scheduler = MainActor.assumeIsolated {
                ReminderScheduler(timer: timer) { reminder, title, body in
                    switch reminder {
                    case .notRunning: Notifications.post(title: title, body: body, category: .notRunning)
                    case .longRunning: Notifications.post(title: title, body: body, category: .longRunning)
                    }
                }
            }
            MainActor.assumeIsolated {
                scheduler.start()
                Notifications.actionHandler = { [weak timer] action in
                    switch action {
                    case Notifications.Action.startLast: _ = try? timer?.startDefault()
                    case Notifications.Action.stop: try? timer?.stop()
                    default: break
                    }
                }
            }
            reminders = scheduler

            let backups = MainActor.assumeIsolated {
                AutoBackupScheduler(context: container.mainContext) {
                    Notifications.post(title: "Automatická záloha selhala", body: $0)
                }
            }
            MainActor.assumeIsolated { backups.start() }
            autoBackup = backups
        }
        statusItem = isTesting ? nil : MainActor.assumeIsolated { StatusItemController(timer: timer, container: container) }
    }

    // Ikonu v liště i okna řídí StatusItemController; SwiftUI scéna je jen formální.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
