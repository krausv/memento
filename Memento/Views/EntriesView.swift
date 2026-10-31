import SwiftData
import SwiftUI

struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var tagFilterID: UUID?
    /// Výchozí je aktuální měsíc; `nil` = všechny měsíce.
    @State private var monthFilter: ReportMonth? = ReportMonth(containing: Date())

    @State private var showingNew = false
    @State private var editing: TimeEntry?
    @State private var editingNote: TimeEntry?

    /// Smazaný štítek by filtr nechal viset a seznam by zůstal prázdný.
    private var activeFilter: Tag? { tags.first { $0.id == tagFilterID } }

    private var entries: [TimeEntry] {
        allEntries.filter { entry in
            (monthFilter?.contains(entry.start) ?? true)
                && (activeFilter.map { filter in entry.tags.contains { $0 === filter } } ?? true)
        }
    }

    /// Měsíce, ve kterých jsou záznamy, a vždy aktuální měsíc; nejnovější první.
    private var availableMonths: [ReportMonth] {
        var months = Set(allEntries.map { ReportMonth(containing: $0.start) })
        months.insert(ReportMonth(containing: Date()))
        if let monthFilter { months.insert(monthFilter) }
        return months.sorted(by: >)
    }

    private func billing(_ entry: TimeEntry) -> BillingEntry? {
        guard let project = entry.project else { return nil }
        return BillingEntry(projectKey: project.id, currency: project.currency, hourlyRate: project.hourlyRate,
                            start: entry.start, end: entry.end)
    }

    private func amountText(_ list: [TimeEntry]) -> String {
        Billing.text(Billing.totals(list.compactMap(billing), now: timer.now, rounding: AppSettings.rounding))
    }

    private var summary: some View {
        HStack(spacing: 16) {
            Text(monthFilter.map(CzFormat.month) ?? "Všechny měsíce").font(.headline)
            Spacer()
            Label(CzFormat.hours(seconds: Int(entries.reduce(0) { $0 + $1.duration(at: timer.now) })), systemImage: "clock")
            Label(amountText(entries), systemImage: "banknote").fontWeight(.semibold)
            Text("\(entries.count) záznamů").foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: entries) { Calendar.prague.startOfDay(for: $0.start) }
            .map { (day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider()
            list
        }
        .navigationTitle("Záznamy")
        .toolbar {
            ToolbarItem {
                Picker("Měsíc", selection: $monthFilter) {
                    Text("Všechny měsíce").tag(ReportMonth?.none)
                    Divider()
                    ForEach(availableMonths, id: \.self) { Text(CzFormat.month($0)).tag(Optional($0)) }
                }
            }
            if !tags.isEmpty {
                ToolbarItem {
                    Picker("Štítek", selection: $tagFilterID) {
                        Text("Všechny štítky").tag(UUID?.none)
                        ForEach(tags) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            ToolbarItem {
                Button("Přidat záznam", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { EntryForm(entry: nil) }
        .sheet(item: $editing) { EntryForm(entry: $0) }
        .sheet(item: $editingNote) { NoteForm(entry: $0) }
    }

    private var list: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in row(entry) }
                } header: {
                    HStack {
                        Text(CzFormat.dayHeading(group.day))
                        Spacer()
                        Text(CzFormat.hours(seconds: Int(group.entries.reduce(0) { $0 + $1.duration(at: timer.now) })))
                            .monospacedDigit()
                        Text(amountText(group.entries)).monospacedDigit().frame(width: 130, alignment: .trailing)
                    }
                }
            }
            if !entries.isEmpty {
                Text("Částky jsou se zaokrouhlením z exportu a v součtech po měsících odpovídají výkazu. U filtrovaných záznamů jde o částku jen za zobrazené.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Žádné záznamy", systemImage: "clock",
                                       description: Text(allEntries.isEmpty
                                           ? "Spusť časovač nebo přidej záznam ručně."
                                           : "Pro zvolený měsíc a štítek nejsou žádné záznamy."))
            }
        }
    }

    private func row(_ entry: TimeEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.project?.name ?? "—")
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                TagChips(tags: entry.tags)
            }
            Spacer()
            if let end = entry.end {
                Text(CzFormat.timeRange(start: entry.start, end: end)).foregroundStyle(.secondary)
                Text(CzFormat.hours(seconds: Int(entry.duration))).monospacedDigit().frame(width: 80, alignment: .trailing)
            } else {
                Text("\(CzFormat.time(entry.start))– běží").foregroundStyle(.tint)
                Text(timer.elapsedText).monospacedDigit().frame(width: 80, alignment: .trailing)
            }
            Text(amountText([entry])).monospacedDigit().foregroundStyle(.secondary).frame(width: 130, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(entry) }
        .contextMenu {
            if !entry.isRunning, let project = entry.project, !project.isArchived {
                Button("Pokračovat") { _ = try? timer.start(project, note: entry.note, tags: entry.tags) }
            }
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
    @State private var tags: [Tag]
    @State private var errorMessage: String?

    init(entry: TimeEntry?) {
        self.entry = entry
        let now = Date()
        _project = State(initialValue: entry?.project)
        _start = State(initialValue: entry?.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: entry?.end ?? now)
        _note = State(initialValue: entry?.note ?? "")
        _tags = State(initialValue: entry?.tags ?? [])
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
            TagPicker(selected: $tags)
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
            entry.tags = tags
        } else {
            let created = TimeEntry(project: project, start: start, end: end, note: cleanedNote)
            context.insert(created)
            created.tags = tags
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
    @State private var tags: [Tag]

    init(entry: TimeEntry) {
        self.entry = entry
        _note = State(initialValue: entry.note ?? "")
        _tags = State(initialValue: entry.tags)
    }

    var body: some View {
        Form {
            Text(entry.project?.name ?? "").foregroundStyle(.secondary)
            BulletTextEditor(text: $note, autofocus: true).frame(minHeight: 160)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            TagPicker(selected: $tags)
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
        entry.tags = tags
        try? context.save()
        dismiss()
    }
}
