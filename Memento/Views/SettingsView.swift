import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.rounding) private var roundingMinutes = RoundingOption.none.rawValue
    @AppStorage(SettingsKey.supplierName) private var supplierName = ""
    @AppStorage(SettingsKey.supplierIco) private var supplierIco = ""

    @State private var defaultRate = AppSettings.defaultRate
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

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
            Section("Systém") {
                Toggle("Spustit při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let launchError { Text(launchError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nastavení")
    }

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
