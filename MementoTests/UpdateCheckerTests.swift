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
