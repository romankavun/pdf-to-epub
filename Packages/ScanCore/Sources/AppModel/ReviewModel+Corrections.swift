import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Observation
import TextReview

public extension ReviewModel {
    /// The longest start of a block's text shown to recognize a candidate.
    private static let candidateTextLength = 80

    // MARK: - Corrections

    var canUndo: Bool {
        project.canUndo
    }

    /// Takes back the last correction.
    func undo() {
        guard project.canUndo else { return }
        cancelEditing()
        proposal = nil
        project.undo()
        rebuild()
    }

    /// Gives the selected block a type. A note has none, and a figure can
    /// only be ignored. When a paragraph and a heading are swapped, similar
    /// blocks are offered the same change in ``proposal``.
    func setSelectedType(_ type: BlockType) {
        guard let item = selectedItem else { return }
        switch item.kind {
        case .note: return
        case .figure where type != .ignored: return
        default: break
        }
        cancelEditing()
        proposal = nil
        project.setType(type, for: item.anchor)
        rebuild()
        guard type != .ignored, let before = item.textType, before != type else { return }
        let candidates = project.similarBlocks(like: item.anchor, thatAre: before).map(candidate)
        if !candidates.isEmpty {
            proposal = .type(type, candidates: candidates)
        }
    }

    /// Gives the selected block the type it was recognized with, which for
    /// an ignored block brings it back into the document.
    func resetSelectedType() {
        guard let item = selectedItem, !item.kind.isNote else { return }
        cancelEditing()
        proposal = nil
        project.resetType(for: item.anchor)
        rebuild()
    }

    /// The blocks offered by a type proposal; empty for any other.
    var proposalCandidates: [Candidate] {
        if case let .type(_, candidates) = proposal {
            candidates
        } else {
            []
        }
    }

    /// Applies the proposed type to the blocks in `chosen`, as one step to
    /// undo, and ends the proposal.
    func acceptTypeProposal(for chosen: Set<BlockAnchor>) {
        guard case let .type(type, candidates) = proposal else { return }
        proposal = nil
        let anchors = candidates.map(\.anchor).filter(chosen.contains)
        guard !anchors.isEmpty else { return }
        project.setType(type, for: anchors)
        rebuild()
    }

    /// Replaces the proposed word everywhere, as one step to undo, and ends
    /// the proposal.
    func acceptWordProposal() {
        guard case let .word(find, replacement, _) = proposal else { return }
        proposal = nil
        project.replaceWord(find, with: replacement)
        rebuild()
    }

    func dismissProposal() {
        proposal = nil
    }

    // MARK: Editing text

    var isEditing: Bool {
        editingItemID != nil
    }

    /// Opens the selected block or note text for editing, with ``draft`` set
    /// to its text. A block left out of the document cannot be edited.
    func beginEditing() {
        guard let item = selectedItem, item.kind != .ignored else { return }
        draft = item.editableText
        editingItemID = item.id
    }

    func cancelEditing() {
        editingItemID = nil
    }

    /// Records ``draft`` as the text of the block being edited. Nothing is
    /// recorded when the text did not change. When the change is one fixed
    /// word that stands elsewhere too, replacing it everywhere is offered in
    /// ``proposal``.
    func commitEditing() {
        guard let id = editingItemID, let item = currentPage?.items.first(where: { $0.id == id }) else {
            editingItemID = nil
            return
        }
        editingItemID = nil
        let old = item.canonicalText
        let new = String(editorText: draft)
        guard new != old else { return }
        proposal = nil
        project.setText(new, for: item.anchor)
        rebuild()
        if let change = WordReplacement.singleWordChange(from: old, to: new) {
            let count = WordReplacement.occurrences(of: change.old, in: project.conversion)
            if count > 0 {
                proposal = .word(find: change.old, replacement: change.new, occurrences: count)
            }
        }
    }

    internal func candidate(_ anchor: BlockAnchor) -> Candidate {
        let text = pages.indices.contains(anchor.page)
            ? pages[anchor.page].items.first { $0.anchor == anchor }?.runs.map(\.text).joined() ?? ""
            : ""
        return Candidate(anchor: anchor, page: anchor.page, text: String(text.prefix(Self.candidateTextLength)))
    }
}
