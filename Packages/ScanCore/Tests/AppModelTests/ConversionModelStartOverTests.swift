@testable import AppModel
import Corrections
import Foundation
import ProjectStore
import Testing

@MainActor
@Suite("ConversionModel start over")
struct ConversionModelStartOverTests {
    private let storage = FakeStorage()
    private let pipeline = FakePipeline()
    private let projectURL = URL(fileURLWithPath: "/documents/Sample.scanproject")

    /// A model with the folder open and a corrected project for it beside it.
    private func modelWithProjectBeside() -> ConversionModel {
        var corrections = CorrectionSet()
        corrections.replaceWord("Text", with: "Fixed")
        var conversion = fakeConversion()
        conversion.pageURLs = threePages
        storage.projects[projectURL] = Project(conversion: conversion, corrections: corrections)
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder: folder)
        return model
    }

    @Test("opening a folder that already has a project beside it names that project")
    func reportsExistingProject() {
        let model = modelWithProjectBeside()
        #expect(model.existingProject == projectURL)
        #expect(model.phase == .ready)
    }

    @Test("a folder without a project beside it has none to report")
    func noExistingProject() {
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder: folder)
        #expect(model.existingProject == nil)
    }

    @Test("a PDF that already has a project beside it names that project too")
    func reportsExistingProjectForPDF() {
        storage.projects[projectURL] = Project(conversion: fakeConversion())
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(pdf: URL(fileURLWithPath: "/documents/Sample.pdf"))
        #expect(model.existingProject == projectURL)
    }

    @Test("Convert does nothing while a project exists; only Start over replaces it")
    func startRefusedWithExistingProject() async {
        let model = modelWithProjectBeside()
        #expect(!model.canStart)
        model.start()
        await model.conversionTask?.value
        #expect(model.phase == .ready)
        #expect(storage.created.isEmpty)
    }

    @Test("opening the existing project loads it with its corrections")
    func opensExistingProject() {
        let model = modelWithProjectBeside()
        model.openExistingProject()
        #expect(model.project?.location == projectURL)
        #expect(model.project?.conversion.document.blocks == [.paragraph(["Fixed."])])
        #expect(model.existingProject == nil)
    }

    @Test("start over discards the existing project and its corrections, then converts into a new one")
    func startsOver() async {
        let model = modelWithProjectBeside()
        model.startOver()
        await model.conversionTask?.value
        #expect(storage.discarded == [projectURL])
        #expect(storage.created == [fakeConversion()])
        #expect(model.project?.location == projectURL)
        #expect(model.project?.corrections.isEmpty == true)
        #expect(model.existingProject == nil)
    }

    @Test("a cancelled start over leaves the existing project where it is")
    func cancelledStartOverKeepsProject() {
        let model = modelWithProjectBeside()
        model.startOver()
        model.cancel()
        #expect(storage.discarded.isEmpty)
        #expect(model.existingProject == projectURL)
        #expect(!model.canStart)
    }

    @Test("when the existing project cannot be discarded the reason is reported and the new one is still made")
    func discardFails() async {
        storage.discardFailure = StorageFailure()
        let model = modelWithProjectBeside()
        model.startOver()
        await model.conversionTask?.value
        #expect(model.startOverError == "disk full")
        #expect(model.projectError == nil)
        #expect(storage.created == [fakeConversion()])
        #expect(model.project?.corrections.isEmpty == true)
    }

    @Test("an open project cannot be converted again under its corrections")
    func openProjectCannotStart() {
        storage.projects[projectURL] = Project(conversion: fakeConversion())
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(projectURL)
        #expect(!model.canStart)
    }
}
