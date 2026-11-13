import AppModel
import Conversion
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing

private let urls = ["1.png", "2.png", "3.png", "4.png"].map { URL(fileURLWithPath: "/pages/\($0)") }

private func box(_ y: Double) -> CGRect {
    CGRect(x: 0.05, y: y, width: 0.9, height: 0.1)
}

/// Four pages: a cover with no blocks, a clean page, and two pages with a
/// suspicious word each ("Журавeль" has a Latin "o").
private func sampleConversion() -> Conversion {
    let blocks: [Block] = [
        .heading(level: 1, content: ["Chapter"]),
        .paragraph(["Clean text", .noteReference("note-1"), " goes on."]),
        .paragraph(["He read ", .emphasis("Журавeль"), " aloud."]),
        .figure(Figure(imageID: "figure-001", alternativeText: "", caption: ["Fig. 1"])),
        .paragraph(["A сл0во here."]),
    ]
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "Chapter", blocks: blocks)],
        notes: [Note(id: "note-1", label: "7", content: ["Note."])]
    )
    return Conversion(
        document: document,
        pageURLs: urls,
        blockSources: [
            BlockSource(page: 1, box: box(0.1)), BlockSource(page: 1, box: box(0.3)),
            BlockSource(page: 2, box: box(0.1)), BlockSource(page: 2, box: box(0.3)),
            BlockSource(page: 3, box: box(0.1)),
        ]
    )
}

@MainActor
@Suite("ReviewModel")
struct ReviewModelTests {
    private let model = ReviewModel(conversion: sampleConversion())

    @Test("groups blocks under the page they start on, keeping pages without blocks")
    func pages() {
        #expect(model.pages.map(\.url) == urls)
        #expect(model.pages.map { $0.items.map(\.id) } == [
            [],
            [.block(0), .block(1)],
            [.block(2), .block(3)],
            [.block(4)],
        ])
        #expect(model.pages[1].items[0].kind == .heading(level: 1))
        #expect(model.pages[2].items[1].kind == .figure(imageID: "figure-001"))
        #expect(model.pages[2].items[0].box == box(0.1))
    }

    @Test("splits block text into runs, with note labels and flagged words")
    func runs() {
        #expect(model.pages[1].items[1].runs == [
            ReviewModel.Run(text: "Clean text"),
            ReviewModel.Run(text: "7", style: .noteReference),
            ReviewModel.Run(text: " goes on."),
        ])
        #expect(model.pages[2].items[0].runs == [
            ReviewModel.Run(text: "He read "),
            ReviewModel.Run(text: "Журавeль", style: .emphasis, reason: .mixedScript),
            ReviewModel.Run(text: " aloud."),
        ])
        #expect(model.pages[2].items[1].runs == [ReviewModel.Run(text: "Fig. 1")])
        #expect(model.pages[3].items[0].issueCount == 1)
        #expect(model.issueCount == 2)
    }

    @Test("starts on the first page with nothing selected")
    func initialState() {
        #expect(model.pageIndex == 0)
        #expect(model.selectedItemID == nil)
        #expect(model.issuePosition == nil)
    }

    @Test("moves between pages within bounds and drops the selection")
    func pageNavigation() {
        model.select(itemID: .block(2))
        #expect(model.pageIndex == 2)

        model.goToNextPage()
        #expect(model.pageIndex == 3)
        #expect(model.selectedItemID == nil)
        model.goToNextPage()
        #expect(model.pageIndex == 3)
        #expect(!model.canGoToNextPage)

        model.goToPage(0)
        model.goToPreviousPage()
        #expect(model.pageIndex == 0)
        #expect(!model.canGoToPreviousPage)
        model.goToPage(99)
        #expect(model.pageIndex == 0)
    }

    @Test("next issue walks the flagged blocks in reading order and wraps around")
    func nextIssue() {
        model.goToNextIssue()
        #expect(model.pageIndex == 2)
        #expect(model.selectedItemID == .block(2))
        #expect(model.issuePosition == 1)

        model.goToNextIssue()
        #expect(model.pageIndex == 3)
        #expect(model.selectedItemID == .block(4))
        #expect(model.issuePosition == 2)

        model.goToNextIssue()
        #expect(model.selectedItemID == .block(2))
    }

    @Test("next issue starts from the page being viewed")
    func nextIssueFromCurrentPage() {
        model.goToPage(3)

        model.goToNextIssue()
        #expect(model.selectedItemID == .block(4))

        model.goToPage(3)
        model.goToPreviousIssue()
        #expect(model.selectedItemID == .block(2))
    }

    @Test("previous issue walks backwards and wraps around")
    func previousIssue() {
        model.goToPreviousIssue()
        #expect(model.selectedItemID == .block(4))
        model.goToPreviousIssue()
        #expect(model.selectedItemID == .block(2))
    }

    @Test("a document without flagged words has no issues to visit")
    func noIssues() {
        var conversion = sampleConversion()
        conversion.document.chapters[0].blocks = [.paragraph(["Clean."])]
        conversion.blockSources = [BlockSource(page: 1, box: box(0.1))]
        let model = ReviewModel(conversion: conversion)

        model.goToNextIssue()

        #expect(model.issueCount == 0)
        #expect(model.selectedItemID == nil)
        #expect(model.pageIndex == 0)
    }

    @Test("a block that runs onto the next page is shown on both, counted once")
    func continuedBlock() {
        var conversion = sampleConversion()
        var source = BlockSource(page: 2, box: box(0.3))
        source.add(box(0.05), onPage: 3)
        conversion.blockSources[3] = source
        let model = ReviewModel(conversion: conversion)

        #expect(model.pages[3].items.map(\.id) == [.block(3), .block(4)])
        let start = model.pages[2].items[1], end = model.pages[3].items[0]
        #expect(start.box == box(0.3) && end.box == box(0.05))
        #expect(!start.continuesFromPreviousPage && start.continuesOnNextPage)
        #expect(end.continuesFromPreviousPage && !end.continuesOnNextPage)
        #expect(end.runs == start.runs)
        #expect(model.pages[2].items[0].continuesFromPreviousPage == false)
    }

    @Test("a flagged block on two pages is one issue, visited on the page it starts on")
    func continuedIssue() {
        var conversion = sampleConversion()
        var source = BlockSource(page: 2, box: box(0.1))
        source.add(box(0.0), onPage: 3)
        conversion.blockSources[2] = source
        let model = ReviewModel(conversion: conversion)

        #expect(model.issueCount == 2)
        #expect(model.flaggedItemCount == 2)
        model.goToNextIssue()
        #expect(model.pageIndex == 2 && model.selectedItemID == .block(2))
        model.goToNextIssue()
        #expect(model.pageIndex == 3 && model.selectedItemID == .block(4))
    }

    @Test("selecting the part of a block on the page being viewed stays on that page")
    func selectContinuation() {
        var conversion = sampleConversion()
        var source = BlockSource(page: 2, box: box(0.3))
        source.add(box(0.05), onPage: 3)
        conversion.blockSources[3] = source
        let model = ReviewModel(conversion: conversion)

        model.goToPage(3)
        model.select(itemID: .block(3))
        #expect(model.pageIndex == 3 && model.selectedItemID == .block(3))

        model.goToPage(0)
        model.select(itemID: .block(3))
        #expect(model.pageIndex == 2)
    }

    @Test("linked note texts are shown on their page, in place, with flagged words")
    func notes() {
        var conversion = sampleConversion()
        conversion.document.notes = [
            Note(id: "note-1", label: "7", content: ["A n0te with ", .emphasis("text"), "."]),
            Note(id: "note-2", label: "8", content: ["Clean note."]),
        ]
        conversion.noteSources = [BlockSource(page: 2, box: box(0.2)), BlockSource(page: 3, box: box(0.5))]
        let model = ReviewModel(conversion: conversion)

        #expect(model.pages[2].items.map(\.id) == [.block(2), .note("note-1"), .block(3)])
        let note = model.pages[2].items[1]
        #expect(note.kind == .note(label: "7"))
        #expect(note.box == box(0.2))
        #expect(note.runs == [
            ReviewModel.Run(text: "A "),
            ReviewModel.Run(text: "n0te", reason: .digitInsideWord),
            ReviewModel.Run(text: " with "),
            ReviewModel.Run(text: "text", style: .emphasis),
            ReviewModel.Run(text: "."),
        ])
        #expect(model.pages[3].items.map(\.id) == [.block(4), .note("note-2")])
        #expect(model.issueCount == 3)

        model.goToPage(2)
        model.goToNextIssue()
        model.goToNextIssue()
        #expect(model.selectedItemID == .note("note-1"))
        #expect(model.issuePosition == 2)
    }
}
