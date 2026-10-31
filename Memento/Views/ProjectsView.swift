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
            ForEach(visibleProjects) { project in
                projectRow(project)
            }
        }
        .overlay {
            if visibleProjects.isEmpty {
                ContentUnavailableView("Žádné projekty", systemImage: "folder.badge.plus",
                                       description: Text("Vytvoř první projekt tlačítkem „Nový projekt“."))
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
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(project.isArchived)
            VStack(alignment: .leading) {
                Text(project.name).font(.headline)
                Text([project.client, "\(CzFormat.decimal(project.hourlyRate)) \(project.currency)/h"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let status = project.budgetStatus(now: timer.now, rounding: AppSettings.rounding) {
                    budgetView(project, status)
                }
                if let target = project.targetStatus(now: timer.now, rounding: AppSettings.rounding) {
                    targetView(project, target)
                }
            }
            if project.isArchived { Text("archivováno").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if timer.runningEntry?.project === project {
                Text(timer.elapsedText)
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: .capsule)
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

    private func budgetView(_ project: Project, _ status: BudgetStatus) -> some View {
        let tint: Color = status.level >= BudgetStatus.exceededLevel ? .red : status.level >= BudgetStatus.warningLevel ? .orange : .accentColor
        return VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(status.fraction, 1)).tint(tint).frame(width: 180)
            Text("\(CzFormat.hours(seconds: status.usedSeconds)) z \(CzFormat.hours(seconds: status.budgetSeconds)) · \(project.budgetPeriodValue.title.lowercased())")
                .font(.caption).foregroundStyle(tint == .accentColor ? Color.secondary : tint)
        }
    }

    private func targetView(_ project: Project, _ status: TargetStatus) -> some View {
        let (label, tint): (String, Color) = switch status.position {
        case .under: ("pod hranicí", .accentColor)
        case .on: ("na hranici", .green)
        case .over: ("nad hranicí", .orange)
        }
        let difference = status.difference
        let detail = difference < 0
            ? "chybí \(CzFormat.money(-difference, currency: project.currency))"
            : "+\(CzFormat.money(difference, currency: project.currency))"
        return VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(status.fraction, 1)).tint(tint).frame(width: 180)
            Text("\(CzFormat.money(status.amount, currency: project.currency)) z \(CzFormat.money(status.target, currency: project.currency)) tento měsíc · \(label) (\(detail))")
                .font(.caption).foregroundStyle(tint == .accentColor ? Color.secondary : tint)
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
    @State private var hasBudget: Bool
    @State private var budgetHours: Decimal
    @State private var budgetPeriod: BudgetPeriod
    @State private var hasTarget: Bool
    @State private var targetAmount: Decimal

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _client = State(initialValue: project?.client ?? "")
        _rate = State(initialValue: project?.hourlyRate ?? AppSettings.defaultRate)
        _currency = State(initialValue: project?.currency ?? "CZK")
        _hasBudget = State(initialValue: project?.budgetHours != nil)
        _budgetHours = State(initialValue: project?.budgetHours ?? 40)
        _budgetPeriod = State(initialValue: project?.budgetPeriodValue ?? .total)
        _hasTarget = State(initialValue: project?.targetAmount != nil)
        _targetAmount = State(initialValue: project?.targetAmount ?? 50_000)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var error: String? {
        if trimmedName.isEmpty { return "Název je povinný." }
        if allProjects.contains(where: { $0 !== project && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return "Projekt s tímto názvem už existuje."
        }
        if rate < 0 { return "Sazba nesmí být záporná." }
        if currency.trimmingCharacters(in: .whitespaces).isEmpty { return "Měna je povinná." }
        if hasBudget, budgetHours <= 0 { return "Limit hodin musí být kladný." }
        if hasTarget, targetAmount <= 0 { return "Měsíční cíl musí být kladný." }
        return nil
    }

    var body: some View {
        Form {
            TextField("Název", text: $name)
            TextField("Klient", text: $client)
            TextField("Hodinová sazba", value: $rate, format: .number.precision(.fractionLength(0...2)))
            TextField("Měna", text: $currency)
            Section("Limit a cíl") {
                Toggle("Hlídat limit hodin", isOn: $hasBudget)
                if hasBudget {
                    TextField("Limit (hodiny)", value: $budgetHours, format: .number.precision(.fractionLength(0...2)))
                    Picker("Období", selection: $budgetPeriod) {
                        ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Upozornění přijde při 80 % a po překročení limitu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Měsíční cíl fakturace", isOn: $hasTarget)
                if hasTarget {
                    TextField("Cíl za měsíc (\(currency))", value: $targetAmount, format: .number.precision(.fractionLength(0...2)))
                    Text("Hodnotí se částka za aktuální měsíc podle sazby projektu: pod hranicí, na hranici (±2 % cíle) a nad ní. Upozornění přijde po dosažení cíle a po jeho překročení.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error, !trimmedName.isEmpty || rate < 0 || hasBudget || hasTarget {
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

    private func applyBudget(to project: Project) {
        let wasEnabled = project.budgetHours != nil || project.targetAmount != nil
        project.budgetHours = hasBudget ? budgetHours : nil
        project.targetAmount = hasTarget ? targetAmount : nil
        project.budgetPeriod = budgetPeriod.rawValue
        // Po úpravě limitu se stávající čerpání neoznamuje, hlídá se až další překročení.
        project.syncBudgetAlertState(now: Date(), rounding: AppSettings.rounding)
        if hasBudget || hasTarget, !wasEnabled { Notifications.requestAuthorization() }
    }

    private func save() {
        let clientValue = client.trimmingCharacters(in: .whitespacesAndNewlines)
        let currencyValue = currency.trimmingCharacters(in: .whitespaces).uppercased()
        if let project {
            project.name = trimmedName
            project.client = clientValue.isEmpty ? nil : clientValue
            project.hourlyRate = rate
            project.currency = currencyValue
            applyBudget(to: project)
        } else {
            let created = Project(name: trimmedName, client: clientValue.isEmpty ? nil : clientValue,
                                  hourlyRate: rate, currency: currencyValue)
            context.insert(created)
            applyBudget(to: created)
        }
        try? context.save()
        dismiss()
    }
}
