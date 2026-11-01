import AppKit
import CryptoKit
import Foundation
import Security

enum UpdateInstallError: LocalizedError, Equatable {
    case noAsset
    case unsignedApp
    case notWritable
    case download(String)
    case checksum
    case mount(String)
    case appMissing
    case signature
    case replace(String)

    var errorDescription: String? {
        switch self {
        case .noAsset: "Vydání neobsahuje soubor ke stažení."
        case .unsignedApp: "Tato kopie aplikace není podepsaná Developer ID, nelze ji aktualizovat zevnitř."
        case .notWritable: "Do složky s aplikací nelze zapisovat (je spuštěná z DMG nebo ze složky bez oprávnění)."
        case .download(let detail): "Stažení se nepovedlo: \(detail)"
        case .checksum: "Stažený soubor neodpovídá kontrolnímu součtu z GitHubu."
        case .mount(let detail): "Otevření staženého obrazu se nepovedlo: \(detail)"
        case .appMissing: "Stažený obraz neobsahuje Memento.app."
        case .signature: "Stažená aplikace nemá platný podpis stejného vývojáře, aktualizace se neprovede."
        case .replace(let detail): "Výměna aplikace se nepovedla: \(detail)"
        }
    }
}

/// Stáhne DMG z vydání, ověří ho (kontrolní součet + podpis stejného týmu jako běžící aplikace),
/// vymění `Memento.app` a spustí novou kopii. Žádná cizí aplikace se nenainstaluje: bez platného
/// podpisu stejného Team ID aktualizace končí chybou a nic se nemění.
struct UpdateInstaller {
    var appURL: URL = Bundle.main.bundleURL

    /// Aktualizovat zevnitř jde jen aplikaci podepsané Developer ID (ne ad-hoc vývojářské buildy).
    var canInstallInPlace: Bool { Self.teamIdentifier(of: appURL) != nil }

    func install(_ release: ReleaseInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let asset = release.assetURL else { throw UpdateInstallError.noAsset }
        guard let team = Self.teamIdentifier(of: appURL) else { throw UpdateInstallError.unsignedApp }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw UpdateInstallError.notWritable
        }

        let dmg = try await Self.download(asset, progress: progress)
        defer { try? FileManager.default.removeItem(at: dmg) }
        if let expected = release.sha256, try Self.sha256(of: dmg) != expected.lowercased() {
            throw UpdateInstallError.checksum
        }

        let staged = try await Self.extractApp(from: dmg, near: appURL)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        try Self.verifySignature(of: staged, team: team, identifier: Bundle.main.bundleIdentifier)

        do {
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staged)
        } catch {
            throw UpdateInstallError.replace(error.localizedDescription)
        }
        Self.relaunch(appURL, after: ProcessInfo.processInfo.processIdentifier)
    }

    // MARK: Stažení a kontrolní součet

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
        let onProgress: @Sendable (Double) -> Void
        init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (temp, response) = try await URLSession.shared.download(for: request, delegate: ProgressDelegate(progress))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                try? FileManager.default.removeItem(at: temp)
                throw UpdateInstallError.download("server vrátil neočekávanou odpověď")
            }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("Memento-update-\(UUID().uuidString).dmg")
            try FileManager.default.moveItem(at: temp, to: target)
            return target
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.download(error.localizedDescription)
        }
    }

    /// Hodnota ve tvaru `sha256:<hex>` (jak ji vrací GitHub) → malá hex písmena.
    static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: DMG

    /// Připojí DMG jen pro čtení, zkopíruje z něj aplikaci do dočasné složky na stejném disku jako cíl a obraz odpojí.
    static func extractApp(from dmg: URL, near destination: URL) async throws -> URL {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("Memento-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        do {
            try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen",
                                               "-mountpoint", mountPoint.path, dmg.path])
        } catch {
            try? fm.removeItem(at: mountPoint)
            throw UpdateInstallError.mount(error.localizedDescription)
        }
        defer {
            Task.detached {
                _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
                try? FileManager.default.removeItem(at: mountPoint)
            }
        }
        let source = mountPoint.appendingPathComponent("Memento.app")
        guard fm.fileExists(atPath: source.path) else { throw UpdateInstallError.appMissing }
        let folder = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        let staged = folder.appendingPathComponent("Memento.app")
        do {
            try fm.copyItem(at: source, to: staged)
        } catch {
            throw UpdateInstallError.replace(error.localizedDescription)
        }
        return staged
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateInstallError.mount(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: Podpis

    /// Team ID, kterým je aplikace podepsaná; `nil` pro ad-hoc nebo nepodepsanou.
    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Požadavek na podpis: Developer ID řetězec Applu, stejný Team ID a (pokud je známý) stejný bundle ID.
    static func requirement(team: String, identifier: String?) -> String {
        var text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        if let identifier { text += " and identifier \"\(identifier)\"" }
        return text
    }

    static func verifySignature(of app: URL, team: String, identifier: String?) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(Self.requirement(team: team, identifier: identifier) as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw UpdateInstallError.signature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil) == errSecSuccess else {
            throw UpdateInstallError.signature
        }
    }

    // MARK: Restart

    /// Shell s jednoduchými uvozovkami kolem cesty (apostrof v cestě se escapuje).
    static func relaunchScript(pid: Int32, path: String) -> String {
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \(quoted)"
    }

    /// Po skončení této aplikace spustí novou kopii. Skript přežije ukončení rodiče.
    static func relaunch(_ app: URL, after pid: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", relaunchScript(pid: pid, path: app.path)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
