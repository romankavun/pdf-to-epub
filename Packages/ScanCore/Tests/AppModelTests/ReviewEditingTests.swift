@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing

@MainActor
@Suite("ReviewModel editing")
struct ReviewEditingTests {
    private let storage = FakeStorage()
    private let location = URL(fileURLWithPath: "/projects/Document.scanproject")

    private func review() -> ReviewModel {
        ReviewModel(project: ProjectModel(base: projectConversion(), location: location, storage: storage))
    }

    private func item(_ id: ReviewModel.ItemID, in model: ReviewModel) -> ReviewModel.Item? {
        model.pages.flatMap(\.items).first { $0.id == id }
    }

    @Test("items carry the anchor of the block they come from")
    func anchors() {
        let model = review()
        #expect(item(.block(0), in: model)?.anchor == BlockAnchor(projectConversion().blockSources[0]))
        #expect(item(.note("note-1"), in: model)?.anchor == BlockAnchor(projectConversion().noteSources[0]))
    }

    // MARK: Types

    @Test("changing the type of the selected block shows at once, keeps the selection and is saved")
    func retype() {
        let model = review()
        model.select(itemID: .block(1))
        model.setSelectedType(.heading(level: 2))
        #expect(item(.block(1), in: model)?.kind == .heading(level: 2))
        #expect(model.selectedItemID == .block(1))
        #expect(storage.saved.count == 1)
    }

    @Test("after a block becomes a heading, similar paragraphs are offered with their text and page")
    func typeProposal() {
        let model = review()
        model.select(itemID: .block(0))
        model.setSelectedType(.heading(level: 2))
        let sources = projectConversion().blockSources
        #expect(model.proposal == .type(.heading(level: 2), candidates: [
            ReviewModel.Candidate(anchor: BlockAnchor(sources[3]), page: 1, text: "Title two"),
        ]))
    }

    @Test("accepting applies the type to the chosen blocks only, as one step")
    func acceptType() {
        let model = review()
        model.select(itemID: .block(0))
        model.setSelectedType(.heading(level: 2))
        model.acceptTypeProposal(for: [])
        #expect(item(.block(3), in: model)?.kind == .paragraph)
        #expect(model.proposal == nil)

        model.select(itemID: .block(0))
        model.setSelectedType(.paragraph)
        model.setSelectedType(.heading(level: 2))
        model.acceptTypeProposal(for: Set(model.proposalCandidates.map(\.anchor)))
        #expect(item(.block(3), in: model)?.kind == .heading(level: 2))
        #expect(model.proposal == nil)
        model.undo()
        #expect(item(.block(3), in: model)?.kind == .paragraph)
        #expect(item(.block(0), in: model)?.kind == .heading(level: 2))
    }

    @Test("dismissing drops the offer and changes nothing")
    func dismiss() {
        let model = review()
        model.select(itemID: .block(0))
        model.setSelectedType(.heading(level: 2))
        model.dismissProposal()
        #expect(model.proposal == nil)
        #expect(item(.block(3), in: model)?.kind == .paragraph)
    }

    @Test("ignoring a block is not offered to similar ones")
    func noProposalForIgnore() {
        let model = review()
        model.select(itemID: .block(0))
        model.setSelectedType(.ignored)
        #expect(model.proposal == nil)
    }

    @Test("an ignored block stays in the review, marked, and can be restored")
    func ignoreAndRestore() {
        let model = review()
        model.select(itemID: .block(1))
        model.setSelectedType(.ignored)
        #expect(model.project.conversion.document.blocks.count == 4)
        let ignored = model.pages[0].items.first { $0.kind == .ignored }
        #expect(ignored?.id == .ignored(0))
        #expect(ignored?.runs.map(\.text).joined() == "Body 7 text.")
        #expect(model.pages[0].items.map(\.id) == [.block(0), .ignored(0)])
        // The selection follows the block, so it can be restored at once.
        #expect(model.selectedItemID == .ignored(0))

        model.select(itemID: .ignored(0))
        model.resetSelectedType()
        #expect(item(.block(1), in: model)?.kind == .paragraph)
        #expect(model.project.conversion.document.blocks.count == 5)
    }

    @Test("a note text has no type to change")
    func noteType() {
        let model = review()
        model.select(itemID: .note("note-1"))
        model.setSelectedType(.heading(level: 1))
        #expect(model.project.corrections.isEmpty)
    }

    // MARK: Text

    @Test("editing starts from the text with note references in brackets")
    func beginEditing() {
        let model = review()
        model.select(itemID: .block(1))
        model.beginEditing()
        #expect(model.isEditing)
        #expect(model.draft == "Body ⟦7⟧ text.")
    }

    @Test("committing a fixed word updates the text and the flags, and offers the fix for the rest of the document")
    func commitEdit() {
        let model = review()
        #expect(model.issueCount == 2)
        model.select(itemID: .block(2))
        model.beginEditing()
        model.draft = "Журавель is here."
        model.commitEditing()
        #expect(!model.isEditing)
        #expect(item(.block(2), in: model)?.issueCount == 0)
        #expect(model.issueCount == 1)
        #expect(model.proposal == .word(find: "Журавeль", replacement: "Журавель", occurrences: 1))

        model.acceptWordProposal()
        #expect(model.issueCount == 0)
        #expect(model.proposal == nil)
        #expect(model.project.corrections.corrections.contains(.replaceWord("Журавeль", with: "Журавель")))
    }

    @Test("an edit that is not one fixed word is not offered as a rule")
    func noWordProposal() {
        let model = review()
        model.select(itemID: .block(2))
        model.beginEditing()
        model.draft = "Something else entirely."
        model.commitEditing()
        #expect(model.proposal == nil)
    }

    @Test("an edit keeps the note reference that it does not touch")
    func editKeepsReference() {
        let model = review()
        model.select(itemID: .block(1))
        model.beginEditing()
        model.draft = "Body ⟦7⟧ words."
        model.commitEditing()
        #expect(model.project.conversion.document.blocks[1] == .paragraph(["Body ", .noteReference("note-1"), " words."]))
    }

    @Test("a note text can be edited")
    func editNote() {
        let model = review()
        model.select(itemID: .note("note-1"))
        model.beginEditing()
        model.draft = "Note, fixed."
        model.commitEditing()
        #expect(model.project.conversion.document.notes[0].content == ["Note, fixed."])
    }

    @Test("cancelling or committing the unchanged text changes nothing")
    func cancelEditing() {
        let model = review()
        model.select(itemID: .block(2))
        model.beginEditing()
        model.draft = "Changed"
        model.cancelEditing()
        #expect(!model.isEditing)
        #expect(model.project.corrections.isEmpty)

        model.beginEditing()
        model.commitEditing()
        #expect(model.project.corrections.isEmpty)
        #expect(storage.saved.isEmpty)
    }

    @Test("an ignored block cannot be edited, and moving elsewhere ends an edit")
    func editingLimits() {
        let model = review()
        model.select(itemID: .block(1))
        model.setSelectedType(.ignored)
        model.select(itemID: .ignored(0))
        model.beginEditing()
        #expect(!model.isEditing)

        model.select(itemID: .block(0))
        model.beginEditing()
        model.goToNextPage()
        #expect(!model.isEditing)
    }

    @Test("undo takes back the last change and keeps the selection when the block is still there")
    func undo() {
        let model = review()
        model.select(itemID: .block(0))
        model.setSelectedType(.heading(level: 2))
        model.dismissProposal()
        #expect(model.canUndo)
        model.undo()
        #expect(item(.block(0), in: model)?.kind == .paragraph)
        #expect(model.selectedItemID == .block(0))
        #expect(!model.canUndo)
    }
}
