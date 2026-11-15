import Conversion
import DocumentModel
import Foundation
import LayoutAnalysis

/// A block the user chose to leave out of the document, kept so the review can
/// show it and let the user bring it back.
public struct IgnoredBlock: Sendable, Equatable {
    public var block: Block
    public var source: BlockSource
}

/// A conversion with the user's corrections applied.
public struct CorrectedConversion: Sendable, Equatable {
    /// The document as it should be exported. Blocks, notes and their sources
    /// stay aligned with each other.
    public var conversion: Conversion
    /// Blocks of the original conversion that are ignored, in document order.
    public var ignored: [IgnoredBlock]
    /// Corrections that found nothing to act on, because the block is gone
    /// or its text changed since the correction was made.
    public var unapplied: [Correction]
}

/// Everything the user decided about a document, in the order they decided it.
///
/// A value type: undo is keeping an earlier copy. Mutators keep at most one
/// type and one edit per block, and one replacement per word, so the set
/// always describes the latest decision.
public struct CorrectionSet: Sendable, Codable, Equatable {
    public internal(set) var corrections: [Correction]

    public init(corrections: [Correction] = []) {
        self.corrections = corrections
    }

    public var isEmpty: Bool {
        corrections.isEmpty
    }

    /// The type the user gave the block at `anchor`, or `nil` when they left
    /// it as recognized.
    public func type(for anchor: BlockAnchor) -> BlockType? {
        for case let .retype(other, type) in corrections where other.matches(anchor) {
            return type
        }
        return nil
    }

    /// Whether the user changed the text of the block or note at `anchor`.
    public func hasEdit(for anchor: BlockAnchor) -> Bool {
        corrections.contains { correction in
            if case let .edit(other, _, _) = correction {
                other.matches(anchor)
            } else {
                false
            }
        }
    }

    public mutating func setType(_ type: BlockType, for anchor: BlockAnchor) {
        resetType(for: anchor)
        corrections.append(.retype(anchor, to: type))
    }

    /// Gives the block back the type it was recognized with.
    public mutating func resetType(for anchor: BlockAnchor) {
        corrections.removeAll { correction in
            if case let .retype(other, _) = correction {
                other.matches(anchor)
            } else {
                false
            }
        }
    }

    /// Records that the block or note at `anchor`, whose text currently reads
    /// `original`, now reads `edited`. When the block was already edited, the
    /// first original is kept, because that is the automatic text the
    /// edit is checked against; an edit back to it removes the correction.
    public mutating func setText(from original: String, to edited: String, for anchor: BlockAnchor) {
        var automatic = original
        corrections.removeAll { correction in
            guard case let .edit(other, from, _) = correction, other.matches(anchor) else { return false }
            automatic = from
            return true
        }
        if edited != automatic {
            corrections.append(.edit(anchor, from: automatic, to: edited))
        }
    }

    public mutating func replaceWord(_ word: String, with replacement: String) {
        corrections.removeAll { correction in
            if case let .replaceWord(other, _) = correction {
                other == word
            } else {
                false
            }
        }
        corrections.append(.replaceWord(word, with: replacement))
    }

    /// Applies the corrections to `conversion`, the output of the pipeline.
    ///
    /// Merges and splits come first, in the order they were made, so that
    /// every other correction finds the blocks as they are in the document.
    /// Per block, an edit comes next and then the type, so the type applies
    /// to the edited text; word replacements come last and reach every
    /// block and note, edited or not. Chapters are cut again from the
    /// resulting blocks, and notes that lost their last reference are
    /// dropped along with their sources.
    public func applying(to conversion: Conversion) -> CorrectedConversion {
        guard !corrections.isEmpty else {
            return CorrectedConversion(conversion: conversion, ignored: [], unapplied: [])
        }
        let structure = structure(of: conversion)
        let conversion = structure.conversion
        var run = Run(corrections: corrections, applied: structure.applied)
        var result = conversion
        let corrected = run.correctedBlocks(of: conversion)
        var blocks = corrected.blocks
        var notes = run.correctedNotes(of: conversion)
        run.replaceWords(in: &blocks, and: &notes)

        // A note whose only references were in ignored or edited-away text
        // goes with them; a note that nothing referred to before stays.
        let referencedBefore = Set(conversion.document.blocks.flatMap(\.referencedNoteIDs))
        let referencedNow = Set(blocks.flatMap(\.referencedNoteIDs))
        let keep = notes.map { !referencedBefore.contains($0.id) || referencedNow.contains($0.id) }
        if conversion.noteSources.count == notes.count {
            result.noteSources = zip(conversion.noteSources, keep).filter(\.1).map(\.0)
        }
        result.document.notes = zip(notes, keep).filter(\.1).map(\.0)
        result.document.chapters = Chapter.chapters(from: blocks, fallbackTitle: conversion.document.metadata.title)
        if corrected.sources.count == blocks.count {
            result.blockSources = corrected.sources
        }
        let unapplied = corrections.enumerated().filter { !run.applied.contains($0.offset) }.map(\.element)
        return CorrectedConversion(conversion: result, ignored: corrected.ignored, unapplied: unapplied)
    }
}

/// The blocks of a conversion after their edits and types.
private struct CorrectedBlocks {
    var blocks: [Block]
    /// Aligned with ``blocks``; empty when the blocks could not be located.
    var sources: [BlockSource]
    var ignored: [IgnoredBlock]
}

/// The state of one pass over a conversion: which corrections found their
/// target.
private struct Run {
    let corrections: [Correction]
    var applied: Set<Int>

    /// The blocks of `conversion` with edits and types applied, their
    /// sources, and the blocks that were left out.
    ///
    /// Without a source for every block nothing can be located: the blocks
    /// come back unchanged and no sources are returned.
    mutating func correctedBlocks(
        of conversion: Conversion
    ) -> CorrectedBlocks {
        let originals = conversion.document.blocks
        guard conversion.blockSources.count == originals.count else {
            return CorrectedBlocks(blocks: originals, sources: [], ignored: [])
        }
        var blocks: [Block] = []
        var sources: [BlockSource] = []
        var ignored: [IgnoredBlock] = []
        for (original, source) in zip(originals, conversion.blockSources) {
            if let block = corrected(original, at: source) {
                blocks.append(block)
                sources.append(source)
            } else {
                ignored.append(IgnoredBlock(block: original, source: source))
            }
        }
        return CorrectedBlocks(blocks: blocks, sources: sources, ignored: ignored)
    }

    /// The notes of `conversion` with the edits applied.
    mutating func correctedNotes(of conversion: Conversion) -> [Note] {
        var notes = conversion.document.notes
        guard conversion.noteSources.count == notes.count else { return notes }
        for index in notes.indices {
            notes[index].content = edited(notes[index].content, at: conversion.noteSources[index])
        }
        return notes
    }

    /// Applies every word replacement to the text of all blocks and notes.
    mutating func replaceWords(in blocks: inout [Block], and notes: inout [Note]) {
        for (number, correction) in corrections.enumerated() {
            guard case let .replaceWord(word, replacement) = correction else { continue }
            applied.insert(number)
            blocks = blocks.map { $0.replacingContent($0.content.replacingWord(word, with: replacement)) }
            for index in notes.indices {
                notes[index].content = notes[index].content.replacingWord(word, with: replacement)
            }
        }
    }

    /// `original` with its edit and type, or `nil` when it is ignored.
    private mutating func corrected(_ original: Block, at source: BlockSource) -> Block? {
        let block = original.replacingContent(edited(original.content, at: source))
        guard let (number, type) = type(at: source) else { return block }
        switch block.retyped(as: type) {
        case let .block(retyped):
            applied.insert(number)
            return retyped
        case .ignored:
            applied.insert(number)
            return nil
        case .rejected:
            return block
        }
    }

    /// `content` with the edit for the block at `source`, if there is one
    /// whose original text still matches.
    private mutating func edited(_ content: [Inline], at source: BlockSource) -> [Inline] {
        for (number, correction) in corrections.enumerated() {
            guard case let .edit(anchor, from, to) = correction, anchor.matches(source),
                  content.canonicalText == from else { continue }
            applied.insert(number)
            return content.replacingText(with: to)
        }
        return content
    }

    /// The first type chosen for the block at `source`, with the number of
    /// the correction that chose it.
    private func type(at source: BlockSource) -> (Int, BlockType)? {
        for (number, correction) in corrections.enumerated() {
            if case let .retype(anchor, type) = correction, anchor.matches(source) {
                return (number, type)
            }
        }
        return nil
    }
}

extension Block {
    enum Retyped {
        case block(Block)
        case ignored
        /// A figure has no text to set as a heading or paragraph.
        case rejected
    }

    func replacingContent(_ content: [Inline]) -> Block {
        switch self {
        case let .heading(level, _): .heading(level: level, content: content)
        case .paragraph: .paragraph(content)
        case var .figure(figure):
            {
                figure.caption = content
                return .figure(figure)
            }()
        }
    }

    func retyped(as type: BlockType) -> Retyped {
        switch (type, self) {
        case (.ignored, _): .ignored
        case (_, .figure): .rejected
        case (.paragraph, _): .block(.paragraph(content))
        case let (.heading(level), _): .block(.heading(level: min(max(level, 1), 6), content: content))
        }
    }
}

extension [Inline] {
    /// The content with every whole word `word` in text runs replaced. A
    /// word is whole when no letter, digit or apostrophe touches it.
    func replacingWord(_ word: String, with replacement: String) -> [Inline] {
        map { inline in
            switch inline {
            case let .text(text): .text(text.replacingWholeWord(word, with: replacement))
            case let .emphasis(text): .emphasis(text.replacingWholeWord(word, with: replacement))
            case let .strong(text): .strong(text.replacingWholeWord(word, with: replacement))
            case .noteReference: inline
            }
        }
    }
}

extension String {
    func replacingWholeWord(_ word: String, with replacement: String) -> String {
        guard !word.isEmpty else { return self }
        func isWordCharacter(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber || "'’ʼ".contains(character)
        }
        var result = ""
        var copied = startIndex
        var searchFrom = startIndex
        while let range = range(of: word, range: searchFrom ..< endIndex) {
            let before = range.lowerBound > startIndex ? self[index(before: range.lowerBound)] : nil
            let after = range.upperBound < endIndex ? self[range.upperBound] : nil
            if !isWordCharacter(before), !isWordCharacter(after) {
                result += self[copied ..< range.lowerBound] + replacement
                copied = range.upperBound
            }
            searchFrom = range.upperBound
        }
        return result + self[copied...]
    }
}
