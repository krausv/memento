import SwiftUI

struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer

    var body: some View {
        if timer.runningEntry != nil {
            Label(timer.elapsedText, systemImage: "timer")
        } else {
            Image(systemName: "timer")
        }
    }
}

struct MenuBarContent: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let running = timer.runningEntry {
            Text("\(running.task?.displayName ?? "Úkol") · \(timer.elapsedText)")
            Button("Stop") { try? timer.stop() }
        } else {
            Text("Časovač neběží")
        }

        let recent = timer.recentTasks(limit: 5)
        if !recent.isEmpty {
            Divider()
            Text("Poslední úkoly")
            ForEach(recent) { task in
                Button(task.displayName) { try? timer.start(task) }
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
