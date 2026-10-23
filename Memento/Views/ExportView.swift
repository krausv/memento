import AppKit
import SwiftData
import SwiftUI

struct ExportView: View {
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var month = ReportMonth(containing: Date())
    @State private var selected = Set<UUID>()
    @State private var message: String?
    @State private var isError = false

    private var months: [ReportMonth] {
        var result = [ReportMonth(containing: Date())]
        while result.count < 24 { result.append(result.last!.previous()) }
        return result
    }

    private func entryCount(_ project: Project) -> Int {
        project.entries.filter { $0.end != nil && month.contains($0.start) }.count
    }

    var body: some View {
        Form {
            Section("Období") {
                Picker("Měsíc", selection: $month) {
                    ForEach(months, id: \.self) { Text(CzFormat.month($0)).tag($0) }
                }
                HStack {
                    Button("Tento měsíc") { month = ReportMonth(containing: Date()) }
                    Button("Minulý měsíc") { month = ReportMonth(containing: Date()).previous() }
                }
            }
            Section("Projekty") {
                if projects.isEmpty { Text("Žádné projekty.").foregroundStyle(.secondary) }
                ForEach(projects) { project in
                    let count = entryCount(project)
                    Toggle(isOn: Binding(
                        get: { selected.contains(project.id) },
                        set: { if $0 { selected.insert(project.id) } else { selected.remove(project.id) } }
                    )) {
                        HStack {
                            Text(project.name)
                            Spacer()
                            Text(count == 0 ? "bez záznamů" : "\(count) záznamů").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Exportovat do PDF…", action: export)
                    .disabled(selected.isEmpty)
                if let message {
                    Text(message).foregroundStyle(isError ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export")
        .onAppear(perform: selectDefaults)
        .onChange(of: month) { selectDefaults() }
    }

    /// Výchozí výběr: všechny projekty, které mají v daném měsíci záznamy.
    private func selectDefaults() {
        selected = Set(projects.filter { entryCount($0) > 0 }.map(\.id))
        message = nil
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Exportovat"
        panel.message = "Vyber složku, do které se uloží PDF výkazy."
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            let urls = try PDFExporter.export(
                projects: projects.filter { selected.contains($0.id) },
                month: month,
                rounding: AppSettings.rounding,
                supplier: ReportSupplier(name: AppSettings.supplierName, ico: AppSettings.supplierIco),
                to: folder
            )
            isError = false
            message = "Vytvořeno PDF: \(urls.count)"
            NSWorkspace.shared.open(folder)
        } catch {
            isError = true
            message = "Export selhal: \(error.localizedDescription)"
        }
    }
}
