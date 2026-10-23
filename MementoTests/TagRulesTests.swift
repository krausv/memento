import XCTest
@testable import Memento

final class TagRulesTests: XCTestCase {
    func testNormalizedTrimsAndRejectsEmpty() {
        XCTAssertEqual(TagRules.normalized("  Schůzka \n"), "Schůzka")
        XCTAssertNil(TagRules.normalized("   "))
    }

    func testSameNameIgnoresCaseAndDiacritics() {
        XCTAssertTrue(TagRules.sameName("Schůzka", "schuzka"))
        XCTAssertFalse(TagRules.sameName("Schůzka", "Vývoj"))
    }
}
