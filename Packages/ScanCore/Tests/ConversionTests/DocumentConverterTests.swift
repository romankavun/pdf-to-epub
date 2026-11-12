import Conversion
import DocumentModel
import Foundation
import OCR
import Testing

/// Returns canned pages keyed by file name instead of looking at pixels.
private struct FakeEngine: OCREngine {
    var pages: [String: RecognizedPage]

    func recognize(imageAt url: URL) async throws -> RecognizedPage {
        guard let page = pages[url.lastPathComponent] else { throw CocoaError(.fileNoSuchFile) }
        return page
    }
}

private func body(_ texts: [String], top: Double = 0.2) -> [TextLine] {
    texts.enumerated().map { index, text in
        TextLine(text: text, box: CGRect(x: index == 0 ? 0.08 : 0.05, y: top + Double(index) * 0.02, width: 0.9, height: 0.017))
    }
}

private func title(_ text: String) -> TextLine {
    TextLine(text: text, box: CGRect(x: 0.05, y: 0.1, width: 0.3, height: 0.035))
}

@Suite("DocumentConverter")
struct DocumentConverterTests {
    private let metadata = DocumentMetadata(identifier: "urn:uuid:0f8fad5b-d9cb-469f-a165-70867728950e", title: "Whole Document", author: nil, language: "uk")
    private let urls = ["1.png", "2.png", "3.png"].map { URL(fileURLWithPath: "/pages/\($0)") }
    private let engine = FakeEngine(pages: [
        "1.png": RecognizedPage(lines: body(["preface a", "preface b", "preface c"])),
        "2.png": RecognizedPage(lines: [title("Chapter One")] + body(["one a", "one b", "one c"])),
        "3.png": RecognizedPage(lines: [title("Chapter Two")] + body(["two a", "two b", "two c"])),
    ])

    @Test("recognizes every page in order and splits chapters at level 1 headings")
    func chapters() async throws {
        let document = try await DocumentConverter(engine: engine).convert(pageURLs: urls, metadata: metadata)
        #expect(document.metadata == metadata)
        #expect(document.chapters.map(\.title) == ["Whole Document", "Chapter One", "Chapter Two"])
        #expect(document.chapters[0].blocks == [.paragraph(["preface a preface b preface c"])])
        #expect(document.chapters[1].blocks == [
            .heading(level: 1, content: ["Chapter One"]),
            .paragraph(["one a one b one c"]),
        ])
    }

    @Test("a document that starts with a heading has no untitled leading chapter")
    func startsWithHeading() async throws {
        let document = try await DocumentConverter(engine: engine).convert(pageURLs: Array(urls.dropFirst()), metadata: metadata)
        #expect(document.chapters.map(\.title) == ["Chapter One", "Chapter Two"])
    }

    @Test("reports progress once per page, in order")
    func progress() async throws {
        let recorder = ProgressRecorder()
        _ = try await DocumentConverter(engine: engine).convert(pageURLs: urls, metadata: metadata) { done, total in
            recorder.record(done, total)
        }
        #expect(recorder.values == ["1/3", "2/3", "3/3"])
    }

    @Test("passes an engine failure through")
    func engineFailure() async {
        await #expect(throws: CocoaError.self) {
            try await DocumentConverter(engine: engine)
                .convert(pageURLs: [URL(fileURLWithPath: "/pages/missing.png")], metadata: metadata)
        }
    }

    @Test("stops when the task is cancelled")
    func cancellation() async {
        let task = Task {
            try await DocumentConverter(engine: engine).convert(pageURLs: urls, metadata: metadata)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ done: Int, _ total: Int) {
        lock.withLock { storage.append("\(done)/\(total)") }
    }

    var values: [String] {
        lock.withLock { storage }
    }
}
