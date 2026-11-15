import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Observation
import ProjectStore

/// A document being worked on: the conversion as the pipeline produced it and
/// the user's corrections on top of it.
///
/// The model keeps the two apart on purpose. The corrected conversion is
/// derived from them after every change, so converting again only replaces
/// the base and the corrections apply to the new one. Corrections are
/// written to the project folder after each change, so closing the app
/// loses nothing.
@MainActor
@Observable
public final class ProjectModel {
    /// The project folder; `nil` for a document that is not saved anywhere, whose
    /// corrections live in memory only.
    public let location: URL?
    /// What the pipeline produced, without corrections.
    public private(set) var base: Conversion
    public private(set) var corrections: CorrectionSet
    /// The document with the corrections applied: what is reviewed and exported.
    public private(set) var conversion: Conversion
    /// Blocks the user left out of the document.
    public private(set) var ignored: [IgnoredBlock] = []
    /// Words the review no longer flags, lowercased. Kept in the project
    /// beside the corrections but not part of them: not undone, and not
    /// affected by converting again.
    public private(set) var ignoredWords: Set<String>
    /// Corrections that found nothing to act on in the current base, for the
    /// user to know about after converting again.
    public private(set) var unapplied: [Correction] = []
    /// Why the last write to disk failed, or `nil` when it succeeded.
    public private(set) var saveError: String?

    /// Earlier states of the corrections, newest last.
    private var history: [CorrectionSet] = []
    /// States taken back by undo, newest last; emptied by any new change.
    private var undone: [CorrectionSet] = []
    private let storage: any ProjectPersisting

    public init(
        base: Conversion,
        corrections: CorrectionSet = CorrectionSet(),
        ignoredWords: Set<String> = [],
        location: URL? = nil,
        storage: any ProjectPersisting = LiveProjectStorage()
    ) {
        self.base = base
        self.corrections = corrections
        self.ignoredWords = ignoredWords
        self.location = location
        self.storage = storage
        conversion = base
        recompute()
    }

    public var canUndo: Bool {
        !history.isEmpty
    }

    public var canRedo: Bool {
        !undone.isEmpty
    }

    // MARK: - Changes

    /// Gives the block at `anchor` a type.
    public func setType(_ type: BlockType, for anchor: BlockAnchor) {
        setType(type, for: [anchor])
    }

    /// Gives every block at `anchors` a type, as one step to undo.
    public func setType(_ type: BlockType, for anchors: [BlockAnchor]) {
        change { set in
            for anchor in anchors {
                set.setType(type, for: anchor)
            }
        }
    }

    /// Gives the block back the type it was recognized with.
    public func resetType(for anchor: BlockAnchor) {
        change { $0.resetType(for: anchor) }
    }

    /// Sets the text of the block or note at `anchor`. `text` is in the
    /// canonical form (note references as placeholders).
    public func setText(_ text: String, for anchor: BlockAnchor) {
        guard let automatic = automaticText(at: anchor) else { return }
        change { $0.setText(from: automatic, to: text, for: anchor) }
    }

    /// Replaces every whole word `word` in the document with `replacement`.
    public func replaceWord(_ word: String, with replacement: String) {
        change { $0.replaceWord(word, with: replacement) }
    }

    /// Merges the block at `second`, which must follow the block at `first`,
    /// into it: one block with the text of both and the type of the first.
    /// Edits to either are carried over. Returns whether the merge was
    /// possible; both must be headings or paragraphs and neighbours in the
    /// document as it stands.
    @discardableResult
    public func merge(_ first: BlockAnchor, with second: BlockAnchor) -> Bool {
        guard let head = structuredText(at: first), let tail = structuredText(at: second) else { return false }
        var updated = corrections
        updated.merge(first, with: second, texts: (head, tail))
        guard !updated.applying(to: base).unapplied.contains(.merge(first, with: second)) else { return false }
        commit(updated)
        return true
    }

    /// Whether the block at `anchor`, which shows `text`, can be split by a
    /// position in that text: it has to be recognized text as it is, because
    /// the position is only meaningful there. A block the user edited or
    /// whose words a replacement rule changed cannot be split.
    public func canSplit(_ anchor: BlockAnchor, showing text: String) -> Bool {
        !corrections.hasEdit(for: anchor) && structuredText(at: anchor) == text
    }

    /// Cuts the block at `anchor`, which shows `text`, in two after `offset`
    /// characters of it (the split correction). Returns whether
    /// the block could be split.
    @discardableResult
    public func split(_ anchor: BlockAnchor, at offset: Int, of text: String) -> Bool {
        guard canSplit(anchor, showing: text) else { return false }
        var updated = corrections
        updated.split(anchor, at: offset, of: text)
        guard !updated.applying(to: base).unapplied.contains(.split(anchor, at: offset, of: text)) else {
            return false
        }
        commit(updated)
        return true
    }

    /// Stops flagging `word`, in any case, and saves the list.
    public func ignoreWord(_ word: String) {
        let lowered = word.lowercased()
        guard !ignoredWords.contains(lowered) else { return }
        ignoredWords.insert(lowered)
        guard let location else { return }
        do {
            try storage.save(ignoredWords: ignoredWords, to: location)
            saveError = nil
        } catch {
            saveError = String(describing: error)
        }
    }

    /// Takes back the last change.
    public func undo() {
        guard let previous = history.popLast() else { return }
        undone.append(corrections)
        corrections = previous
        recompute()
        persist()
    }

    /// Brings back the change taken back last by ``undo()``.
    public func redo() {
        guard let next = undone.popLast() else { return }
        history.append(corrections)
        corrections = next
        recompute()
        persist()
    }

    /// Puts a newly converted document under the corrections: the same document
    /// converted again, with the corrections the user made before. What no
    /// longer applies is listed in ``unapplied``. Undo history starts over,
    /// because it refers to the old conversion.
    public func replaceBase(_ conversion: Conversion) {
        base = conversion
        history = []
        undone = []
        recompute()
        guard let location else { return }
        do {
            try storage.replaceConversion(in: location, with: conversion)
            saveError = nil
        } catch {
            saveError = String(describing: error)
        }
    }

    // MARK: - Questions

    /// The blocks that look like the one at `anchor` and are currently of
    /// type `type`, which the user has not decided about themselves. Used to
    /// offer a correction for them after the user made it for one block.
    public func similarBlocks(like anchor: BlockAnchor, thatAre type: BlockType) -> [BlockAnchor] {
        guard let source = conversion.blockSources.first(where: { anchor.matches($0) }) else { return [] }
        return SimilarBlocks.anchors(like: source, ofType: type, in: conversion)
            .filter { corrections.type(for: $0) == nil }
    }

    // MARK: - Internals

    /// The text of the block or note at `anchor` before any correction.
    private func automaticText(at anchor: BlockAnchor) -> String? {
        structuredText(at: anchor)
    }

    /// The text of the block at `anchor` after merges and splits but before
    /// edits and types.
    private func structuredText(at anchor: BlockAnchor) -> String? {
        let structured = corrections.structured(from: base)
        if structured.blockSources.count == structured.document.blocks.count,
           let index = structured.blockSources.firstIndex(where: { anchor.matches($0) })
        {
            return structured.document.blocks[index].textContent.canonicalText
        }
        if structured.noteSources.count == structured.document.notes.count,
           let index = structured.noteSources.firstIndex(where: { anchor.matches($0) })
        {
            return structured.document.notes[index].content.canonicalText
        }
        return nil
    }

    private func change(_ edit: (inout CorrectionSet) -> Void) {
        var updated = corrections
        edit(&updated)
        commit(updated)
    }

    private func commit(_ updated: CorrectionSet) {
        guard updated != corrections else { return }
        history.append(corrections)
        undone = []
        corrections = updated
        recompute()
        persist()
    }

    private func recompute() {
        let result = corrections.applying(to: base)
        conversion = result.conversion
        ignored = result.ignored
        unapplied = result.unapplied
    }

    private func persist() {
        guard let location else { return }
        do {
            try storage.save(corrections, to: location)
            saveError = nil
        } catch {
            saveError = String(describing: error)
        }
    }
}

private extension Block {
    var textContent: [Inline] {
        switch self {
        case let .heading(_, content), let .paragraph(content): content
        case let .figure(figure): figure.caption
        }
    }
}
