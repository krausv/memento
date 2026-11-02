import SwiftData
import SwiftUI
import UserNotifications

@main
struct MementoApp: App {
    private let container: ModelContainer
    private let timer: TimerController
    private let updates: UpdateStore
    private let statusItem: StatusItemController?
    private let budgetMonitor: BudgetMonitor?
    private let reminders: ReminderScheduler?
    private let pomodoro: PomodoroScheduler?
    private let pomodoroPanel: PomodoroPanelController?
    private let autoBackup: AutoBackupScheduler?

    init() {
        // Testy běží v hostitelské aplikaci – nesmí sahat na uživatelská data ani na lištu.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let container: ModelContainer
        do {
            let configuration = isTesting
                ? ModelConfiguration(isStoredInMemoryOnly: true)
                : ModelConfiguration(url: try StoreLocation.prepare())
            container = try ModelContainer(for: Project.self, TimeEntry.self, Tag.self, configurations: configuration)
        } catch {
            fatalError("Nepodařilo se otevřít úložiště: \(error)")
        }
        let timer = MainActor.assumeIsolated { TimerController(context: container.mainContext) }
        self.container = container
        self.timer = timer
        let updates = MainActor.assumeIsolated { UpdateStore() }
        self.updates = updates
        let statusItem = isTesting ? nil : MainActor.assumeIsolated {
            StatusItemController(timer: timer, container: container, updates: updates)
        }
        self.statusItem = statusItem
        if isTesting {
            budgetMonitor = nil
            reminders = nil
            pomodoro = nil
            pomodoroPanel = nil
            autoBackup = nil
        } else {
            Notifications.configure()
            MainActor.assumeIsolated {
                updates.onInstallFailure = { Notifications.post(title: "Aktualizace se nepovedla", body: $0) }
                updates.beforeInstall = { try AutoBackupService.runBeforeUpdate(context: container.mainContext) }
                updates.start()
            }
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
                    case .missingNote: Notifications.post(title: title, body: body, category: .missingNote)
                    }
                }
            }
            let pomodoroScheduler = MainActor.assumeIsolated {
                PomodoroScheduler(timer: timer) { notice, title, body in
                    switch notice {
                    case .breakDue: Notifications.post(title: title, body: body, category: .pomodoroBreakDue)
                    case .workDue: Notifications.post(title: title, body: body, category: .pomodoroWorkDue)
                    case .breakStarted: Notifications.post(title: title, body: body, category: .pomodoroBreakStarted)
                    case .workStarted: Notifications.post(title: title, body: body)
                    }
                }
            }
            MainActor.assumeIsolated {
                scheduler.start()
                pomodoroScheduler.start()
                Notifications.actionHandler = { [weak timer, weak statusItem, weak pomodoroScheduler] action, category in
                    switch action {
                    case Notifications.Action.startLast: _ = try? timer?.startDefault()
                    case Notifications.Action.stop: try? timer?.stop()
                    case Notifications.Action.addNote: statusItem?.showNoteForRunningEntry()
                    case Notifications.Action.pomodoroStart: pomodoroScheduler?.perform(.startNext)
                    case Notifications.Action.pomodoroSnooze: pomodoroScheduler?.perform(.snooze)
                    case Notifications.Action.pomodoroSkipBreak: pomodoroScheduler?.perform(.skipBreak)
                    case UNNotificationDefaultActionIdentifier:
                        // Klik na samotné oznámení o chybějící poznámce rovnou otevře její zadání.
                        if category == Notifications.Category.missingNote.rawValue { statusItem?.showNoteForRunningEntry() }
                    default: break
                    }
                }
            }
            reminders = scheduler
            pomodoro = pomodoroScheduler
            pomodoroPanel = MainActor.assumeIsolated { PomodoroPanelController(scheduler: pomodoroScheduler) }

            let backups = MainActor.assumeIsolated {
                AutoBackupScheduler(context: container.mainContext) {
                    Notifications.post(title: "Automatická záloha selhala", body: $0)
                }
            }
            MainActor.assumeIsolated {
                backups.start()
                // Záloha po každé změně měření (start, stop, posun začátku), ne jen jednou za den.
                let previous = timer.onChange
                timer.onChange = { [weak backups] in
                    previous?()
                    backups?.checkAfterChange()
                }
            }
            autoBackup = backups
        }
    }

    // Ikonu v liště i okna řídí StatusItemController; SwiftUI scéna je jen formální.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
