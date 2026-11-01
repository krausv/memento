import AppKit
import Foundation
import Observation

/// Spouští `UpdateChecker` krátce po startu a pak jednou denně (pokud to uživatel nevypnul).
/// Selhání jsou tichá – položka v menu se prostě neukáže.
@MainActor
@Observable
final class UpdateStore {
    enum ManualStatus: Equatable { case checking, upToDate, failed }

    /// Novější vydání, o kterém víme.
    private(set) var available: ReleaseInfo?
    /// Výsledek poslední ruční kontroly; `nil` = nikdy se neptal.
    private(set) var manualStatus: ManualStatus?

    /// Průběh aktualizace zevnitř aplikace.
    enum InstallState: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var installState: InstallState = .idle

    /// Zavolá se, když instalace selže (aby se to dozvěděl i ten, kdo ji spustil z menu).
    @ObservationIgnored var onInstallFailure: ((String) -> Void)?

    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let canInstallInPlace: () -> Bool
    @ObservationIgnored private let installAction: (ReleaseInfo, @escaping @Sendable (Double) -> Void) async throws -> Void
    @ObservationIgnored private let openPage: (URL) -> Void
    @ObservationIgnored private let quit: () -> Void
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        checker: UpdateChecker = UpdateChecker(),
        currentVersion: String = UpdateStore.bundleVersion,
        isEnabled: @escaping () -> Bool = { AppSettings.checkForUpdates },
        canInstallInPlace: @escaping () -> Bool = { UpdateInstaller().canInstallInPlace },
        installAction: @escaping (ReleaseInfo, @escaping @Sendable (Double) -> Void) async throws -> Void = {
            try await UpdateInstaller().install($0, progress: $1)
        },
        openPage: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        quit: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.canInstallInPlace = canInstallInPlace
        self.installAction = installAction
        self.openPage = openPage
        self.quit = quit
        self.checker = checker
        self.currentVersion = currentVersion
        self.isEnabled = isEnabled
    }

    nonisolated static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var version: String { currentVersion }

    func start(initialDelay: Duration = .seconds(5), interval: Duration = .seconds(86_400)) {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: initialDelay)
            while !Task.isCancelled {
                guard let self else { return }
                if self.isEnabled() {
                    self.available = await self.checker.check(currentVersion: self.currentVersion)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Ruční kontrola: běží i při vypnuté automatické a ohlásí všechny tři výsledky.
    func checkNow() async {
        guard manualStatus != .checking else { return }
        manualStatus = .checking
        switch await checker.checkDetailed(currentVersion: currentVersion) {
        case .updateAvailable(let release):
            available = release
            manualStatus = nil
        case .upToDate:
            available = nil
            manualStatus = .upToDate
        case .failed:
            manualStatus = .failed
        }
    }

    var isInstalling: Bool {
        switch installState {
        case .downloading, .installing: true
        case .idle, .failed: false
        }
    }

    /// Aktualizace jedním klikem: stáhne, ověří, vymění aplikaci a restartuje. Kde to nejde
    /// (ad-hoc build, vydání bez DMG), otevře stránku vydání ke stažení ručně.
    func startUpdate() {
        guard let release = available, !isInstalling else { return }
        guard canInstallInPlace(), release.assetURL != nil else {
            openPage(release.url)
            return
        }
        Task { await install(release) }
    }

    func install(_ release: ReleaseInfo) async {
        guard !isInstalling else { return }
        installState = .downloading(0)
        do {
            try await installAction(release) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.installState else { return }
                    self.installState = .downloading(fraction)
                }
            }
            installState = .installing
            quit()
        } catch {
            let message = error.localizedDescription
            installState = .failed(message)
            onInstallFailure?(message)
        }
    }

    /// Stránka vydání – záloha pro případ, že se instalace nepovede.
    func openReleasePage() {
        if let release = available { openPage(release.url) }
    }
}
