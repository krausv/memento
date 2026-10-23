import SwiftUI

struct MainWindow: View {
    static let id = "main"

    enum Section: String, CaseIterable, Identifiable {
        case projects = "Projekty"
        case entries = "Záznamy"
        case stats = "Přehled"
        case export = "Export"
        case settings = "Nastavení"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .projects: "folder"
            case .entries: "list.bullet.rectangle"
            case .stats: "chart.bar"
            case .export: "square.and.arrow.up"
            case .settings: "gearshape"
            }
        }
    }

    @State private var selection: Section? = .projects

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection ?? .projects {
            case .projects: ProjectsView()
            case .entries: EntriesView()
            case .stats: StatsView()
            case .export: ExportView()
            case .settings: SettingsView()
            }
        }
    }
}
