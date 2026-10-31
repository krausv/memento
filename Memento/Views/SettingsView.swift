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
    @AppStorage(SettingsKey.palette) private var paletteRaw = Palette.travertine.rawValue

    @State private var defaultRate = AppSettings.defaultRate
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var reminders = AppSettings.reminders
    @State private var pomodoro = AppSettings.pomodoro
    @State private var autoBackup = AppSettings.autoBackup()
    @State private var lastAutoBackup = AppSettings.lastAutoBackup()
    @State private var autoBackupError = AppSettings.lastAutoBackupError()
    @State private var pendingBackup: Backup?
    @State private var backupMessage: String?
    @State private var backupFailed = false

    var body: some View {
        Form {
            Section("Vzhled") {
                Picker("Barevná paleta", selection: $paletteRaw) {
                    ForEach(Palette.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text((Palette(rawValue: paletteRaw) ?? .travertine).detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            remindersSection
            pomodoroSection
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
            autoBackupSection
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

    private static let weekdays: [(day: Int, title: String)] = [
        (2, "Po"), (3, "Út"), (4, "St"), (5, "Čt"), (6, "Pá"), (7, "So"), (1, "Ne"),
    ]

    private var remindersSection: some View {
        Section("Připomínky") {
            Toggle("Připomenout, když v pracovní době neběží časovač", isOn: $reminders.remindNotRunning)
            if reminders.remindNotRunning {
                HStack {
                    Text("Pracovní dny")
                    Spacer()
                    ForEach(Self.weekdays, id: \.day) { weekday in
                        Toggle(weekday.title, isOn: Binding(
                            get: { reminders.workDays.contains(weekday.day) },
                            set: { on in
                                if on { reminders.workDays.insert(weekday.day) } else { reminders.workDays.remove(weekday.day) }
                            }
                        ))
                        .toggleStyle(.button)
                    }
                }
                DatePicker("Od", selection: minutesBinding(\.workStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Do", selection: minutesBinding(\.workEndMinutes), displayedComponents: .hourAndMinute)
                Text("Připomíná nejvýš jednou za hodinu a ne dříve než 15 minut po zastavení časovače.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Upozornit, když časovač běží příliš dlouho", isOn: $reminders.remindLongRunning)
            if reminders.remindLongRunning {
                Stepper("Po \(reminders.longRunningHours) h", value: $reminders.longRunningHours, in: 1...24)
            }
            Toggle("Upozornit, když časovač běží bez poznámky", isOn: $reminders.remindMissingNote)
            if reminders.remindMissingNote {
                Stepper("Po \(reminders.missingNoteMinutes) min", value: $reminders.missingNoteMinutes, in: 5...480, step: 5)
                Text("Upozornění přijde jednou za záznam; kliknutím na něj se otevře zadání poznámky.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .environment(\.locale, CzFormat.locale)
        .environment(\.calendar, .prague)
        .environment(\.timeZone, Calendar.prague.timeZone)
        .onChange(of: reminders) {
            AppSettings.reminders = reminders
            if reminders.remindNotRunning || reminders.remindLongRunning || reminders.remindMissingNote { Notifications.requestAuthorization() }
        }
    }

    private var pomodoroSection: some View {
        Section("Pomodoro") {
            Toggle("Oznámení na konci fáze", isOn: $pomodoro.notifications)
            Toggle("Vizuální časovač (plovoucí okno)", isOn: $pomodoro.visualTimer)
            if pomodoro.isActive {
                Stepper("Práce: \(pomodoro.workMinutes) min", value: $pomodoro.workMinutes, in: 5...120, step: 5)
                Stepper("Krátká pauza: \(pomodoro.shortBreakMinutes) min", value: $pomodoro.shortBreakMinutes, in: 1...30)
                Stepper("Dlouhá pauza: \(pomodoro.longBreakMinutes) min", value: $pomodoro.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Dlouhá pauza po \(pomodoro.cyclesBeforeLongBreak) pomodorech",
                        value: $pomodoro.cyclesBeforeLongBreak, in: 2...10)
                Toggle("Další fáze naváže automaticky", isOn: $pomodoro.autoAdvance)
                Text("Cyklus začíná spuštěním časovače a končí jeho zastavením. Pomodoro jen připomíná, měření času pauzou nezastavuje. "
                     + (pomodoro.autoAdvance
                        ? "Fáze se střídají samy."
                        : "Další fáze začne až po kliknutí na „Spustit“ v oznámení nebo v plovoucím okně."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: pomodoro) {
            AppSettings.pomodoro = pomodoro
            if pomodoro.notifications { Notifications.requestAuthorization() }
        }
    }

    /// Čas v minutách od půlnoci jako `Date` pro `DatePicker` (datum je v pražském kalendáři libovolné).
    private func minutesBinding(_ keyPath: WritableKeyPath<ReminderSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.prague.date(bySettingHour: reminders[keyPath: keyPath] / 60,
                                     minute: reminders[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.prague.dateComponents([.hour, .minute], from: date)
                reminders[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var autoBackupSection: some View {
        Section("Automatická záloha") {
            Toggle("Zálohovat automaticky do složky", isOn: Binding(
                get: { autoBackup.enabled },
                set: { setAutoBackupEnabled($0) }
            ))
            if autoBackup.enabled || autoBackup.folderPath != nil {
                LabeledContent("Složka") {
                    HStack {
                        Text(autoBackup.folderPath ?? "není zvolená")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Zvolit…") { chooseAutoBackupFolder() }
                    }
                }
                Picker("Četnost", selection: $autoBackup.frequency) {
                    ForEach(AutoBackupFrequency.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Ponechat posledních \(autoBackup.keepCount) záloh", value: $autoBackup.keepCount, in: 1...100)
                HStack {
                    Button("Zálohovat teď", action: runAutoBackupNow)
                        .disabled(autoBackup.folderPath == nil)
                    if let lastAutoBackup {
                        Text("Poslední záloha: \(CzFormat.date(lastAutoBackup)) \(CzFormat.time(lastAutoBackup))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let autoBackupError {
                    Text(autoBackupError).font(.caption).foregroundStyle(.red)
                }
                Text("Kontrola probíhá po spuštění, po probuzení Macu a jednou za hodinu. Mažou se jen soubory memento-auto-*.json vytvořené touto funkcí.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: autoBackup) { AppSettings.setAutoBackup(autoBackup) }
    }

    private func setAutoBackupEnabled(_ enabled: Bool) {
        autoBackup.enabled = enabled
        guard enabled else { return }
        Notifications.requestAuthorization()
        if autoBackup.folderPath == nil { chooseAutoBackupFolder() }
        // Bez složky by zapnutí nic nedělalo.
        if autoBackup.folderPath == nil { autoBackup.enabled = false }
    }

    private func chooseAutoBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Zvolit"
        panel.message = "Vyber složku, do které se budou ukládat automatické zálohy."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        autoBackup.folderPath = url.path
    }

    private func runAutoBackupNow() {
        AppSettings.setAutoBackup(autoBackup)
        let now = Date()
        do {
            try AutoBackupService.run(context: context, settings: autoBackup, now: now)
            AppSettings.recordAutoBackup(date: now, error: nil)
        } catch {
            AppSettings.recordAutoBackup(date: nil, error: error.localizedDescription)
        }
        lastAutoBackup = AppSettings.lastAutoBackup()
        autoBackupError = AppSettings.lastAutoBackupError()
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
            reminders = AppSettings.reminders
            pomodoro = AppSettings.pomodoro
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
