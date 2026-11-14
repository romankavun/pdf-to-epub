import Conversion
import CoreGraphics
import DocumentModel
import LayoutAnalysis

/// Finds blocks that look like one the user just corrected, so the same
/// correction can be offered for them.
///
/// "Looks like" is judged from the page alone, because that is what the
/// user sees: a block that is the same height (one line of a heading is
/// as tall as another's) and starts at the same left edge or is centred on
/// the same line. Text is not compared; headings differ in every word.
public enum SimilarBlocks {
    /// How much taller or shorter a block may be, as a share of the taller.
    static let heightTolerance = 0.25
    /// How far, as a share of the page width, the left edge or the centre
    /// may differ.
    static let positionTolerance = 0.02

    /// The anchors of the blocks of `conversion` that are of `type` and look
    /// like the block at `reference`, in document order. The block at
    /// `reference` itself is not among them, nor are figures, and nor are
    /// blocks that run onto another page, whose first area is not their
    /// real height.
    public static func anchors(
        like reference: BlockSource, ofType type: BlockType, in conversion: Conversion
    ) -> [BlockAnchor] {
        let referenceAnchor = BlockAnchor(reference)
        let blocks = conversion.document.blocks
        guard conversion.blockSources.count == blocks.count else { return [] }
        return zip(blocks, conversion.blockSources).compactMap { block, source in
            guard blockType(of: block) == type, source.continuations.isEmpty,
                  !referenceAnchor.matches(source), looksLike(source.box, reference.box)
            else { return nil }
            return BlockAnchor(source)
        }
    }

    private static func blockType(of block: Block) -> BlockType? {
        switch block {
        case .paragraph: .paragraph
        case let .heading(level, _): .heading(level: level)
        case .figure: nil
        }
    }

    private static func looksLike(_ box: CGRect, _ reference: CGRect) -> Bool {
        let taller = max(box.height, reference.height)
        guard taller > 0, abs(box.height - reference.height) / taller <= heightTolerance else { return false }
        return abs(box.minX - reference.minX) <= positionTolerance
            || abs(box.midX - reference.midX) <= positionTolerance
    }
}
