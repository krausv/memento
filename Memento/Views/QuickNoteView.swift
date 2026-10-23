import SwiftData
import SwiftUI

/// Rychlé okno pro poznámku k právě běžícímu záznamu (levé kliknutí na ikonu při běžícím časovači).
struct QuickNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer

    let entry: TimeEntry
    let close: () -> Void

    @State private var note: String

    init(entry: TimeEntry, close: @escaping () -> Void) {
        self.entry = entry
        self.close = close
        _note = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.project?.name ?? "Projekt").font(.headline)
                Spacer()
                Text(timer.elapsedText).monospacedDigit().foregroundStyle(.secondary)
            }
            BulletTextEditor(text: $note, autofocus: true)
                .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Zrušit", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Uložit", action: save).keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func save() {
        entry.note = BulletText.clean(note)
        try? context.save()
        close()
    }
}
