import XCTest
@testable import Pichacka

final class FileNamingTests: XCTestCase {
    func testSlug() {
        XCTAssertEqual(FileNaming.slug("Digi správa"), "digi-sprava")
        XCTAssertEqual(FileNaming.slug("  Příliš žluťoučký kůň  "), "prilis-zlutoucky-kun")
        XCTAssertEqual(FileNaming.slug("A & B / C.s.r.o."), "a-b-c-s-r-o")
        XCTAssertEqual(FileNaming.slug("Projekt 2026!!!"), "projekt-2026")
        XCTAssertEqual(FileNaming.slug("???"), "projekt")
    }

    func testReportFileName() {
        XCTAssertEqual(
            FileNaming.reportFileName(month: ReportMonth(year: 2026, month: 10), projectName: "Digi správa"),
            "2026-10_digi-sprava.pdf"
        )
        XCTAssertEqual(
            FileNaming.reportFileName(month: ReportMonth(year: 2026, month: 3), projectName: "X"),
            "2026-03_x.pdf"
        )
    }
}
