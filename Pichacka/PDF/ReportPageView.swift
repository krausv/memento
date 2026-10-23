import SwiftUI

struct ReportSupplier {
    var name: String?
    var ico: String?

    var line: String? {
        let parts = [name, ico.map { "IČO: \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Jedna stránka výkazu. Vykresluje už jen hotová data z `Report`.
struct ReportPageView: View {
    let report: Report
    let supplier: ReportSupplier
    let items: [PDFItem]
    let pageNumber: Int
    let pageCount: Int
    let generatedAt: Date

    private static let columns: [CGFloat] = [70, 120, 170, 100, 55]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    view(for: item).frame(height: item.height, alignment: .top)
                }
            }
            Spacer(minLength: 0)
            footer.frame(height: ReportPaginator.footerHeight, alignment: .bottom)
        }
        .padding(.top, ReportPaginator.margin.top)
        .padding(.bottom, ReportPaginator.margin.bottom)
        .padding(.leading, ReportPaginator.margin.leading)
        .padding(.trailing, ReportPaginator.margin.trailing)
        .frame(width: ReportPaginator.pageSize.width, height: ReportPaginator.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .font(.system(size: 10))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func view(for item: PDFItem) -> some View {
        switch item {
        case .header: header
        case .sectionTitle(let title):
            Text(title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        case .taskHeader:
            tableRow([("Úkol", .leading), ("Hodiny", .trailing)], widths: [415, 100], bold: true)
        case .taskRow(let line):
            tableRow([(line.taskName, .leading), (CzFormat.hours(seconds: line.seconds), .trailing)], widths: [415, 100])
        case .detailHeader:
            tableRow(detailCells(["Datum", "Úkol", "Poznámka", "Od–do", "Trvání"]), widths: Self.columns, bold: true)
        case .detailRow(let row):
            tableRow(detailCells([
                CzFormat.date(row.start), row.taskName, row.note ?? "",
                CzFormat.timeRange(start: row.start, end: row.end), CzFormat.hours(seconds: row.seconds),
            ]), widths: Self.columns)
        case .summary: summary
        }
    }

    private func detailCells(_ texts: [String]) -> [(String, Alignment)] {
        texts.enumerated().map { ($1, $0 == texts.count - 1 ? .trailing : .leading) }
    }

    private func tableRow(_ cells: [(String, Alignment)], widths: [CGFloat], bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell.0)
                    .fontWeight(bold ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, index < cells.count - 1 ? 6 : 0)
                    .frame(width: widths[index], alignment: cell.1)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(bold ? 0.6 : 0.15)).frame(height: 0.5) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Výkaz práce").font(.system(size: 24, weight: .bold))
            Text(report.projectName).font(.system(size: 15, weight: .semibold))
            if let client = report.client, !client.isEmpty { Text("Klient: \(client)") }
            Text("Období: \(CzFormat.month(report.month))")
            if let line = supplier.line { Text("Dodavatel: \(line)") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Rectangle().fill(Color.black).frame(height: 1).padding(.bottom, 6)
            summaryLine("Celkem hodin", CzFormat.hours(seconds: report.totalSeconds))
            summaryLine("Hodinová sazba", CzFormat.money(report.hourlyRate, currency: report.currency))
            summaryLine("Celková částka", CzFormat.money(report.amount, currency: report.currency), bold: true)
        }
        .padding(.top, 16)
    }

    private func summaryLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.system(size: bold ? 14 : 11, weight: bold ? .bold : .regular))
        .frame(width: 280)
    }

    private var footer: some View {
        HStack {
            Text("Vygenerováno \(CzFormat.date(generatedAt))")
            Spacer()
            Text("Strana \(pageNumber) z \(pageCount)")
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.black.opacity(0.6))
    }
}
