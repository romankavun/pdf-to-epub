@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Styles
import Testing

private func area(_ top: Double, height: Double = 0.1) -> CGRect {
    CGRect(x: 0.1, y: top, width: 0.8, height: height)
}

private let bodyStyle = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
private let titleStyle = BlockStyle(
    rule: .largerThanText, lineHeight: 1.6, ink: 1, alignment: .centered, width: 0.4
)
private let subtitleStyle = BlockStyle(rule: .bodySizeBold, ink: 1.5, alignment: .margin, width: 0.3)
private let noteStyle = BlockStyle(rule: .noteText, lineHeight: 0.6, ink: 1, lineCount: 2, opensWithNoteLabel: true)
private let pageNumberStyle = BlockStyle(rule: .pageNumber, alignment: .centered, width: 0.05, zone: .bottom)

/// Twelve pages. Page 0: a title and a paragraph; page 1: five paragraphs;
/// page 2: a subtitle and a paragraph; pages 3 to 11: one paragraph each.
/// A note text on page 3, a page number on pages 1 to 11.
///
/// Blocks: 0 title, 1 paragraph (page 0), 2-6 paragraphs (page 1), 7
/// subtitle, 8 paragraph (page 2), 9-17 paragraphs (pages 3-11).
func styledConversion(styles: Bool = true) -> Conversion {
    var placed: [(Block, BlockStyle, BlockSource)] = [
        (.heading(level: 1, content: ["Title"]), titleStyle, BlockSource(page: 0, box: area(0.05))),
        (.paragraph(["Opening."]), bodyStyle, BlockSource(page: 0, box: area(0.3))),
    ]
    for (index, top) in [0.1, 0.3, 0.5, 0.7, 0.85].enumerated() {
        placed.append((.paragraph([.text("Busy \(index).")]), bodyStyle, BlockSource(page: 1, box: area(top))))
    }
    placed.append((.heading(level: 2, content: ["Part"]), subtitleStyle, BlockSource(page: 2, box: area(0.05))))
    placed.append((.paragraph(["Second."]), bodyStyle, BlockSource(page: 2, box: area(0.3))))
    for page in 3 ... 11 {
        placed.append((.paragraph([.text("Page \(page).")]), bodyStyle, BlockSource(page: page, box: area(0.3))))
    }
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "en"),
        chapters: [Chapter(title: "T", blocks: placed.map(\.0))],
        notes: [Note(id: "note-1", label: "1", content: ["A note."])]
    )
    let furniture = (1 ... 11).map { page in
        PageFurniture(
            area: PageArea(page: page, box: CGRect(x: 0.48, y: 0.96, width: 0.04, height: 0.02)),
            text: "\(page + 1)", style: pageNumberStyle
        )
    }
    return Conversion(
        document: document,
        pageURLs: (0 ... 11).map { URL(fileURLWithPath: "/p/\($0).png") },
        blockSources: placed.map(\.2),
        noteSources: [BlockSource(page: 3, box: area(0.9, height: 0.04))],
        styles: styles
            ? BlockStyles(blocks: placed.map(\.1), notes: [noteStyle], pageFurniture: furniture)
            : nil
    )
}

@MainActor
@Suite("ReviewModel styles")
struct ReviewStylesTests {
    private let storage = FakeStorage()

    private func review(styles: Bool = true) -> ReviewModel {
        ReviewModel(project: ProjectModel(base: styledConversion(styles: styles), storage: storage))
    }

    private func style(_ type: StyleType, in model: ReviewModel) throws -> Style {
        try #require(model.styles?.first { $0.type == type })
    }

    private func item(_ id: ReviewModel.ItemID, in model: ReviewModel) throws -> ReviewModel.Item {
        try #require(model.pages.flatMap(\.items).first { $0.id == id })
    }

    // MARK: The sidebar

    @Test("a project saved without styles has none, and cannot show them")
    func versionOne() throws {
        let model = review(styles: false)
        #expect(model.styles == nil)
        #expect(model.styleSections.isEmpty)
        model.showsStyles = true
        #expect(!model.showsStyles)
        #expect(try model.style(of: item(.block(1), in: model)) == nil)
    }

    @Test("styles are grouped by type: headings by level, paragraphs, note texts, page furniture")
    func sections() {
        let model = review()
        #expect(model.styleSections.map(\.type) == [
            .heading(level: 1), .heading(level: 2), .paragraph, .note, .pageFurniture,
        ])
        #expect(model.styleSections.map { $0.styles.map(\.members.count) } == [[1], [1], [16], [1], [11]])
    }

    @Test("the sidebar is off when the review opens, and hiding it drops the selected style")
    func toggle() throws {
        let model = review()
        #expect(!model.showsStyles)
        #expect(model.selectedStyle == nil)
        model.showsStyles = true
        try model.selectStyle(style(.paragraph, in: model).id)
        #expect(model.selectedStyle?.type == .paragraph)
        #expect(model.isShowingStyle)
        model.showsStyles = false
        #expect(model.selectedStyle == nil)
        #expect(!model.isShowingStyle)
        model.showsStyles = true
        #expect(model.selectedStyle == nil)
    }

    @Test("selecting a style closes the editor, deselecting brings back the block list")
    func selectStyle() throws {
        let model = review()
        model.select(itemID: .block(0))
        model.beginEditing()
        model.showsStyles = true
        try model.selectStyle(style(.paragraph, in: model).id)
        #expect(!model.isEditing)
        model.selectStyle(nil)
        #expect(!model.isShowingStyle)
    }

    // MARK: Block to style

    @Test("every block, note text and ignored block has the style it was recognized with")
    func styleOfItem() throws {
        let model = review()
        #expect(try model.style(of: item(.block(0), in: model))?.type == .heading(level: 1))
        #expect(try model.style(of: item(.block(9), in: model))?.type == .paragraph)
        #expect(try model.style(of: item(.note("note-1"), in: model))?.type == .note)

        model.select(itemID: .block(9))
        model.setSelectedType(.ignored)
        let ignored = try #require(model.pages.flatMap(\.items).first { $0.kind == .ignored })
        #expect(model.style(of: ignored)?.type == .paragraph)
        model.select(itemID: .block(0))
        model.setSelectedType(.paragraph)
        #expect(try model.style(of: item(.block(0), in: model))?.type == .heading(level: 1))
        #expect(model.styleSections.map(\.type).first == .heading(level: 1))
    }

    @Test("the button on a selected block opens the sidebar on its style")
    func showStyleOfItem() throws {
        let model = review()
        try model.showStyle(of: item(.block(7), in: model))
        #expect(model.showsStyles)
        #expect(model.selectedStyle?.type == .heading(level: 2))
    }

    // MARK: Corrections

    @Test("a style counts its corrected blocks, and their examples carry a mark")
    func corrected() throws {
        let model = review()
        let paragraphs = try style(.paragraph, in: model)
        #expect(model.correctedCount(of: paragraphs) == 0)

        model.goToPage(4)
        model.select(itemID: .block(10))
        model.setSelectedType(.heading(level: 3))
        model.goToPage(9)
        model.select(itemID: .block(15))
        model.setSelectedType(.ignored)
        #expect(model.correctedCount(of: paragraphs) == 2)
        let marks = Dictionary(uniqueKeysWithValues: model.examples(of: paragraphs).map { ($0.member, $0.mark) })
        #expect(marks[.block(10)] == .corrected)
        #expect(marks[.block(15)] == .ignored)
        #expect(marks[.block(1)] == .some(nil))

        model.undo()
        model.undo()
        #expect(model.correctedCount(of: paragraphs) == 0)
    }

    @Test("an edited text and a merge count as corrections of the blocks they touch")
    func editsAndMerges() throws {
        let model = review()
        model.goToPage(1)
        model.select(itemID: .block(2))
        model.mergeSelectedWithNext()
        #expect(try model.correctedCount(of: style(.paragraph, in: model)) == 2)
        model.goToPage(3)
        model.select(itemID: .note("note-1"))
        model.beginEditing()
        model.draft = "A better note."
        model.commitEditing()
        #expect(try model.correctedCount(of: style(.note, in: model)) == 1)
    }

    // MARK: Examples

    @Test("six examples from pages spread across the document, then all of them")
    func examples() throws {
        let model = review()
        let paragraphs = try style(.paragraph, in: model)
        let examples = model.examples(of: paragraphs)
        #expect(examples.map(\.member) == [.block(1), .block(8), .block(10), .block(13), .block(15), .block(17)])
        #expect(examples.map(\.page) == [0, 2, 4, 7, 9, 11])
        #expect(examples.first?.box == area(0.3))
        #expect(model.examples(of: paragraphs, limit: nil).count == 16)
    }

    @Test("no two examples from one page while another page still has one")
    func spreadOverFewPages() {
        #expect(ReviewModel.spread(pages: [1, 1, 1, 1, 1, 2, 2, 2], count: 6) == [0, 1, 2, 5, 6, 7])
        #expect(ReviewModel.spread(pages: [3, 3, 4], count: 6) == [0, 1, 2])
        #expect(ReviewModel.spread(pages: Array(0 ..< 12), count: 6) == [0, 2, 4, 7, 9, 11])
        #expect(ReviewModel.spread(pages: [], count: 6).isEmpty)
    }

    @Test("page furniture has examples too, at its own place")
    func furnitureExamples() throws {
        let model = review()
        let numbers = try style(.pageFurniture, in: model)
        let examples = model.examples(of: numbers)
        #expect(examples.count == 6)
        #expect(examples.first?.page == 1)
        #expect(examples.first?.box == CGRect(x: 0.48, y: 0.96, width: 0.04, height: 0.02))
    }

    @Test("pages are given as ranges, counting from 1")
    func pageRanges() {
        #expect(ReviewModel.pageRanges([0, 1, 2, 5, 7, 8]) == [1 ... 3, 6 ... 6, 8 ... 9])
        #expect(ReviewModel.pageRanges([]).isEmpty)
    }

    // MARK: Outlines and crops

    @Test("the selected style's blocks on the page in view are outlined, page furniture included")
    func outlines() throws {
        let model = review()
        #expect(model.styleOutlines == nil)
        model.showsStyles = true
        model.goToPage(1)
        try model.selectStyle(style(.paragraph, in: model).id)
        #expect(model.styleOutlines?.itemIDs == [.block(2), .block(3), .block(4), .block(5), .block(6)])
        #expect(model.styleOutlines?.furniture == [])
        try model.selectStyle(style(.pageFurniture, in: model).id)
        #expect(model.styleOutlines?.itemIDs == [])
        #expect(model.styleOutlines?.furniture == [CGRect(x: 0.48, y: 0.96, width: 0.04, height: 0.02)])
    }

    @Test("opening an example goes to its page, selects its block and leaves the style")
    func openExample() throws {
        let model = review()
        model.showsStyles = true
        let paragraphs = try style(.paragraph, in: model)
        model.selectStyle(paragraphs.id)
        let example = try #require(model.examples(of: paragraphs).first { $0.member == .block(13) })
        model.open(example)
        #expect(model.pageIndex == 7)
        #expect(model.selectedItemID == .block(13))
        #expect(model.selectedStyle == nil)
        #expect(model.showsStyles)
    }

    @Test("an example of a block merged into the one before opens the merged block")
    func openMergedExample() throws {
        let model = review()
        model.goToPage(1)
        model.select(itemID: .block(2))
        model.mergeSelectedWithNext()
        let paragraphs = try style(.paragraph, in: model)
        let example = try #require(model.examples(of: paragraphs, limit: nil).first { $0.member == .block(3) })
        model.goToPage(0)
        model.open(example)
        #expect(model.pageIndex == 1)
        #expect(model.selectedItemID == .block(2))
    }

    @Test("an example of page furniture shows its page with nothing selected")
    func openFurnitureExample() throws {
        let model = review()
        let example = try #require(try model.examples(of: style(.pageFurniture, in: model)).last)
        model.open(example)
        #expect(model.pageIndex == example.page)
        #expect(model.selectedItemID == nil)
    }

    // MARK: Wording

    @Test("a style's features are what sets it apart from body text")
    func features() throws {
        let model = review()
        #expect(try ReviewModel.features(of: style(.heading(level: 1), in: model)) == [.taller(1.6), .centered])
        #expect(try ReviewModel.features(of: style(.heading(level: 2), in: model)) == [.heavier])
        #expect(try ReviewModel.features(of: style(.paragraph, in: model)) == [.indented, .fullWidth, .lines(5)])
        #expect(try ReviewModel.features(of: style(.note, in: model)) == [
            .smaller(0.6), .fullWidth, .lines(2), .opensWithNoteLabel,
        ])
        #expect(try ReviewModel.features(of: style(.pageFurniture, in: model)) == [.centered, .bottomEdge])
    }
}
