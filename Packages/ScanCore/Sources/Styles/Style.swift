import DocumentModel
import LayoutAnalysis

/// The type recognition gave the blocks of a style.
///
/// Sorted as the style overview groups styles: headings by level, then
/// paragraphs, figures, note texts and page furniture.
public enum StyleType: Hashable, Sendable, Comparable {
    case heading(level: Int)
    case paragraph
    case figure
    /// The text of a note.
    case note
    /// Lines left out of the document as page furniture.
    case pageFurniture
}

/// One thing a style groups: a block, a note text or a line of page furniture.
public enum StyleMember: Hashable, Sendable {
    /// A block, by its index in the document's blocks (and in
    /// ``LayoutAnalysis/BlockStyles/blocks`` and the block sources).
    case block(Int)
    /// A note text, by its index in the document's notes.
    case note(Int)
    /// A line of page furniture, by its index in
    /// ``LayoutAnalysis/BlockStyles/pageFurniture``.
    case pageFurniture(Int)
}

/// A group of blocks that look alike on the page and were given the same
/// type for the same reason (see GLOSSARY.md).
public struct Style: Sendable, Equatable, Identifiable {
    public var type: StyleType
    /// Why recognition gave the blocks their type.
    public var rule: DecidingRule
    /// Tells apart styles that share ``type`` and ``rule``, from 1 in order
    /// of first appearance; `nil` when no other style shares them. A name is
    /// made of the type, the rule and this number ("Paragraph 2 ·
    /// paragraph"); the app localizes it.
    public var number: Int?
    /// The style's blocks in order of appearance: by page, then from the top.
    public var members: [StyleMember]
    /// The pages the members start on, ascending, each once.
    public var pages: [Int]
    /// The colour of the style in a fixed palette: styles are counted in
    /// order of first appearance, so a project always gets the same colours.
    /// The app wraps it around its palette.
    public var paletteIndex: Int
    /// What the style's blocks look like: the median of each measurement,
    /// with the place (alignment, zone) of the first block.
    public var typical: BlockStyle

    /// The style's place in the order of first appearance, which is also
    /// its ``paletteIndex``.
    public var id: Int {
        paletteIndex
    }

    public init(
        type: StyleType, rule: DecidingRule, number: Int?, members: [StyleMember], pages: [Int], paletteIndex: Int,
        typical: BlockStyle
    ) {
        self.type = type
        self.rule = rule
        self.number = number
        self.members = members
        self.pages = pages
        self.paletteIndex = paletteIndex
        self.typical = typical
    }
}
