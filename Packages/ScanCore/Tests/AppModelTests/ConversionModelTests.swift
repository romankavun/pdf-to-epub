@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import EPUBExport
import Foundation
import Importing
import LayoutAnalysis
import ProjectStore
import Testing

let folder = URL(fileURLWithPath: "/documents/Sample")
let threePages = ["1.png", "2.png", "3.png"].map { folder.appendingPathComponent($0) }

func fakeConversion(title: String = "Sample") -> Conversion {
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: title, author: nil, language: "uk"),
        chapters: [Chapter(title: title, blocks: [.paragraph(["Text."])])]
    )
    return Conversion(document: document, unlinkedReferences: 2, unlinkedNotes: 1)
}

struct FakeFailure: Error, CustomStringConvertible {
    var description: String {
        "disk on fire"
    }
}

/// Lets a test hold the fake conversion in the middle of a document.
final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func open() {
        continuation.yield()
    }

    func wait() async {
        for await _ in stream {
            return
        }
    }
}

final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func record(_ value: Value) {
        lock.withLock { storage.append(value) }
    }

    var values: [Value] {
        lock.withLock { storage }
    }
}

struct FakePipeline: ConversionPipeline {
    var pages: Result<[URL], ImportError> = .success(threePages)
    var failure: FakeFailure?
    var exportFailure: EPUBExportError?
    /// When set, the conversion reports page `pauseAfter` and then waits.
    var gate: Gate?
    var pauseAfter = 1
    let metadata = Recorder<DocumentMetadata>()
    let exports = Recorder<URL>()
    let documents = Recorder<Document>()

    func pageURLs(in _: URL) throws -> [URL] {
        try pages.get()
    }

    func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> Conversion {
        self.metadata.record(metadata)
        if let failure {
            throw failure
        }
        for done in 1 ... pageURLs.count {
            progress(done, pageURLs.count)
            if done == pauseAfter, let gate {
                await gate.wait()
                try Task.checkCancellation()
            }
        }
        return fakeConversion(title: metadata.title)
    }

    func export(_ document: Document, to url: URL) async throws {
        if let exportFailure {
            throw exportFailure
        }
        documents.record(document)
        exports.record(url)
    }
}

/// Waits for main-actor work queued by background callbacks to land.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< 2000 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

@MainActor
@Suite("ConversionModel")
struct ConversionModelTests {
    @Test("starts with no folder and nothing to convert")
    func startsEmpty() {
        let model = ConversionModel(pipeline: FakePipeline(), storage: FakeStorage())

        #expect(model.phase == .empty)
        #expect(!model.canStart)
    }

    @Test("opening a folder counts its pages and names the document after it")
    func opensFolder() {
        let model = ConversionModel(pipeline: FakePipeline(), storage: FakeStorage())

        model.open(folder: folder)

        #expect(model.phase == .ready)
        #expect(model.folder?.path == folder.path)
        #expect(model.pageCount == 3)
        #expect(model.title == "Sample")
        #expect(model.canStart)
    }

    @Test("a folder without page images is reported, not opened")
    func rejectsFolderWithoutImages() {
        let model = ConversionModel(pipeline: FakePipeline(pages: .failure(.noImages(folder))), storage: FakeStorage())

        model.open(folder: folder)

        #expect(model.phase == .failed(.noImages))
        #expect(model.folder == nil)
        #expect(!model.canStart)
    }

    @Test("a blank title blocks the conversion: EPUB requires one")
    func blankTitleBlocksStart() {
        let model = ConversionModel(pipeline: FakePipeline(), storage: FakeStorage())
        model.open(folder: folder)

        model.title = "  "

        #expect(!model.canStart)
    }

    @Test("converts with the metadata the user entered")
    func convertsWithMetadata() async {
        let pipeline = FakePipeline()
        let model = ConversionModel(pipeline: pipeline, storage: FakeStorage())
        model.open(folder: folder)
        model.title = " Sample, 1840 "
        model.author = "  "
        model.language = "en"

        model.start()
        await model.conversionTask?.value

        #expect(model.phase == .finished(fakeConversion(title: "Sample, 1840")))
        let metadata = pipeline.metadata.values.first
        #expect(metadata?.title == "Sample, 1840")
        #expect(metadata?.author == nil)
        #expect(metadata?.language == "en")
    }

    @Test("shows how many pages are done while converting")
    func reportsProgress() async {
        let gate = Gate()
        let model = ConversionModel(pipeline: FakePipeline(gate: gate), storage: FakeStorage())
        model.open(folder: folder)

        model.start()
        #expect(model.phase == .converting(done: 0, total: 3))
        #expect(!model.canStart)
        #expect(await eventually { model.phase == .converting(done: 1, total: 3) })

        gate.open()
        await model.conversionTask?.value
        #expect(model.phase == .finished(fakeConversion()))
    }

    @Test("names the page being recognized, which is the one after the pages done")
    func pageInProgress() async {
        let gate = Gate()
        let model = ConversionModel(pipeline: FakePipeline(gate: gate), storage: FakeStorage())
        model.open(folder: folder)
        #expect(model.pageInProgress == nil)

        model.start()
        #expect(model.pageInProgress == .init(number: 1, url: threePages[0]))
        #expect(await eventually { model.pageInProgress == .init(number: 2, url: threePages[1]) })

        gate.open()
        await model.conversionTask?.value
        #expect(model.pageInProgress == nil)
    }

    @Test("once every page is recognized no page is in progress while the document is assembled")
    func noPageWhileAssembling() async {
        let gate = Gate()
        let model = ConversionModel(pipeline: FakePipeline(gate: gate, pauseAfter: 3), storage: FakeStorage())
        model.open(folder: folder)

        model.start()
        #expect(await eventually { model.phase == .converting(done: 3, total: 3) })
        #expect(model.pageInProgress == nil)

        gate.open()
        await model.conversionTask?.value
    }

    @Test("a failed conversion shows the reason")
    func reportsFailure() async {
        let model = ConversionModel(pipeline: FakePipeline(failure: FakeFailure()), storage: FakeStorage())
        model.open(folder: folder)

        model.start()
        await model.conversionTask?.value

        #expect(model.phase == .failed(.other("disk on fire")))
    }

    @Test("cancelling returns to the ready state at once and drops the late result")
    func cancels() async {
        let gate = Gate()
        let model = ConversionModel(pipeline: FakePipeline(gate: gate), storage: FakeStorage())
        model.open(folder: folder)
        model.start()
        #expect(await eventually { model.phase == .converting(done: 1, total: 3) })
        let task = model.conversionTask

        model.cancel()
        #expect(model.phase == .ready)

        gate.open()
        await task?.value
        #expect(model.phase == .ready)
        #expect(model.canStart)
    }

    @Test("exports the converted document to the chosen file")
    func exports() async {
        let pipeline = FakePipeline()
        let model = ConversionModel(pipeline: pipeline, storage: FakeStorage())
        model.open(folder: folder)
        model.start()
        await model.conversionTask?.value
        let destination = URL(fileURLWithPath: "/tmp/Sample.epub")

        await model.export(to: destination)

        #expect(pipeline.exports.values == [destination])
        #expect(model.exportResult == .saved(destination))
    }

    @Test("a failed export is reported and the document stays available")
    func reportsExportFailure() async {
        let model = ConversionModel(pipeline: FakePipeline(exportFailure: .noChapters), storage: FakeStorage())
        model.open(folder: folder)
        model.start()
        await model.conversionTask?.value

        await model.export(to: URL(fileURLWithPath: "/tmp/Sample.epub"))

        #expect(model.exportResult == .failed("noChapters"))
        #expect(model.phase == .finished(fakeConversion()))
    }

    @Test("suggests saving the EPUB next to the folder, named after it")
    func suggestsExportName() {
        let model = ConversionModel(pipeline: FakePipeline(), storage: FakeStorage())
        model.open(folder: folder)

        #expect(model.suggestedExportURL == URL(fileURLWithPath: "/documents/Sample.epub"))
    }

    @Test("opening another folder forgets the previous result")
    func reopening() async {
        let model = ConversionModel(pipeline: FakePipeline(), storage: FakeStorage())
        model.open(folder: folder)
        model.start()
        await model.conversionTask?.value
        await model.export(to: URL(fileURLWithPath: "/tmp/Sample.epub"))

        model.open(folder: URL(fileURLWithPath: "/documents/Eneida"))

        #expect(model.phase == .ready)
        #expect(model.title == "Eneida")
        #expect(model.exportResult == nil)
    }
}

@Suite("ConversionSummary")
struct ConversionSummaryTests {
    @Test("counts what the document contains and what was left unresolved")
    func counts() {
        let document = Document(
            metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
            chapters: [
                Chapter(title: "One", blocks: [.heading(level: 1, content: ["One"]), .paragraph(["A"])]),
                Chapter(title: "Two", blocks: [
                    .heading(level: 1, content: ["Two"]),
                    .heading(level: 2, content: ["Part"]),
                    .paragraph(["B", .noteReference("n1")]),
                    .figure(Figure(imageID: "figure-001", alternativeText: "")),
                ]),
            ],
            notes: [Note(id: "n1", label: "1", content: ["Note."])],
            images: [
                ImageResource(id: "cover", filename: "cover.png", mediaType: "image/png", data: Data()),
                ImageResource(id: "figure-001", filename: "figure-001.png", mediaType: "image/png", data: Data()),
            ],
            coverImageID: "cover"
        )

        let summary = ConversionSummary(Conversion(document: document, unlinkedReferences: 3, unlinkedNotes: 4))

        #expect(summary == ConversionSummary(
            chapters: 2, headings: 3, paragraphs: 2, figures: 1, notes: 1,
            hasCover: true, unlinkedReferences: 3, unlinkedNotes: 4
        ))
    }
}

@Suite("LivePipeline")
struct LivePipelineTests {
    @Test("recognizes English alongside the document's language, and alone for an English document")
    func recognitionLanguages() {
        #expect(LivePipeline.recognitionLanguages(for: "uk") == ["uk", "en-US"])
        #expect(LivePipeline.recognitionLanguages(for: "en") == ["en-US"])
        #expect(LivePipeline.recognitionLanguages(for: "en-GB") == ["en-US"])
    }
}
