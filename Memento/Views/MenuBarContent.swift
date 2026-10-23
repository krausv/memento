import SwiftData
import SwiftUI

struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer

    var body: some View {
        if timer.runningEntry != nil {
            // Label by v liště ukázal jen ikonu; text vedle ikony zajistí až HStack.
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(timer.elapsedText).monospacedDigit()
            }
        } else {
            Image(systemName: "timer")
        }
    }
}

struct MenuBarContent: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.openWindow) private var openWindow
    // Dotazy drží menu aktuální při změně dat; samotný výběr dělá selectableProjects.
    @Query private var projects: [Project]
    @Query private var entries: [TimeEntry]

    var body: some View {
        if let running = timer.runningEntry {
            Text("\(running.project?.name ?? "Projekt") · \(timer.elapsedText)")
            Button("Stop") { try? timer.stop() }
        } else {
            Text("Časovač neběží")
        }

        let choices = timer.selectableProjects()
        Divider()
        if choices.isEmpty {
            Text("Nejdřív vytvoř projekt v okně Memento")
        } else {
            Text("Spustit projekt")
            ForEach(choices, id: \.id) { project in
                Button(project.name) { _ = try? timer.start(project) }
            }
        }

        Divider()
        Button("Otevřít Memento") {
            openWindow(id: MainWindow.id)
            NSApp.activate()
        }
        Button("Ukončit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
