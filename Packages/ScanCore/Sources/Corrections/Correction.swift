import CoreGraphics
import LayoutAnalysis

/// Where a block or note text lies in the scans, used as its identity.
///
/// A block has no identifier that survives converting the document again:
/// indices shift and note numbers are recounted. Its place on the page is
/// what the user pointed at, and it stays nearly the same when OCR or layout
/// analysis is run again, so a correction finds its block by the page and
/// the area where the block starts.
public struct BlockAnchor: Sendable, Codable, Hashable {
    /// Two areas are the same place when they overlap by at least this
    /// share of their union. Enough to absorb the few pixels a line box
    /// moves between runs, not enough to confuse neighbouring lines.
    static let minimumOverlap: CGFloat = 0.5

    public var page: Int
    /// Normalized, origin at the top-left corner, as in ``PageArea``.
    public var box: CGRect

    public init(page: Int, box: CGRect) {
        self.page = page
        self.box = box
    }

    /// The anchor of the block that starts where `source` starts.
    public init(_ source: BlockSource) {
        self.init(page: source.page, box: source.box)
    }

    /// Whether `other` is the same place on the same page.
    public func matches(_ other: BlockAnchor) -> Bool {
        guard page == other.page else { return false }
        let overlap = box.intersection(other.box)
        guard !overlap.isNull else { return false }
        let union = box.union(other.box)
        guard union.width * union.height > 0 else { return box == other.box }
        return overlap.width * overlap.height / (union.width * union.height) >= Self.minimumOverlap
    }

    /// Whether a block that starts at `source` is at this place.
    public func matches(_ source: BlockSource) -> Bool {
        matches(BlockAnchor(source))
    }
}

/// What a block is, as the user decided it.
public enum BlockType: Sendable, Codable, Hashable {
    case paragraph
    /// `level` 1 is a chapter title; the exporter nests deeper levels.
    case heading(level: Int)
    /// Not part of the document: a page decoration, a stray scan.
    case ignored
}

/// One decision of the user. Corrections are kept apart from the output of
/// OCR and layout analysis and applied on top of it, so converting the document
/// again does not lose them.
public enum Correction: Sendable, Codable, Equatable {
    /// The block at the anchor is of the given type.
    case retype(BlockAnchor, to: BlockType)
    /// The text of the block or note at the anchor, whose automatic text
    /// was `from`, is `to`. Both are in the canonical form of
    /// ``Swift/Array/canonicalText``. If the automatic text has changed, the
    /// edit is stale and not applied.
    case edit(BlockAnchor, from: String, to: String)
    /// Every whole word `word` in the document's text is `replacement`.
    case replaceWord(String, with: String)
}
