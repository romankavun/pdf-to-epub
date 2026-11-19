@testable import AppModel
import Conversion
import DocumentModel
import Foundation
import Preprocessing
import Testing

/// Real preparation of pages and a real project bundle; only recognition is
/// faked.
private struct PreparingPipeline: ConversionPipeline {
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
        preparingPagesIn preparedFolder: URL?,
        progress _: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> Conversion {
        var pages = pageURLs
        if let preparedFolder {
            let preparer = ScanPagePreparer(folder: preparedFolder)
            let profile = try preparer.profile(ofDocumentWith: pageURLs)
            pages = try pageURLs.map { try preparer.prepare(pageAt: $0, as: profile) }
        }
        let document = Document(metadata: metadata, chapters: [Chapter(title: "T", blocks: [.paragraph(["Text."])])])
        return Conversion(document: document, pageURLs: pages)
    }

    func export(_: Document, to _: URL) async throws {}
}

/// A white scanner bed with a grainy page and a few dark lines on it.
private func scanPage() -> ScanBitmap {
    var bitmap = ScanBitmap(width: 300, height: 400, gray: 255)
    for y in 100 ..< 300 {
        for x in 75 ..< 225 {
            let tone = 255 - UInt8((x * 7 + y * 13) % 5)
            let ink = x > 90 && x < 210 && (y - 115) % 12 < 6 && y < 285
            bitmap.setColor(red: ink ? 30 : tone, green: ink ? 30 : tone, blue: ink ? 30 : tone, x: x, y: y)
        }
    }
    return bitmap
}

@MainActor
@Suite("Scan project flow")
struct ScanProjectFlowTests {
    @Test("a folder of scans becomes a project that keeps the prepared pages and leaves the scans alone")
    func projectKeepsPreparedPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scans = root.appendingPathComponent("Document", isDirectory: true)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for number in 1 ... 2 {
            try #require(ScanImageFile.writePNG(scanPage(), to: scans.appendingPathComponent("scan-\(number).png")))
        }

        let model = ConversionModel(pipeline: PreparingPipeline())
        model.open(folder: scans)
        model.start()
        await model.conversionTask?.value

        let bundle = root.appendingPathComponent("Document.scanproject")
        let pages = try FileManager.default.contentsOfDirectory(atPath: bundle.appendingPathComponent("pages").path)
        #expect(pages.sorted() == ["scan-1.png", "scan-2.png"])
        let prepared = try #require(ScanImageFile.read(bundle.appendingPathComponent("pages/scan-1.png")))
        #expect(prepared.width < 200 && prepared.height < 250)
        // The originals are untouched.
        #expect(try FileManager.default.contentsOfDirectory(atPath: scans.path).sorted() == [
            "scan-1.png",
            "scan-2.png",
        ])
        #expect(ScanImageFile.read(scans.appendingPathComponent("scan-1.png")) == scanPage())

        let reopened = ConversionModel(pipeline: PreparingPipeline())
        reopened.open(bundle)
        let urls = try #require(reopened.project?.base.pageURLs)
        #expect(urls.count == 2 && urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
