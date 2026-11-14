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

    // MARK: Merging and splitting

    /// Whether the selected block and the one after it in the document are both
    /// headings or paragraphs, so that they can be merged.
    var canMergeSelectedWithNext: Bool {
        mergePair() != nil
    }

    /// Merges the block after the selected one into it: one block with both
    /// texts and the selected block's type. Undo splits them back as they
    /// were.
    func mergeSelectedWithNext() {
        guard let (first, second) = mergePair() else { return }
        cancelEditing()
        proposal = nil
        project.merge(first, with: second)
        rebuild()
    }

    /// Whether the block being edited can be split at a position of the
    /// text: its text has to be as recognized and unchanged in the editor.
    var canSplitEditing: Bool {
        guard let item = editingItem, item.textType != nil else { return false }
        return draft == item.editableText && project.canSplit(item.anchor, showing: item.canonicalText)
    }

    /// Cuts the block being edited in two after the first `offset`
    /// characters of the editor's text, which is where the user put the
    /// cursor. The spaces at the cut are dropped; each part can then get a
    /// type of its own. The first part stays selected.
    func splitEditing(atDraftOffset offset: Int) {
        guard canSplitEditing, let item = editingItem else { return }
        let canonicalOffset = String(editorText: String(draft.prefix(offset))).count
        cancelEditing()
        proposal = nil
        guard project.split(item.anchor, at: canonicalOffset, of: item.canonicalText) else { return }
        rebuild()
        let sources = project.conversion.blockSources
        if let index = sources.firstIndex(where: {
            $0.page == item.anchor.page && abs($0.box.minY - item.anchor.box.minY) < 0.0001
        }) {
            select(itemID: .block(index))
        }
    }

    private var editingItem: Item? {
        currentPage?.items.first { $0.id == editingItemID }
    }

    private func mergePair() -> (BlockAnchor, BlockAnchor)? {
        guard case let .block(index) = selectedItemID else { return nil }
        let blocks = project.conversion.document.blocks
        let sources = project.conversion.blockSources
        guard blocks.indices.contains(index + 1), sources.count == blocks.count,
              blocks[index].isText, blocks[index + 1].isText else { return nil }
        return (BlockAnchor(sources[index]), BlockAnchor(sources[index + 1]))
    }

    internal func candidate(_ anchor: BlockAnchor) -> Candidate {
        let text = pages.indices.contains(anchor.page)
            ? pages[anchor.page].items.first { $0.anchor == anchor }?.runs.map(\.text).joined() ?? ""
            : ""
        return Candidate(anchor: anchor, page: anchor.page, text: String(text.prefix(Self.candidateTextLength)))
    }
}

private extension Block {
    var isText: Bool {
        if case .figure = self {
            false
        } else {
            true
        }
    }
}
