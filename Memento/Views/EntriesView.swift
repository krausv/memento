import SwiftData
import SwiftUI

struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start, order: .reverse) private var entries: [TimeEntry]

    @State private var showingNew = false
    @State private var editing: TimeEntry?

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
    }

    private func row(_ entry: TimeEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.task?.displayName ?? "—")
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
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
        .onTapGesture(count: 2) { if !entry.isRunning { editing = entry } }
        .contextMenu {
            if !entry.isRunning { Button("Upravit") { editing = entry } }
            Button("Smazat", role: .destructive) { delete(entry) }
        }
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
    @Query(sort: \ProjectTask.name) private var tasks: [ProjectTask]
    @Query private var entries: [TimeEntry]

    let entry: TimeEntry?
    @State private var task: ProjectTask?
    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(entry: TimeEntry?) {
        self.entry = entry
        let now = Date()
        _task = State(initialValue: entry?.task)
        _start = State(initialValue: entry?.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: entry?.end ?? now)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var choices: [ProjectTask] {
        tasks.filter { $0.isSelectable || $0 === entry?.task }
    }

    var body: some View {
        Form {
            Picker("Úkol", selection: $task) {
                Text("Vyber úkol").tag(ProjectTask?.none)
                ForEach(choices) { Text($0.displayName).tag(Optional($0)) }
            }
            DatePicker("Od", selection: $start)
            DatePicker("Do", selection: $end)
            TextField("Poznámka", text: $note)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .environment(\.locale, CzFormat.locale)
        .environment(\.calendar, .prague)
        .environment(\.timeZone, Calendar.prague.timeZone)
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle(entry == nil ? "Nový záznam" : "Upravit záznam")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Uložit", action: save).disabled(task == nil) }
        }
    }

    private func save() {
        guard let task else { return }
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
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.task = task
            entry.start = start
            entry.end = end
            entry.note = trimmedNote.isEmpty ? nil : trimmedNote
        } else {
            context.insert(TimeEntry(task: task, start: start, end: end, note: trimmedNote.isEmpty ? nil : trimmedNote))
        }
        try? context.save()
        dismiss()
    }
}
