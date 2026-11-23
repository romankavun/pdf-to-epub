@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import ProjectStore
import Testing

@MainActor
@Suite("ConversionModel projects")
struct ConversionModelProjectTests {
    private let storage = FakeStorage()
    private let pipeline = FakePipeline()
    private let projectURL = URL(fileURLWithPath: "/documents/Sample.scanproject")

    private func finishedModel() async -> ConversionModel {
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder: folder)
        model.start()
        await model.conversionTask?.value
        return model
    }

    @Test("a finished conversion becomes a project saved beside the folder")
    func createsProject() async {
        let model = await finishedModel()
        #expect(model.project?.location == projectURL)
        #expect(model.project?.base == fakeConversion())
        #expect(storage.created == [fakeConversion()])
        #expect(model.projectError == nil)
    }

    @Test("when the project cannot be written the document is still usable and the reason is reported")
    func projectCreationFails() async {
        storage.createFailure = StorageFailure()
        let model = await finishedModel()
        #expect(model.project?.location == nil)
        #expect(model.projectError == "disk full")
        #expect(model.phase == .finished(fakeConversion()))
    }

    @Test("the exported document has the corrections applied")
    func exportsCorrectedDocument() async {
        let model = await finishedModel()
        model.project?.replaceWord("Text", with: "Fixed")
        await model.export(to: URL(fileURLWithPath: "/tmp/Sample.epub"))
        #expect(pipeline.documents.values.first?.blocks == [.paragraph(["Fixed."])])
    }

    @Test("opening a project folder loads its document, corrections and metadata instead of converting")
    func opensProject() {
        var corrections = CorrectionSet()
        corrections.replaceWord("Text", with: "Fixed")
        var conversion = fakeConversion(title: "Saved title")
        conversion.pageURLs = threePages
        conversion.document.metadata.author = "Author"
        conversion.document.metadata.language = "en"
        storage.projects[projectURL] = Project(conversion: conversion, corrections: corrections)
        let model = ConversionModel(pipeline: pipeline, storage: storage)

        model.open(projectURL)

        #expect(model.phase == .finished(conversion))
        #expect(model.project?.location == projectURL)
        #expect(model.project?.conversion.document.blocks == [.paragraph(["Fixed."])])
        #expect(model.input?.path == folder.path)
        #expect(model.pageCount == 3)
        #expect(model.title == "Saved title" && model.author == "Author" && model.language == "en")
    }

    @Test("a project that cannot be read is reported and nothing is left open")
    func openFails() {
        storage.projects[projectURL] = nil
        let model = ConversionModel(pipeline: pipeline, storage: FailingLoadStorage())
        model.open(projectURL)
        #expect(model.phase == .failed(.other("disk full")))
        #expect(model.project == nil)
    }

    @Test("opening a plain folder through the same entry point converts as before")
    func opensFolder() {
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder)
        #expect(model.phase == .ready)
    }

    @Test("opening another folder drops the project")
    func dropsProject() async {
        let model = await finishedModel()
        model.open(folder: URL(fileURLWithPath: "/documents/Eneida"))
        #expect(model.project == nil)
        #expect(model.projectError == nil)
    }
}

@MainActor
@Suite("Projects on disk")
struct ProjectOnDiskTests {
    @Test("corrections survive closing and reopening the project, and opening the scans again finds it")
    func survivesReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scans = root.appendingPathComponent("Document")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pipeline = FakePipeline(pages: .success([scans.appendingPathComponent("1.png")]))

        let model = ConversionModel(pipeline: pipeline, storage: LiveProjectStorage())
        model.open(folder: scans)
        model.start()
        await model.conversionTask?.value
        let location = try #require(model.project?.location)
        #expect(location.lastPathComponent == "Document.scanproject")
        model.project?.replaceWord("Text", with: "Fixed")

        let reopened = ConversionModel(pipeline: pipeline, storage: LiveProjectStorage())
        reopened.open(location)
        #expect(reopened.project?.conversion.document.blocks == [.paragraph(["Fixed."])])
        #expect(reopened.project?.base.document.blocks == [.paragraph(["Text."])])

        let second = ConversionModel(pipeline: pipeline, storage: LiveProjectStorage())
        second.open(folder: scans)
        #expect(second.existingProject?.standardizedFileURL == location.standardizedFileURL)
    }
}

private struct FailingLoadStorage: ProjectPersisting {
    func isProject(at _: URL) -> Bool {
        true
    }

    func createProject(
        for _: Conversion, named _: String, in _: URL, movingPages _: Bool
    ) throws -> (location: URL, conversion: Conversion) {
        throw StorageFailure()
    }

    func load(from _: URL) throws -> Project {
        throw StorageFailure()
    }

    func save(_: CorrectionSet, to _: URL) throws {}
    func save(ignoredWords _: Set<String>, to _: URL) throws {}
    func discardProject(at _: URL) throws {}
}
