import SwiftData
import SwiftUI

/// Rychlé okno pro poznámku k právě běžícímu záznamu (levé kliknutí na ikonu při běžícím časovači).
struct QuickNoteView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer

    let entry: TimeEntry
    let close: () -> Void

    @State private var note: String
    @State private var tags: [Tag]
    @State private var start: Date
    @State private var errorMessage: String?

    init(entry: TimeEntry, close: @escaping () -> Void) {
        self.entry = entry
        self.close = close
        _start = State(initialValue: entry.start)
        _note = State(initialValue: entry.note ?? "")
        _tags = State(initialValue: entry.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entry.project?.name ?? "Projekt").font(.headline)
                Spacer()
                Text(timer.totalElapsedText)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
            DatePicker("Začátek", selection: $start, in: ...Date())
                .environment(\.locale, CzFormat.locale)
                .environment(\.calendar, .prague)
                .environment(\.timeZone, Calendar.prague.timeZone)
            BulletTextEditor(text: $note, autofocus: true)
                .frame(minHeight: 200)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            TagPicker(selected: $tags)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
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
        // Záznam mezitím mohl zmizet z databáze (smazání, obnova zálohy); sahat na něj by shodilo aplikaci.
        guard !entry.isDeleted, entry.modelContext != nil, timer.runningEntry?.id == entry.id else {
            errorMessage = "Záznam už neexistuje nebo neběží. Zavři okno a zkus to znovu."
            return
        }
        do {
            try timer.moveStart(to: RunningStart.rounded(start, original: entry.start))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        entry.note = BulletText.clean(note)
        entry.tags = tags
        try? context.save()
        close()
    }
}
