import SwiftData
import SwiftUI

struct ProjectsView: View {
    private enum Sheet: Identifiable {
        case newProject
        case editProject(Project)

        var id: String {
            switch self {
            case .newProject: "newProject"
            case .editProject(let p): "editProject-\(p.id)"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \Project.createdAt) private var projects: [Project]

    @AppStorage("showArchivedProjects") private var showArchived = false
    @State private var sheet: Sheet?
    @State private var projectToDelete: Project?

    private var visibleProjects: [Project] {
        projects.filter { showArchived || !$0.isArchived }
    }

    var body: some View {
        List {
            if visibleProjects.isEmpty {
                ContentUnavailableView("Žádné projekty", systemImage: "folder.badge.plus",
                                       description: Text("Vytvoř první projekt tlačítkem „Nový projekt“."))
            }
            ForEach(visibleProjects) { project in
                projectRow(project)
            }
        }
        .navigationTitle("Projekty")
        .toolbar {
            ToolbarItem {
                Toggle("Archivované", isOn: $showArchived)
            }
            ToolbarItem {
                Button("Nový projekt", systemImage: "plus") { sheet = .newProject }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newProject: ProjectForm(project: nil)
            case .editProject(let project): ProjectForm(project: project)
            }
        }
        .alert(
            "Smazat projekt „\(projectToDelete?.name ?? "")“?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            presenting: projectToDelete
        ) { project in
            Button("Smazat", role: .destructive) { delete(project) }
            Button("Zrušit", role: .cancel) {}
        } message: { _ in
            Text("Smažou se i všechny jeho záznamy času. Raději projekt archivuj.")
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack {
            Button("Spustit", systemImage: "play.fill") { _ = try? timer.start(project) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(project.isArchived)
            VStack(alignment: .leading) {
                Text(project.name).font(.headline)
                Text([project.client, "\(CzFormat.decimal(project.hourlyRate)) \(project.currency)/h"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if project.isArchived { Text("archivováno").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if timer.runningEntry?.project === project {
                Text(timer.elapsedText).monospacedDigit().foregroundStyle(.tint)
            }
            Menu("Akce", systemImage: "ellipsis.circle") {
                Button("Upravit") { sheet = .editProject(project) }
                Button(project.isArchived ? "Obnovit z archivu" : "Archivovat") { toggleArchive(project) }
                Divider()
                Button("Smazat…", role: .destructive) { projectToDelete = project }
            }
            .menuStyle(.borderlessButton)
            .labelStyle(.iconOnly)
            .fixedSize()
        }
    }

    private func toggleArchive(_ project: Project) {
        project.isArchived.toggle()
        try? context.save()
    }

    private func delete(_ project: Project) {
        // Běžící záznam mizí s projektem – ticker se musí znovu načíst.
        context.delete(project)
        try? context.save()
        timer.refresh()
    }
}

struct ProjectForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProjects: [Project]

    let project: Project?
    @State private var name = ""
    @State private var client = ""
    @State private var rate: Decimal = 0
    @State private var currency = "CZK"

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _client = State(initialValue: project?.client ?? "")
        _rate = State(initialValue: project?.hourlyRate ?? AppSettings.defaultRate)
        _currency = State(initialValue: project?.currency ?? "CZK")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var error: String? {
        if trimmedName.isEmpty { return "Název je povinný." }
        if allProjects.contains(where: { $0 !== project && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return "Projekt s tímto názvem už existuje."
        }
        if rate < 0 { return "Sazba nesmí být záporná." }
        if currency.trimmingCharacters(in: .whitespaces).isEmpty { return "Měna je povinná." }
        return nil
    }

    var body: some View {
        Form {
            TextField("Název", text: $name)
            TextField("Klient", text: $client)
            TextField("Hodinová sazba", value: $rate, format: .number.precision(.fractionLength(0...2)))
            TextField("Měna", text: $currency)
            if let error, !trimmedName.isEmpty || rate < 0 {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .navigationTitle(project == nil ? "Nový projekt" : "Upravit projekt")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Uložit", action: save).disabled(error != nil) }
        }
    }

    private func save() {
        let clientValue = client.trimmingCharacters(in: .whitespacesAndNewlines)
        let currencyValue = currency.trimmingCharacters(in: .whitespaces).uppercased()
        if let project {
            project.name = trimmedName
            project.client = clientValue.isEmpty ? nil : clientValue
            project.hourlyRate = rate
            project.currency = currencyValue
        } else {
            context.insert(Project(name: trimmedName, client: clientValue.isEmpty ? nil : clientValue,
                                   hourlyRate: rate, currency: currencyValue))
        }
        try? context.save()
        dismiss()
    }
}
