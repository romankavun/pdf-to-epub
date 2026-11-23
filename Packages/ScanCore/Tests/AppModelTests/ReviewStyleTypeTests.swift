@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import Foundation
import Styles
import Testing

/// Changing the type of a whole style (style overview, slice 4), on the
/// fixture of ``ReviewStylesTests``: 16 paragraphs (blocks 1-6, 8-17), a
/// heading 1, a heading 2, a note text and page numbers.
@MainActor
@Suite("ReviewModel change type by style")
struct ReviewStyleTypeTests {
    private let storage = FakeStorage()

    private func review() -> ReviewModel {
        let model = ReviewModel(project: ProjectModel(base: styledConversion(), storage: storage))
        model.showsStyles = true
        return model
    }

    private func style(_ type: StyleType, in model: ReviewModel) throws -> Style {
        try #require(model.styles?.first { $0.type == type })
    }

    /// The type the user gave recognized block `index`, or `nil`.
    private func decided(_ index: Int, in model: ReviewModel) -> BlockType? {
        model.project.corrections.type(for: BlockAnchor(model.project.base.blockSources[index]))
    }

    private static let paragraphs = [1, 2, 3, 4, 5, 6] + Array(8 ... 17)

    @Test("a text style can be changed to the other text types or ignored; figures only ignored")
    func choices() throws {
        let model = review()
        #expect(try model.typeChoices(for: style(.paragraph, in: model)) == [
            .heading(level: 1), .heading(level: 2), .heading(level: 3), .ignored,
        ])
        #expect(try model.typeChoices(for: style(.heading(level: 2), in: model)) == [
            .paragraph, .heading(level: 1), .heading(level: 3), .ignored,
        ])
        #expect(try model.typeChoices(for: style(.note, in: model)).isEmpty)
        #expect(try model.typeChoices(for: style(.pageFurniture, in: model)).isEmpty)
    }

    @Test("every block of the style gets the type, as one correction each and one step to undo")
    func changeAll() throws {
        let model = review()
        let paragraphs = try style(.paragraph, in: model)
        model.selectStyle(paragraphs.id)
        let before = model.project.corrections.corrections.count

        let change = model.changeType(of: paragraphs, to: .heading(level: 2))

        #expect(change == ReviewModel.StyleTypeChange(
            style: paragraphs.id, type: .heading(level: 2), changed: 16, skipped: 0
        ))
        #expect(model.styleTypeChange == change)
        #expect(model.project.corrections.corrections.count == before + 16)
        #expect(Self.paragraphs.allSatisfy { decided($0, in: model) == .heading(level: 2) })
        #expect(model.project.conversion.document.blocks.allSatisfy {
            if case .heading = $0 {
                true
            } else {
                false
            }
        })
        // The style stays, from recognition, and counts its blocks as corrected.
        #expect(model.selectedStyle == paragraphs)
        #expect(model.correctedCount(of: paragraphs) == 16)

        model.undo()
        #expect(Self.paragraphs.allSatisfy { decided($0, in: model) == nil })
        #expect(model.styleTypeChange == nil)
        model.redo()
        #expect(Self.paragraphs.allSatisfy { decided($0, in: model) == .heading(level: 2) })
    }

    @Test("ignoring a style leaves all its blocks out, marked as ignored")
    func ignoreAll() throws {
        let model = review()
        let paragraphs = try style(.paragraph, in: model)
        model.changeType(of: paragraphs, to: .ignored)
        #expect(model.project.ignored.count == 16)
        #expect(model.examples(of: paragraphs, limit: nil).allSatisfy { $0.mark == .ignored })
        #expect(model.styles?.contains(paragraphs) == true)
    }

    @Test("blocks the user already gave a type are left as they are, and counted as skipped")
    func skipsDecided() throws {
        let model = review()
        model.goToPage(3)
        model.select(itemID: .block(9))
        model.setSelectedType(.heading(level: 3))
        model.dismissProposal()
        model.goToPage(4)
        model.select(itemID: .block(10))
        model.setSelectedType(.ignored)

        let change = try model.changeType(of: style(.paragraph, in: model), to: .heading(level: 2))

        #expect(change.changed == 14)
        #expect(change.skipped == 2)
        #expect(decided(9, in: model) == .heading(level: 3))
        #expect(decided(10, in: model) == .ignored)
        #expect(decided(11, in: model) == .heading(level: 2))
    }

    @Test("blocks that merges and splits changed are no longer as recognized, and are skipped")
    func skipsMergedAndSplit() throws {
        let model = review()
        model.goToPage(1)
        model.select(itemID: .block(2))
        model.mergeSelectedWithNext()
        model.goToPage(3)
        let split = try #require(model.currentPage?.items.first { $0.runs.map(\.text).joined() == "Page 3." })
        model.select(itemID: split.id)
        model.beginEditing()
        model.splitEditing(atDraftOffset: 4)

        let change = try model.changeType(of: style(.paragraph, in: model), to: .heading(level: 2))

        #expect(change.changed == 13)
        #expect(change.skipped == 3)
        #expect(decided(2, in: model) == nil)
        #expect(decided(3, in: model) == nil)
        #expect(decided(9, in: model) == nil)
        #expect(decided(1, in: model) == .heading(level: 2))
    }

    @Test("a later change to one block is a later correction and wins")
    func laterWins() throws {
        let model = review()
        try model.changeType(of: style(.paragraph, in: model), to: .heading(level: 2))
        model.goToPage(3)
        model.select(itemID: .block(9))
        model.setSelectedType(.paragraph)
        #expect(decided(9, in: model) == .paragraph)
        #expect(decided(10, in: model) == .heading(level: 2))
    }

    @Test("with every block skipped nothing is recorded")
    func nothingToChange() throws {
        let model = review()
        let heading = try style(.heading(level: 1), in: model)
        model.select(itemID: .block(0))
        model.setSelectedType(.heading(level: 3))
        model.dismissProposal()
        let corrections = model.project.corrections

        let change = model.changeType(of: heading, to: .paragraph)

        #expect(change.changed == 0)
        #expect(change.skipped == 1)
        #expect(model.project.corrections == corrections)
    }

    @Test("a type the style cannot take changes nothing")
    func refused() throws {
        let model = review()
        let notes = try style(.note, in: model)
        let change = model.changeType(of: notes, to: .paragraph)
        #expect(change.changed == 0)
        #expect(model.project.corrections.isEmpty)
    }

    @Test("the report of a change goes away when another style is selected")
    func reportCleared() throws {
        let model = review()
        let paragraphs = try style(.paragraph, in: model)
        model.selectStyle(paragraphs.id)
        model.changeType(of: paragraphs, to: .heading(level: 3))
        #expect(model.styleTypeChange != nil)
        try model.selectStyle(style(.note, in: model).id)
        #expect(model.styleTypeChange == nil)
    }
}
