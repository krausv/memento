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

    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        checker: UpdateChecker = UpdateChecker(),
        currentVersion: String = UpdateStore.bundleVersion,
        isEnabled: @escaping () -> Bool = { AppSettings.checkForUpdates }
    ) {
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
}
