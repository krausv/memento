import SwiftData
import SwiftUI

struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start, order: .reverse) private var entries: [TimeEntry]

    @State private var showingNew = false
    @State private var editing: TimeEntry?
    @State private var editingNote: TimeEntry?

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: entries) { Calendar.prague.startOfDay(for: $0.start) }
            .map { (day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Žádné záznamy", systemImage: "clock",
                                       description: Text("Spusť časovač nebo přidej záznam ručně."))
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in row(entry) }
                } header: {
                    HStack {
                        Text(CzFormat.dayHeading(group.day))
                        Spacer()
                        Text(CzFormat.hours(seconds: Int(group.entries.reduce(0) { $0 + $1.duration(at: timer.now) })))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Záznamy")
        .toolbar {
            ToolbarItem {
                Button("Přidat záznam", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { EntryForm(entry: nil) }
        .sheet(item: $editing) { EntryForm(entry: $0) }
        .sheet(item: $editingNote) { NoteForm(entry: $0) }
    }

    private func row(_ entry: TimeEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.project?.name ?? "—")
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
            if let end = entry.end {
                Text(CzFormat.timeRange(start: entry.start, end: end)).foregroundStyle(.secondary)
                Text(CzFormat.hours(seconds: Int(entry.duration))).monospacedDigit().frame(width: 80, alignment: .trailing)
            } else {
                Text("\(CzFormat.time(entry.start))– běží").foregroundStyle(.tint)
                Text(timer.elapsedText).monospacedDigit().frame(width: 80, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(entry) }
        .contextMenu {
            Button(entry.isRunning ? "Upravit poznámku" : "Upravit") { edit(entry) }
            Button("Smazat", role: .destructive) { delete(entry) }
        }
    }

    private func edit(_ entry: TimeEntry) {
        if entry.isRunning { editingNote = entry } else { editing = entry }
    }

    private func delete(_ entry: TimeEntry) {
        context.delete(entry)
        try? context.save()
        timer.refresh()
    }
}

struct EntryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var entries: [TimeEntry]

    let entry: TimeEntry?
    @State private var project: Project?
    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(entry: TimeEntry?) {
        self.entry = entry
        let now = Date()
        _project = State(initialValue: entry?.project)
        _start = State(initialValue: entry?.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: entry?.end ?? now)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var choices: [Project] {
        projects.filter { !$0.isArchived || $0 === entry?.project }
    }

    var body: some View {
        Form {
            Picker("Projekt", selection: $project) {
                Text("Vyber projekt").tag(Project?.none)
                ForEach(choices) { Text($0.name).tag(Optional($0)) }
            }
            DatePicker("Od", selection: $start)
            DatePicker("Do", selection: $end)
            VStack(alignment: .leading) {
                Text("Poznámka")
                BulletTextEditor(text: $note).frame(minHeight: 120)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .environment(\.locale, CzFormat.locale)
        .environment(\.calendar, .prague)
        .environment(\.timeZone, Calendar.prague.timeZone)
        .formStyle(.grouped)
        .frame(width: 480)
        .navigationTitle(entry == nil ? "Nový záznam" : "Upravit záznam")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Uložit", action: save).disabled(project == nil) }
        }
    }

    private func save() {
        guard let project else { return }
        // Sekundy nemají v UI smysl, ale rozdíl pár vteřin by mohl vyvolat falešné překrytí.
        let start = Date(timeIntervalSinceReferenceDate: (self.start.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        let end = Date(timeIntervalSinceReferenceDate: (self.end.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        do {
            try EntryValidator.validate(
                start: start, end: end, editing: entry?.id,
                existing: entries.map { EntryInterval(id: $0.id, start: $0.start, end: $0.end) }
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let cleanedNote = BulletText.clean(note)
        if let entry {
            entry.project = project
            entry.start = start
            entry.end = end
            entry.note = cleanedNote
        } else {
            context.insert(TimeEntry(project: project, start: start, end: end, note: cleanedNote))
        }
        try? context.save()
        dismiss()
    }
}

/// Úprava poznámky běžícího záznamu (čas měnit nejde, dokud běží).
struct NoteForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry
    @State private var note: String

    init(entry: TimeEntry) {
        self.entry = entry
        _note = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        Form {
            Text(entry.project?.name ?? "").foregroundStyle(.secondary)
            BulletTextEditor(text: $note, autofocus: true).frame(minHeight: 160)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle("Poznámka")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Uložit", action: save) }
        }
    }

    private func save() {
        entry.note = BulletText.clean(note)
        try? context.save()
        dismiss()
    }
}
