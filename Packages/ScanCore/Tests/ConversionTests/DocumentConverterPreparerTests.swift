import Conversion
import DocumentModel
import Foundation
import OCR
import Preprocessing
import Testing

@Suite("DocumentConverter with a page preparer")
struct DocumentConverterPreparerTests {
    @Test("recognizes the prepared pages and keeps them for review")
    func preparedPages() async throws {
        let engine = FakeEngine(pages: [
            "1.png": RecognizedPage(lines: body(["one a", "one b"])),
            "2.png": RecognizedPage(lines: body(["two a", "two b"])),
        ])
        let conversion = try await DocumentConverter(
            engine: engine, pictureExtractor: FakeExtractor(), markerLocator: FakeLocator(), inkMeasurer: FakeInk(),
            preparer: FakePreparer()
        ).analyze(
            pageURLs: ["1.png", "2.png"].map { URL(fileURLWithPath: "/pages/\($0)") },
            metadata: DocumentMetadata(title: "Prepared", author: nil, language: "en")
        )

        #expect(conversion.pageURLs.map(\.path) == ["/prepared/1.png", "/prepared/2.png"])
        #expect(conversion.document.blocks.count == 2)
    }

    @Test("a document of paper scans is laid out as print: soft hyphens at line ends are removed")
    func paperScanLayout() async throws {
        func converted(as profile: InputProfile) async throws -> [Block] {
            let engine = FakeEngine(pages: ["1.png": RecognizedPage(lines: body(["small con-", "tainers here"]))])
            return try await DocumentConverter(
                engine: engine, pictureExtractor: FakeExtractor(), markerLocator: FakeLocator(),
                inkMeasurer: FakeInk(), preparer: FakePreparer(profile: profile)
            ).analyze(
                pageURLs: [URL(fileURLWithPath: "/pages/1.png")],
                metadata: DocumentMetadata(title: "Scan", author: nil, language: "en")
            ).document.blocks
        }
        #expect(try await converted(as: .paperScan) == [.paragraph(["small containers here"])])
        #expect(try await converted(as: .cleanPage) == [.paragraph(["small con-tainers here"])])
    }
}
