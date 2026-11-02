import AppKit
import SwiftData
import SwiftUI

enum PDFExportError: LocalizedError {
    case cannotCreate(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreate(let url): "Nepodařilo se vytvořit soubor \(url.lastPathComponent)."
        }
    }
}

@MainActor
enum PDFExporter {
    /// Vykreslí výkaz do vícestránkového A4 PDF.
    static func write(_ report: Report, supplier: ReportSupplier, to url: URL, generatedAt: Date = Date()) throws {
        let pages = ReportPaginator.paginate(ReportPaginator.items(for: report))
        var box = CGRect(origin: .zero, size: ReportPaginator.pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw PDFExportError.cannotCreate(url) }

        for (index, items) in pages.enumerated() {
            let page = ReportPageView(
                report: report, supplier: supplier, items: items,
                pageNumber: index + 1, pageCount: pages.count, generatedAt: generatedAt
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(ReportPaginator.pageSize)
            renderer.render { size, draw in
                context.beginPDFPage(nil)
                context.translateBy(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
    }

    /// Vyrobí po jednom PDF pro každý projekt. Vrací zapsané soubory.
    static func export(
        projects: [Project],
        month: ReportMonth,
        rounding: RoundingOption,
        supplier: ReportSupplier,
        to folder: URL
    ) throws -> [URL] {
        var used = Set<String>()
        var written: [URL] = []
        for project in projects {
            let entries = project.entries.compactMap { entry -> ReportEntry? in
                guard let end = entry.end else { return nil }
                return ReportEntry(note: entry.note, start: entry.start, end: end, continuesPrevious: entry.carriedSeconds > 0)
            }
            let report = ReportBuilder().build(
                projectName: project.name, client: project.client, currency: project.currency,
                hourlyRate: project.hourlyRate, month: month, rounding: rounding, entries: entries
            )
            let url = uniqueURL(in: folder, month: month, name: project.name, used: &used)
            try write(report, supplier: supplier, to: url)
            written.append(url)
        }
        return written
    }

    /// Dva projekty se stejným slugem by si přepsaly soubor – druhému se přidá číslo.
    private static func uniqueURL(in folder: URL, month: ReportMonth, name: String, used: inout Set<String>) -> URL {
        var fileName = FileNaming.reportFileName(month: month, projectName: name)
        var counter = 2
        while !used.insert(fileName).inserted {
            fileName = FileNaming.reportFileName(month: month, projectName: "\(name)-\(counter)")
            counter += 1
        }
        return folder.appendingPathComponent(fileName)
    }
}
