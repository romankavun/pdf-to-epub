import Conversion
import CoreGraphics
import DocumentModel
import LayoutAnalysis

public extension CorrectionSet {
    /// Records that the block at `first` takes in the block that follows it,
    /// at `second`.
    ///
    /// `texts` are the canonical texts of the two blocks as the pipeline
    /// produced them (after earlier merges and splits). Edits made to either
    /// block are carried over as one edit of the merged block, so nothing the
    /// user fixed is lost; the type of `second` is dropped, because the merged
    /// block has the type of `first`.
    mutating func merge(_ first: BlockAnchor, with second: BlockAnchor, texts: (first: String, second: String)) {
        let firstEdit = removeEdit(at: first)
        let secondEdit = removeEdit(at: second)
        resetType(for: second)
        corrections.append(.merge(first, with: second))
        guard firstEdit != nil || secondEdit != nil else { return }
        let head = firstEdit ?? (texts.first, texts.first)
        let tail = secondEdit ?? (texts.second, texts.second)
        corrections.append(.edit(first, from: head.from + " " + tail.from, to: head.to + " " + tail.to))
    }

    /// Records that the block at `anchor`, whose text as the pipeline
    /// produced it is `text`, is cut after `offset` characters of that text.
    ///
    /// The type and the edit the block had are dropped: they described the
    /// block as a whole, and the user's `offset` is a position in its
    /// recognized text.
    mutating func split(_ anchor: BlockAnchor, at offset: Int, of text: String) {
        resetType(for: anchor)
        _ = removeEdit(at: anchor)
        corrections.append(.split(anchor, at: offset, of: text))
    }

    /// The conversion with only the merges and splits applied: the blocks as
    /// edits and types see them. Text that is edited later is compared
    /// against the text of these blocks.
    func structured(from conversion: Conversion) -> Conversion {
        structure(of: conversion).conversion
    }
}

extension CorrectionSet {
    private mutating func removeEdit(at anchor: BlockAnchor) -> (from: String, to: String)? {
        var removed: (from: String, to: String)?
        corrections.removeAll { correction in
            guard case let .edit(other, from, to) = correction, other.matches(anchor) else { return false }
            removed = removed ?? (from, to)
            return true
        }
        return removed
    }

    /// Applies the merges and splits in order, giving the blocks, sources
    /// and the numbers of the corrections that found their blocks.
    ///
    /// Without a source for every block nothing can be located and the
    /// conversion comes back as it was.
    func structure(of conversion: Conversion) -> (conversion: Conversion, applied: Set<Int>) {
        var blocks = conversion.document.blocks
        var sources = conversion.blockSources
        var notes = conversion.document.notes
        var noteSources = conversion.noteSources
        var applied = Set<Int>()
        guard sources.count == blocks.count else { return (conversion, applied) }
        for (number, correction) in corrections.enumerated() {
            switch correction {
            case let .merge(first, second):
                guard let index = sources.firstIndex(where: first.matches), index + 1 < blocks.count,
                      second.matches(sources[index + 1]),
                      let merged = blocks[index].merged(with: blocks[index + 1]) else { continue }
                var source = sources[index]
                source.continuations += sources[index + 1].areas
                blocks.replaceSubrange(index ... index + 1, with: [merged])
                sources.replaceSubrange(index ... index + 1, with: [source])
                applied.insert(number)
            case let .split(anchor, offset, text):
                if !sources.contains(where: anchor.matches), noteSources.count == notes.count,
                   let index = noteSources.firstIndex(where: anchor.matches),
                   notes[index].content.canonicalText == text,
                   let parts = notes[index].content.splitting(atCanonicalOffset: offset)
                {
                    // The rest of a note text is not a note: it goes among the
                    // blocks, where its place on the page puts it.
                    let places = noteSources[index].split(atFraction: Double(offset) / Double(text.count))
                    notes[index].content = parts.first
                    noteSources[index] = places.first
                    let position = sources.firstIndex { places.second.isBefore($0) } ?? sources.count
                    blocks.insert(.paragraph(parts.second), at: position)
                    sources.insert(places.second, at: position)
                    applied.insert(number)
                    continue
                }
                guard let index = sources.firstIndex(where: anchor.matches),
                      let content = blocks[index].splittableContent, content.canonicalText == text,
                      let parts = content.splitting(atCanonicalOffset: offset) else { continue }
                let units = Double(text.count)
                let places = sources[index].split(atFraction: Double(offset) / units)
                blocks.replaceSubrange(index ... index, with: [
                    blocks[index].replacingContent(parts.first), blocks[index].replacingContent(parts.second),
                ])
                sources.replaceSubrange(index ... index, with: [places.first, places.second])
                applied.insert(number)
            default:
                continue
            }
        }
        var result = conversion
        result.document.chapters = Chapter.chapters(from: blocks, fallbackTitle: conversion.document.metadata.title)
        result.blockSources = sources
        result.document.notes = notes
        result.noteSources = noteSources
        return (result, applied)
    }
}

private extension Block {
    /// The text of a heading or paragraph; `nil` for a figure.
    var splittableContent: [Inline]? {
        switch self {
        case let .heading(_, content), let .paragraph(content): content
        case .figure: nil
        }
    }

    /// This block with the text of `next` after it; `nil` when either is a
    /// figure.
    func merged(with next: Block) -> Block? {
        guard let content = splittableContent, let more = next.splittableContent else { return nil }
        return replacingContent(content.joined(with: more))
    }
}

extension BlockSource {
    /// Whether this source starts before `other` in reading order.
    func isBefore(_ other: BlockSource) -> Bool {
        (page, box.minY) < (other.page, other.box.minY)
    }

    /// A cut closer than this share of an area's height to the boundary
    /// between two areas is taken to be at that boundary: the position of a
    /// cut is estimated from the text, which is only roughly proportional to
    /// the space it takes.
    private static let boundarySnap = 0.15
    /// Each part of a cut area keeps at least this share of its height, so
    /// neither part ends up with no place to click.
    private static let minimumShare = 0.05

    /// The source cut in two where `fraction` of its height has passed.
    ///
    /// Text is not located line by line, so the cut is estimated by assuming
    /// that the text fills the areas evenly. A cut near the boundary of two
    /// areas (two pages, or two merged paragraphs) lands on it.
    func split(atFraction fraction: Double) -> (first: BlockSource, second: BlockSource) {
        let areas = areas
        let total = areas.reduce(0) { $0 + $1.box.height }
        guard total > 0 else { return (self, self) }
        let target = min(max(fraction, 0), 1) * total

        var start = 0.0
        for (index, area) in areas.enumerated() {
            let height = area.box.height
            let end = start + height
            defer { start = end }
            if index > 0, abs(target - start) <= Self.boundarySnap * min(height, areas[index - 1].box.height) {
                return (Self(areas: Array(areas[..<index])), Self(areas: Array(areas[index...])))
            }
            guard target < end || index == areas.count - 1 else { continue }
            let cut = min(max(target - start, height * Self.minimumShare), height * (1 - Self.minimumShare))
            let box = area.box
            let upper = PageArea(page: area.page, box: CGRect(x: box.minX, y: box.minY, width: box.width, height: cut))
            let lower = PageArea(
                page: area.page,
                box: CGRect(x: box.minX, y: box.minY + cut, width: box.width, height: height - cut)
            )
            return (
                Self(areas: Array(areas[..<index]) + [upper]),
                Self(areas: [lower] + Array(areas[(index + 1)...]))
            )
        }
        return (self, self)
    }

    private init(areas: [PageArea]) {
        self.init(page: areas[0].page, box: areas[0].box)
        continuations = Array(areas.dropFirst())
    }
}
