import XCTest
@testable import Memento

final class BulletTextTests: XCTestCase {
    func testCleanDropsEmptyBulletsAndWhitespace() {
        XCTAssertNil(BulletText.clean("• "))
        XCTAssertNil(BulletText.clean("  \n• \n"))
        XCTAssertEqual(BulletText.clean("• první\n• druhý\n• "), "• první\n• druhý")
    }

    func testRowHeightGrowsWithNoteLength() {
        XCTAssertEqual(PDFItem.rowHeight(forNote: nil), 20.5, accuracy: 0.01)
        XCTAssertGreaterThan(PDFItem.rowHeight(forNote: "• a\n• b\n• c"), PDFItem.rowHeight(forNote: "• a"))
    }
}
