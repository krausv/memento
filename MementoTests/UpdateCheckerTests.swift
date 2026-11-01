import XCTest
@testable import Memento

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndVPrefixedVersions() {
        XCTAssertEqual(AppVersion("1.0.4")?.components, [1, 0, 4])
        XCTAssertEqual(AppVersion("v0.2.0")?.components, [0, 2, 0])
    }

    func testRejectsUnparseableVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x.2"))
    }

    func testComparesNumericallyPerComponent() {
        XCTAssertTrue(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        XCTAssertTrue(AppVersion("1.1.0")! > AppVersion("1.0.99")!)
        XCTAssertTrue(AppVersion("2.0")! > AppVersion("1.9.9")!)
        XCTAssertFalse(AppVersion("1.0.4")! > AppVersion("1.0.4")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertTrue(AppVersion("1.0.1")! > AppVersion("1.0")!)
    }
}

final class UpdateCheckerTests: XCTestCase {
    private let sample = Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/krausv/memento/releases/tag/v0.2.0","draft":false}"#.utf8)

    func testDecodesLatestReleaseResponse() throws {
        let release = try UpdateChecker.decode(sample)
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.url.absoluteString, "https://github.com/krausv/memento/releases/tag/v0.2.0")
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try UpdateChecker.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try UpdateChecker.decode(Data(#"{"tag_name":"nonsense","html_url":"https://x.cz"}"#.utf8)))
    }

    func testDetailedResults() async {
        let data = sample
        let checker = UpdateChecker(fetchData: { data })
        let newer = await checker.checkDetailed(currentVersion: "0.1.0")
        guard case .updateAvailable(let release) = newer else { return XCTFail("očekávána aktualizace") }
        XCTAssertEqual(release.tagName, "v0.2.0")
        let same = await checker.checkDetailed(currentVersion: "0.2.0")
        XCTAssertEqual(same, .upToDate)
        let ahead = await checker.checkDetailed(currentVersion: "0.3.0")
        XCTAssertEqual(ahead, .upToDate)
        let badCurrent = await checker.checkDetailed(currentVersion: "?")
        XCTAssertEqual(badCurrent, .failed)
    }

    func testCheckIsSilentOnFailureAndWhenCurrent() async {
        let data = sample
        let failing = UpdateChecker(fetchData: { throw URLError(.notConnectedToInternet) })
        let failed = await failing.check(currentVersion: "0.1.0")
        XCTAssertNil(failed)
        let current = await UpdateChecker(fetchData: { data }).check(currentVersion: "0.2.0")
        XCTAssertNil(current)
        let newer = await UpdateChecker(fetchData: { data }).check(currentVersion: "0.1.0")
        XCTAssertEqual(newer?.tagName, "v0.2.0")
    }
}

@MainActor
final class UpdateStoreTests: XCTestCase {
    private let sample = Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/krausv/memento/releases/tag/v0.2.0"}"#.utf8)

    func testManualCheckReportsAvailableThenUpToDate() async {
        let data = sample
        let store = UpdateStore(checker: UpdateChecker(fetchData: { data }), currentVersion: "0.1.0", isEnabled: { false })
        await store.checkNow()
        XCTAssertEqual(store.available?.tagName, "v0.2.0")
        XCTAssertNil(store.manualStatus)

        let current = UpdateStore(checker: UpdateChecker(fetchData: { data }), currentVersion: "0.2.0", isEnabled: { false })
        await current.checkNow()
        XCTAssertNil(current.available)
        XCTAssertEqual(current.manualStatus, .upToDate)
    }

    func testManualCheckReportsFailure() async {
        let store = UpdateStore(checker: UpdateChecker(fetchData: { throw URLError(.timedOut) }),
                                currentVersion: "0.1.0", isEnabled: { true })
        await store.checkNow()
        XCTAssertEqual(store.manualStatus, .failed)
        XCTAssertNil(store.available)
    }
}

final class UpdateAssetTests: XCTestCase {
    func testDecodesDmgAssetAndDigest() throws {
        let json = #"""
        {"tag_name":"v0.2.0","html_url":"https://github.com/krausv/memento/releases/tag/v0.2.0",
         "assets":[{"name":"other.zip","browser_download_url":"https://x.cz/other.zip","digest":"sha256:00"},
                   {"name":"Memento.dmg","browser_download_url":"https://github.com/krausv/memento/releases/download/v0.2.0/Memento.dmg","digest":"sha256:ABCD"}]}
        """#
        let release = try UpdateChecker.decode(Data(json.utf8))
        XCTAssertEqual(release.assetURL?.lastPathComponent, "Memento.dmg")
        XCTAssertEqual(release.sha256, "sha256:abcd")
    }

    func testReleaseWithoutAssetsStillDecodes() throws {
        let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/krausv/memento/releases/tag/v0.2.0"}"#
        let release = try UpdateChecker.decode(Data(json.utf8))
        XCTAssertNil(release.assetURL)
        XCTAssertNil(release.sha256)
    }
}

final class UpdateInstallerTests: XCTestCase {
    func testSha256MatchesKnownValue() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID()).txt")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try UpdateInstaller.sha256(of: file),
                       "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testRequirementPinsTeamAndIdentifier() {
        XCTAssertEqual(UpdateInstaller.requirement(team: "ABC123DEF4", identifier: "cz.memento.app"),
                       #"anchor apple generic and certificate leaf[subject.OU] = "ABC123DEF4" and identifier "cz.memento.app""#)
        XCTAssertFalse(UpdateInstaller.requirement(team: "ABC123DEF4", identifier: nil).contains("identifier"))
    }

    func testRelaunchScriptWaitsForPidAndQuotesPath() {
        let script = UpdateInstaller.relaunchScript(pid: 42, path: "/Applications/Mem'ento.app")
        XCTAssertTrue(script.hasPrefix("while kill -0 42"))
        XCTAssertTrue(script.hasSuffix(#"/usr/bin/open -n '/Applications/Mem'\''ento.app'"#))
    }

    func testAdHocBundleCannotBeInstalledInPlace() {
        // Testy běží v ad-hoc podepsané aplikaci bez Team ID.
        XCTAssertNil(UpdateInstaller.teamIdentifier(of: Bundle.main.bundleURL))
        XCTAssertFalse(UpdateInstaller(appURL: Bundle.main.bundleURL).canInstallInPlace)
    }

    func testSignatureCheckRejectsAdHocApp() {
        XCTAssertThrowsError(try UpdateInstaller.verifySignature(of: Bundle.main.bundleURL, team: "25PN83L22C", identifier: nil)) {
            XCTAssertEqual($0 as? UpdateInstallError, .signature)
        }
    }
}

@MainActor
final class UpdateStoreInstallTests: XCTestCase {
    private let release = ReleaseInfo(
        version: AppVersion("0.2.0")!, tagName: "v0.2.0",
        url: URL(string: "https://github.com/krausv/memento/releases/tag/v0.2.0")!,
        assetURL: URL(string: "https://github.com/krausv/memento/releases/download/v0.2.0/Memento.dmg")!, sha256: nil)

    private final class Spy: @unchecked Sendable {
        var installed: [ReleaseInfo] = []
        var opened: [URL] = []
        var quits = 0
        var failures: [String] = []
    }

    private func makeStore(spy: Spy, canInstall: Bool = true, fail: Error? = nil) async -> UpdateStore {
        let data = Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/krausv/memento/releases/tag/v0.2.0","assets":[{"name":"Memento.dmg","browser_download_url":"https://x.cz/Memento.dmg"}]}"#.utf8)
        let store = UpdateStore(
            checker: UpdateChecker(fetchData: { data }), currentVersion: "0.1.0", isEnabled: { false },
            canInstallInPlace: { canInstall },
            installAction: { release, progress in
                spy.installed.append(release)
                progress(0.5)
                if let fail { throw fail }
            },
            openPage: { spy.opened.append($0) },
            quit: { spy.quits += 1 }
        )
        store.onInstallFailure = { spy.failures.append($0) }
        await store.checkNow()
        return store
    }

    func testSuccessfulInstallQuitsApp() async {
        let spy = Spy()
        let store = await makeStore(spy: spy)
        await store.install(release)
        XCTAssertEqual(spy.installed.count, 1)
        XCTAssertEqual(spy.quits, 1)
        XCTAssertEqual(store.installState, .installing)
        XCTAssertTrue(store.isInstalling)
    }

    func testFailedInstallKeepsAppRunningAndReports() async {
        let spy = Spy()
        let store = await makeStore(spy: spy, fail: UpdateInstallError.signature)
        await store.install(release)
        XCTAssertEqual(spy.quits, 0)
        XCTAssertEqual(store.installState, .failed(UpdateInstallError.signature.localizedDescription))
        XCTAssertEqual(spy.failures.count, 1)
        XCTAssertFalse(store.isInstalling, "po chybě jde zkusit znovu")
    }

    func testStartUpdateOpensPageWhenInPlaceInstallUnavailable() async {
        let spy = Spy()
        let store = await makeStore(spy: spy, canInstall: false)
        store.startUpdate()
        XCTAssertEqual(spy.opened.map(\.absoluteString), ["https://github.com/krausv/memento/releases/tag/v0.2.0"])
        XCTAssertTrue(spy.installed.isEmpty)
    }
}
