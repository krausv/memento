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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entry.project?.name ?? "Projekt").font(.headline)
                Spacer()
                Text(timer.elapsedText)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
            BulletTextEditor(text: $note, autofocus: true)
                .frame(minHeight: 200)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Zrušit", role: .cancel, action: close)
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("Uložit", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(20)
        .padding(.top, 18) // místo pro průhledný titulek okna
        .frame(width: 480)
        .containerBackground(.regularMaterial, for: .window)
    }

    private func save() {
        entry.note = BulletText.clean(note)
        try? context.save()
        close()
    }
}
