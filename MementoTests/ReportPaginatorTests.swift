import XCTest
@testable import Memento

final class ReportPaginatorTests: XCTestCase {
    func testLongTableSplitsIntoPagesThatFit() {
        let start = Calendar.prague.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!
        let entries = (0..<120).map {
            ReportEntry(taskName: "Úkol \($0 % 7)", note: nil,
                        start: start.addingTimeInterval(Double($0) * 7200),
                        end: start.addingTimeInterval(Double($0) * 7200 + 3600))
        }
        let report = ReportBuilder().build(projectName: "P", client: nil, currency: "CZK", hourlyRate: 1000,
                                           month: ReportMonth(year: 2026, month: 10), rounding: .none, entries: entries)
        let pages = ReportPaginator.paginate(ReportPaginator.items(for: report))

        XCTAssertGreaterThan(pages.count, 1)
        for page in pages {
            XCTAssertLessThanOrEqual(page.reduce(0) { $0 + $1.height }, ReportPaginator.contentHeight)
        }
        for page in pages.dropFirst() {
            XCTAssertEqual(page.first, .detailHeader)
        }
        let rowCount = pages.flatMap { $0 }.filter { if case .detailRow = $0 { true } else { false } }.count
        XCTAssertEqual(rowCount, 120)
        XCTAssertEqual(pages.last?.last, .summary)
    }
}
