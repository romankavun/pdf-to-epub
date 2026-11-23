@testable import AppModel
import Conversion
import Foundation
import Importing
import ProjectStore
import Testing

private let pdf = URL(fileURLWithPath: "/documents/Sample.pdf")

@MainActor
@Suite("ConversionModel PDF")
struct ConversionModelPDFTests {
    private let storage = FakeStorage()

    @Test("opening a PDF counts its pages and names the document after the file without its extension")
    func opensPDF() {
        let model = ConversionModel(pipeline: FakePipeline(), storage: storage)

        model.open(pdf)

        #expect(model.phase == .ready)
        #expect(model.input == pdf)
        #expect(model.pageCount == 3)
        #expect(model.title == "Sample")
        #expect(model.canStart)
        #expect(model.suggestedExportURL == URL(fileURLWithPath: "/documents/Sample.epub"))
    }

    @Test("a PDF that cannot be read or is locked is reported, not opened")
    func rejectsBadPDF() {
        let unreadable = ConversionModel(
            pipeline: FakePipeline(pdfPages: .failure(.unreadable(pdf))), storage: storage
        )
        unreadable.open(pdf)
        #expect(unreadable.phase == .failed(.pdfUnreadable))
        #expect(unreadable.input == nil)

        let locked = ConversionModel(
            pipeline: FakePipeline(pdfPages: .failure(.passwordRequired(pdf))), storage: storage
        )
        locked.open(pdf)
        #expect(locked.phase == .failed(.pdfPasswordRequired))

        let empty = ConversionModel(pipeline: FakePipeline(pdfPages: .failure(.noPages(pdf))), storage: storage)
        empty.open(pdf)
        #expect(empty.phase == .failed(.pdfNoPages))
    }

    @Test("converting renders the pages first, then recognizes the rendered files")
    func rendersThenConverts() async {
        let pipeline = FakePipeline()
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(pdf)

        model.start()
        #expect(model.phase == .rendering(done: 0, total: 3))
        await model.conversionTask?.value

        #expect(model.phase == .finished(fakeConversion()))
        #expect(pipeline.renderedInto.values.count == 1)
    }

    @Test("the project is named after the PDF, stored beside it and takes the rendered pages")
    func projectBesidePDF() async {
        let model = ConversionModel(pipeline: FakePipeline(echoPages: true), storage: storage)
        model.open(pdf)

        model.start()
        await model.conversionTask?.value

        let detail = storage.createdDetail.first
        #expect(detail?.name == "Sample")
        #expect(detail?.parent.path == "/documents")
        #expect(detail?.movingPages == true)
        let location = URL(fileURLWithPath: "/documents/Sample.scanproject")
        #expect(model.project?.location == location)
        #expect(model.project?.base.pageURLs.first?.path == "/documents/Sample.scanproject/pages/page-0001.png")
    }

    @Test("cancelling while the pages are drawn returns to ready and removes the drawn pages")
    func cancelDuringRendering() async throws {
        let gate = Gate()
        let pipeline = FakePipeline(renderGate: gate)
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(pdf)

        model.start()
        #expect(await eventually { model.phase == .rendering(done: 1, total: 3) })
        let staging = try #require(pipeline.renderedInto.values.first)
        #expect(FileManager.default.fileExists(atPath: staging.path))
        model.cancel()
        gate.open()
        await model.conversionTask?.value

        #expect(model.phase == .ready)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(storage.created.isEmpty)
    }

    @Test("a PDF that cannot be drawn fails the conversion and leaves no files")
    func renderFailure() async throws {
        let pipeline = FakePipeline(renderFailure: .cannotRender(pdf, page: 2))
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(pdf)

        model.start()
        await model.conversionTask?.value

        #expect(model.phase == .failed(.other(String(describing: PDFImportError.cannotRender(pdf, page: 2)))))
        let staging = try #require(pipeline.renderedInto.values.first)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("a project that came from a PDF is named after itself")
    func projectFromPDF() {
        let location = URL(fileURLWithPath: "/documents/Sample.scanproject")
        var conversion = fakeConversion()
        conversion.pageURLs = (1 ... 2).map { location.appendingPathComponent("pages/page-000\($0).png") }
        storage.projects[location] = Project(conversion: conversion)
        let pipeline = FakePipeline()
        let model = ConversionModel(pipeline: pipeline, storage: storage)

        model.open(location)
        #expect(model.suggestedExportURL == URL(fileURLWithPath: "/documents/Sample.epub"))
    }
}
