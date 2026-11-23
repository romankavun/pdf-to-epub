import CoreGraphics

/// The reason layout analysis gave a block its type: its deciding rule.
///
/// Together with ``BlockStyle``'s measured features it is what the style
/// overview groups blocks by, so a rule that is wrong for a document shows up
/// as one odd style instead of an error on every other page.
public enum DecidingRule: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// A heading set in larger type than the body text.
    case largerThanText
    /// A heading at body size, told apart by heavier ink (ADR 0006).
    case bodySizeBold
    /// A heading at body size, told apart by being centred, short and set
    /// apart by blank lines.
    case bodySizeCentered
    /// A figure whose caption opens with a figure label ("Fig. 3", "Мал. 27").
    case captionByLabel
    /// A figure whose caption is told apart by the space below it.
    case captionByGap
    /// A figure with no caption.
    case picture
    /// A block that opens with a note label: the text of a note. A note text
    /// that nothing refers to keeps this rule although it stays a paragraph.
    case noteText
    /// A paragraph: nothing made the block anything else.
    case paragraph
    /// Page furniture that repeats at the top or bottom edge of many pages.
    case runningLine
    /// Page furniture that is a page number.
    case pageNumber
}

/// How a block, a note text or a line of page furniture looks on the page,
/// measured relative to the document's own body text and page, with the rule
/// that decided its type.
///
/// Measurements are kept raw; the `Styles` module quantizes them into
/// buckets. A block that runs onto further pages is measured over all its
/// lines; its position (``zone``, ``alignment``) is that of its first page.
public struct BlockStyle: Sendable, Equatable, Codable {
    /// Where a block stands across the text column.
    public enum Alignment: String, Sendable, Equatable, Hashable, Codable {
        /// The first line starts at the body margin.
        case margin
        /// The first line starts right of the margin, as a paragraph's does.
        case indented
        /// Clear of both edges of the text column and about in its middle.
        case centered
        /// Clear of the left edge, ending at the right edge.
        case right
    }

    /// The vertical band of the page a block starts in.
    public enum Zone: String, Sendable, Equatable, Hashable, Codable {
        /// Wholly within the band where running headers stand.
        case top
        /// Wholly within the band where running footers and page numbers stand.
        case bottom
        /// Anywhere else.
        case body
    }

    public var rule: DecidingRule
    /// The median height of the block's lines, as a multiple of the
    /// document's median line height; 0 for a figure without a caption.
    public var lineHeight: Double
    /// The mean ink density of the block's lines as a multiple of the
    /// document's typical density; `nil` when the page was not measured.
    public var ink: Double?
    public var alignment: Alignment
    /// The width of the block's area on its first page, as a fraction of
    /// the width of the text column (may exceed 1 for a wide picture).
    public var width: Double
    public var zone: Zone
    /// The number of lines; 0 for a figure without a caption.
    public var lineCount: Int
    /// The space from the line before to the block's first line, in median
    /// line steps; `nil` at the top of a page or right under a picture.
    public var spaceAbove: Double?
    /// The space from the block's last line to the next line, in median
    /// line steps; `nil` when nothing follows on the same page.
    public var spaceBelow: Double?
    /// Whether the block, or a figure's caption, stands right under a picture.
    public var isUnderPicture: Bool
    /// Whether the block opens with a note marker.
    public var opensWithNoteLabel: Bool

    public init(
        rule: DecidingRule,
        lineHeight: Double = 1,
        ink: Double? = nil,
        alignment: Alignment = .margin,
        width: Double = 1,
        zone: Zone = .body,
        lineCount: Int = 1,
        spaceAbove: Double? = nil,
        spaceBelow: Double? = nil,
        isUnderPicture: Bool = false,
        opensWithNoteLabel: Bool = false
    ) {
        self.rule = rule
        self.lineHeight = lineHeight
        self.ink = ink
        self.alignment = alignment
        self.width = width
        self.zone = zone
        self.lineCount = lineCount
        self.spaceAbove = spaceAbove
        self.spaceBelow = spaceBelow
        self.isUnderPicture = isUnderPicture
        self.opensWithNoteLabel = opensWithNoteLabel
    }
}

/// A line that layout analysis left out of the document because it belongs
/// to the page, not the text: page furniture, kept so the style overview can
/// show it.
public struct PageFurniture: Sendable, Equatable, Codable {
    /// Where the line lies.
    public var area: PageArea
    /// The recognized text of the line.
    public var text: String
    /// Its measurements; the rule is ``DecidingRule/runningLine`` or
    /// ``DecidingRule/pageNumber``.
    public var style: BlockStyle

    public init(area: PageArea, text: String, style: BlockStyle) {
        self.area = area
        self.text = text
        self.style = style
    }
}

/// The ``BlockStyle`` of everything layout analysis recognized in a document:
/// what the style overview is computed from.
public struct BlockStyles: Sendable, Equatable, Codable {
    /// One per block of ``DocumentLayout/blocks``, in the same order.
    public var blocks: [BlockStyle]
    /// One per note of ``DocumentLayout/notes``, in the same order.
    public var notes: [BlockStyle]
    /// The page furniture of every page, in page order, top to bottom.
    public var pageFurniture: [PageFurniture]

    public init(blocks: [BlockStyle] = [], notes: [BlockStyle] = [], pageFurniture: [PageFurniture] = []) {
        self.blocks = blocks
        self.notes = notes
        self.pageFurniture = pageFurniture
    }
}
