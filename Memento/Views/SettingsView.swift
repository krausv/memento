import AppKit
import ServiceManagement
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @AppStorage(SettingsKey.rounding) private var roundingMinutes = RoundingOption.none.rawValue
    @AppStorage(SettingsKey.supplierName) private var supplierName = ""
    @AppStorage(SettingsKey.supplierIco) private var supplierIco = ""

    @State private var defaultRate = AppSettings.defaultRate
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var pendingBackup: Backup?
    @State private var backupMessage: String?
    @State private var backupFailed = false

    var body: some View {
        Form {
            Section("Projekty") {
                TextField("Výchozí sazba pro nové projekty", value: $defaultRate,
                          format: .number.precision(.fractionLength(0...2)))
                    .onChange(of: defaultRate) { AppSettings.defaultRate = max(0, defaultRate) }
            }
            Section("Export") {
                Picker("Zaokrouhlení záznamů", selection: $roundingMinutes) {
                    ForEach(RoundingOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("Uložená data se nezaokrouhlují, jen výpočet v exportu.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Jméno dodavatele", text: $supplierName)
                TextField("IČO dodavatele", text: $supplierIco)
            }
            TagManagerSection()
            Section("Záloha") {
                HStack {
                    Button("Exportovat zálohu…", action: exportBackup)
                    Button("Importovat zálohu…", action: chooseBackup)
                }
                Text("Záloha je JSON se všemi projekty, záznamy a nastavením. Data jinak existují jen v tomto Macu.")
                    .font(.caption).foregroundStyle(.secondary)
                if let backupMessage {
                    Text(backupMessage).foregroundStyle(backupFailed ? .red : .secondary)
                }
            }
            Section("Systém") {
                Toggle("Spustit při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let launchError { Text(launchError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nastavení")
        .confirmationDialog(
            "Importovat zálohu",
            isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
            presenting: pendingBackup
        ) { backup in
            Button("Sloučit s existujícími daty") { restore(backup, mode: .merge) }
            Button("Nahradit všechna data", role: .destructive) { restore(backup, mode: .replace) }
            Button("Zrušit", role: .cancel) {}
        } message: { backup in
            Text("Záloha z \(CzFormat.date(backup.exportedAt)): projektů \(backup.projects.count), záznamů \(backup.entries.count). Sloučení nic nemaže; nahrazení smaže stávající data i nastavení.")
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "memento-zaloha-\(Self.fileDate.string(from: Date())).json"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try BackupService.makeBackup(context: context)
            try BackupService.encode(backup).write(to: url, options: .atomic)
            report("Záloha uložena: projektů \(backup.projects.count), záznamů \(backup.entries.count).")
        } catch {
            report("Export selhal: \(error.localizedDescription)", failed: true)
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingBackup = try BackupService.decode(Data(contentsOf: url))
            backupMessage = nil
        } catch {
            report("Import selhal: \(error.localizedDescription)", failed: true)
        }
    }

    private func restore(_ backup: Backup, mode: RestoreMode) {
        do {
            let summary = try BackupService.restore(backup, mode: mode, context: context)
            timer.refresh()
            defaultRate = AppSettings.defaultRate
            report("Import hotov: přidáno projektů \(summary.addedProjects), záznamů \(summary.addedEntries), přeskočeno \(summary.skippedEntries).")
        } catch {
            report("Import selhal: \(error.localizedDescription)", failed: true)
        }
    }

    private func report(_ message: String, failed: Bool = false) {
        backupMessage = message
        backupFailed = failed
    }

    private static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = .prague
        formatter.timeZone = Calendar.prague.timeZone
        return formatter
    }()

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Nepodařilo se změnit spouštění při přihlášení: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
