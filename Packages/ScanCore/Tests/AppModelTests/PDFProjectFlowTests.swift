@testable import AppModel
import Conversion
import CoreGraphics
import DocumentModel
import Foundation
import Importing
import Testing

/// Real PDF drawing and a real project bundle; only recognition is faked.
private struct RecognitionFreePipeline: ConversionPipeline {
    private let live = LivePipeline()

    func pageURLs(in folder: URL) throws -> [URL] {
        try live.pageURLs(in: folder)
    }

    func pdfPageCount(of pdf: URL) throws -> Int {
        try live.pdfPageCount(of: pdf)
    }

    func renderPages(
        of pdf: URL, into folder: URL, progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        try await live.renderPages(of: pdf, into: folder, progress: progress)
    }

    func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        preparingPagesIn _: URL?,
        progress _: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> Conversion {
        let document = Document(metadata: metadata, chapters: [Chapter(title: "T", blocks: [.paragraph(["Text."])])])
        return Conversion(document: document, pageURLs: pageURLs)
    }

    func export(_: Document, to _: URL) async throws {}
}

@MainActor
@Suite("PDF project flow")
struct PDFProjectFlowTests {
    @Test("a PDF becomes a project that keeps its pages and reopens without the PDF")
    func projectOutlivesPDF() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SyntheticPDFForApp.write(pages: 3)
        let pdf = folder.appendingPathComponent("Document.pdf")
        try FileManager.default.moveItem(at: source, to: pdf)

        let model = ConversionModel(pipeline: RecognitionFreePipeline())
        model.open(pdf)
        #expect(model.pageCount == 3)
        model.start()
        await model.conversionTask?.value

        let bundle = folder.appendingPathComponent("Document.scanproject")
        #expect(model.project?.location?.resolvingSymlinksInPath() == bundle.resolvingSymlinksInPath())
        let pages = try FileManager.default.contentsOfDirectory(atPath: bundle.appendingPathComponent("pages").path)
        #expect(pages.sorted() == ["page-0001.png", "page-0002.png", "page-0003.png"])

        try FileManager.default.removeItem(at: pdf)
        let reopened = ConversionModel(pipeline: RecognitionFreePipeline())
        reopened.open(bundle)
        #expect(reopened.pageCount == 3)
        let urls = try #require(reopened.project?.base.pageURLs)
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(reopened.suggestedExportURL?.lastPathComponent == "Document.epub")
    }
}

/// A small PDF for the flow test.
private enum SyntheticPDFForApp {
    static func write(pages: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw CocoaError(.fileWriteUnknown) }
        var box = CGRect(x: 0, y: 0, width: 100, height: 150)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for _ in 0 ..< pages {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}
