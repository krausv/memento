import SwiftData
import SwiftUI

/// Výchozí obrazovka: dnešní záznamy a kolik ještě dnes odpracovat, aby vyšel měsíční cíl.
struct TodayView: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.theme) private var theme
    @Query(sort: \TimeEntry.start, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var showingNew = false
    @State private var editing: TimeEntry?
    @State private var editingNote: TimeEntry?

    private var todayEntries: [TimeEntry] {
        let calendar = Calendar.prague
        return allEntries.filter { calendar.isDate($0.start, inSameDayAs: timer.now) }
    }

    private func workedSeconds(_ list: [TimeEntry]) -> Int {
        Int(list.reduce(0) { $0 + $1.duration(at: timer.now) })
    }

    private var targetProjects: [Project] {
        projects.filter { !$0.isArchived && ($0.targetAmount ?? 0) > 0 }
    }

    var body: some View {
        let entries = todayEntries
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(CzFormat.dayHeading(timer.now).capitalized(with: CzFormat.locale)).font(.title2.bold())
                    Spacer()
                    Label("Odpracováno dnes: \(CzFormat.hours(seconds: workedSeconds(entries)))", systemImage: "clock")
                        .font(.title3.bold()).monospacedDigit()
                }
                planCard(entries)
                card("Dnešní záznamy") { entriesList(entries) }
            }
            .padding(20)
        }
        .environment(\.locale, CzFormat.locale)
        .environment(\.calendar, .prague)
        .environment(\.timeZone, Calendar.prague.timeZone)
        .navigationTitle("Dnešní den")
        .toolbar {
            ToolbarItem {
                Button("Přidat záznam", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { EntryForm(entry: nil) }
        .sheet(item: $editing) { EntryForm(entry: $0) }
        .sheet(item: $editingNote) { NoteForm(entry: $0) }
    }

    // MARK: Plán na dnešek

    @ViewBuilder
    private func planCard(_ entries: [TimeEntry]) -> some View {
        let withTarget = targetProjects
        if withTarget.isEmpty {
            card("Plán na dnešek") {
                Text("Žádný projekt nemá nastavený měsíční cíl. Cíl (částku) nastavíš u projektu v sekci Projekty.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            let rounding = AppSettings.rounding
            let month = ReportMonth(containing: timer.now)
            card("Plán na dnešek · měsíční cíl") {
                ForEach(withTarget) { project in
                    if let status = project.targetStatus(now: timer.now, rounding: rounding, month: month) {
                        let worked = workedSeconds(entries.filter { $0.project === project })
                        planRow(project, status, workedToday: worked)
                    }
                }
                Text("Plán rozkládá zbývající hodiny do cíle rovnoměrně na zbývající pracovní dny (včetně zbytku dneška) podle Nastavení › Připomínky.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planRow(_ project: Project, _ status: TargetStatus, workedToday: Int) -> some View {
        if let forecast = TargetForecast.compute(status: status, hourlyRate: project.hourlyRate,
                                                 now: timer.now, schedule: AppSettings.reminders) {
            let required = forecast.requiredTodaySeconds(workedToday: workedToday)
            let planned = workedToday + required
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name).font(.subheadline.bold())
                    Spacer()
                    Text(headline(forecast, required: required)).font(.subheadline.bold()).monospacedDigit()
                        .foregroundStyle(forecast.verdict == .reached ? .green : .primary)
                }
                if forecast.verdict != .reached, required > 0 {
                    ProgressView(value: Double(workedToday), total: Double(max(planned, 1)))
                    Text("Odpracováno dnes \(CzFormat.hours(seconds: workedToday)) z denního plánu \(CzFormat.hours(seconds: planned)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if required > forecast.todayCapacitySeconds, forecast.todayCapacitySeconds > 0 {
                    Text("Do konce pracovní doby zbývá jen \(CzFormat.hours(seconds: forecast.todayCapacitySeconds)).")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Do cíle zbývá \(CzFormat.hours(seconds: forecast.remainingSeconds)) · \(CzFormat.money(status.amount, currency: project.currency)) z \(CzFormat.money(status.target, currency: project.currency)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func headline(_ forecast: TargetForecast, required: Int) -> String {
        if forecast.verdict == .reached { return "cíl splněn" }
        if required > 0 { return "dnes zbývá \(CzFormat.hours(seconds: required))" }
        if forecast.workDaysLeft == 0 { return "do konce měsíce už není pracovní doba" }
        return "dnes mimo pracovní dobu"
    }

    // MARK: Záznamy

    @ViewBuilder
    private func entriesList(_ entries: [TimeEntry]) -> some View {
        if entries.isEmpty {
            Text("Dnes zatím žádné záznamy.").font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(entries) { entry in
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
                        Text(CzFormat.hours(seconds: Int(entry.duration))).monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    } else {
                        Text("\(CzFormat.time(entry.start))– běží").foregroundStyle(.tint)
                        Text(timer.elapsedText).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if entry.isRunning { editingNote = entry } else { editing = entry } }
                if entry.id != entries.last?.id { Divider() }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.surface, in: .rect(cornerRadius: 14))
    }
}
