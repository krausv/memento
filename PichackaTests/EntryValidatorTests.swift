import XCTest
@testable import Pichacka

final class EntryValidatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    private let existing = UUID()

    private func others() -> [EntryInterval] {
        [EntryInterval(id: existing, start: at(60), end: at(120))]
    }

    func testEndMustBeAfterStart() {
        XCTAssertThrowsError(try EntryValidator.validate(start: at(10), end: at(10), existing: [])) {
            XCTAssertEqual($0 as? EntryValidationError, .endNotAfterStart)
        }
        XCTAssertThrowsError(try EntryValidator.validate(start: at(10), end: at(5), existing: [])) {
            XCTAssertEqual($0 as? EntryValidationError, .endNotAfterStart)
        }
    }

    func testOverlapIsRejected() {
        for (s, e) in [(30.0, 90.0), (90.0, 150.0), (70.0, 100.0), (30.0, 150.0)] {
            XCTAssertThrowsError(try EntryValidator.validate(start: at(s), end: at(e), existing: others()), "\(s)–\(e)") {
                XCTAssertEqual($0 as? EntryValidationError, .overlap)
            }
        }
    }

    func testAdjacentEntriesAreAllowed() {
        XCTAssertNoThrow(try EntryValidator.validate(start: at(0), end: at(60), existing: others()))
        XCTAssertNoThrow(try EntryValidator.validate(start: at(120), end: at(180), existing: others()))
    }

    func testEditingIgnoresItself() {
        XCTAssertNoThrow(try EntryValidator.validate(start: at(70), end: at(100), editing: existing, existing: others()))
    }

    func testRunningEntryCountsUntilNow() {
        let running = [EntryInterval(id: UUID(), start: at(60), end: nil)]
        XCTAssertThrowsError(try EntryValidator.validate(start: at(70), end: at(80), existing: running, now: at(100)))
        XCTAssertNoThrow(try EntryValidator.validate(start: at(110), end: at(120), existing: running, now: at(100)))
    }
}
