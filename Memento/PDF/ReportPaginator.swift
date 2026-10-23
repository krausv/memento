import CoreGraphics
import Foundation

/// Prvek PDF s pevnou výškou. Díky pevným výškám jde tabulku rozdělit na stránky bez měření layoutu.
enum PDFItem: Equatable {
    case header
    case sectionTitle(String)
    case detailHeader
    case detailRow(Report.Row)
    case summary

    var height: CGFloat {
        switch self {
        case .header: 130
        case .sectionTitle: 34
        case .detailHeader: 22
        case .detailRow(let row): Self.rowHeight(forNote: row.note)
        case .summary: 110
        }
    }
}

extension PDFItem {
    /// Odhad výšky řádku s víceřádkovou poznámkou; počítá konzervativně, aby se text neořízl.
    static func rowHeight(forNote note: String?) -> CGFloat {
        let charsPerLine = 48
        let lines = (note ?? "").components(separatedBy: .newlines)
            .reduce(0) { $0 + max(1, ($1.count + charsPerLine - 1) / charsPerLine) }
        return max(20, 8 + 12.5 * CGFloat(max(lines, 1)))
    }
}

enum ReportPaginator {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin = Margins(top: 36, leading: 40, bottom: 36, trailing: 40)
    static let footerHeight: CGFloat = 24
    static var contentHeight: CGFloat { pageSize.height - margin.top - margin.bottom - footerHeight }

    struct Margins { let top, leading, bottom, trailing: CGFloat }

    static func items(for report: Report) -> [PDFItem] {
        var items: [PDFItem] = [.header, .sectionTitle("Detail záznamů"), .detailHeader]
        items += report.rows.map(PDFItem.detailRow)
        items.append(.summary)
        return items
    }

    static func paginate(_ items: [PDFItem]) -> [[PDFItem]] {
        var pages: [[PDFItem]] = [[]]
        var used: CGFloat = 0

        func newPage() {
            pages.append([])
            used = 0
        }

        var index = 0
        while index < items.count {
            let item = items[index]
            // Nadpis sekce a hlavička tabulky nesmí zůstat osamocené na konci stránky.
            var needed = item.height
            switch item {
            case .sectionTitle: needed += (items[safe: index + 1]?.height ?? 0) + (items[safe: index + 2]?.height ?? 0)
            case .detailHeader: needed += items[safe: index + 1]?.height ?? 0
            default: break
            }
            if used + needed > contentHeight, used > 0 { newPage() }

            // Detail tabulky pokračující na další stránce dostane znovu hlavičku.
            if used == 0, case .detailRow = item {
                pages[pages.count - 1].append(.detailHeader)
                used += PDFItem.detailHeader.height
            }
            pages[pages.count - 1].append(item)
            used += item.height
            index += 1
        }
        return pages
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
