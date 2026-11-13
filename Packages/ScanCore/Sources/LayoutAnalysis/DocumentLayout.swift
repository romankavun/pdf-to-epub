import CoreGraphics
import DocumentModel

/// An area of one page, normalized, origin at the top-left corner.
public struct PageArea: Sendable, Equatable, Codable {
    /// Index of the page.
    public var page: Int
    public var box: CGRect

    public init(page: Int, box: CGRect) {
        self.page = page
        self.box = box
    }
}

/// Where a block comes from, so that a review screen can show the scan it
/// was read from.
///
/// A paragraph that runs onto the next page covers an area on each page it
/// touches; the review shows it on all of them.
public struct BlockSource: Sendable, Equatable, Codable {
    /// The area the block covers on the page it starts on.
    public var start: PageArea
    /// The areas on the following pages the block runs onto, in order;
    /// empty for a block that fits on one page.
    public var continuations: [PageArea]

    /// A block that lies at `box` on `page` alone.
    public init(page: Int, box: CGRect) {
        start = PageArea(page: page, box: box)
        continuations = []
    }

    /// Index of the page the block starts on.
    public var page: Int {
        start.page
    }

    /// The area the block covers on the page it starts on.
    public var box: CGRect {
        start.box
    }

    /// Every area of the block, the starting one first.
    public var areas: [PageArea] {
        [start] + continuations
    }

    /// Extends the block by `box` on `page`: the area on that page grows to
    /// include it, or a new area starts when `page` follows the last one.
    public mutating func add(_ box: CGRect, onPage page: Int) {
        if let last = continuations.last {
            if last.page == page {
                continuations[continuations.count - 1].box = last.box.union(box)
                return
            }
        } else if start.page == page {
            start.box = start.box.union(box)
            return
        }
        continuations.append(PageArea(page: page, box: box))
    }

    /// The same extension as ``add(_:onPage:)`` for every area of `other`.
    public mutating func add(_ other: BlockSource) {
        for area in other.areas {
            add(area.box, onPage: area.page)
        }
    }
}

/// The structure recovered from the pages of a document.
public struct DocumentLayout: Sendable, Equatable {
    /// Headings, paragraphs and figures in reading order. The text of a
    /// linked note is not among them.
    public var blocks: [Block]
    /// The origin of each block of ``blocks``, in the same order.
    public var sources: [BlockSource]
    /// The notes that text refers to, in the order their text appears in
    /// the document. Identifiers are `note-N`, where N counts every note text
    /// found, linked or not.
    public var notes: [Note]
    /// Where the text of each note of ``notes`` lies, in the same order.
    public var noteSources: [BlockSource]
    /// References that could not be linked to a note. They stay in the text
    /// as their label.
    public var unlinkedReferences: Int
    /// Note texts that nothing refers to. They stay in ``blocks`` as
    /// paragraphs that start with their label, so no text is lost.
    public var unlinkedNotes: Int

    public init(
        blocks: [Block],
        sources: [BlockSource] = [],
        notes: [Note] = [],
        noteSources: [BlockSource] = [],
        unlinkedReferences: Int = 0,
        unlinkedNotes: Int = 0
    ) {
        self.blocks = blocks
        self.sources = sources
        self.notes = notes
        self.noteSources = noteSources
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }
}
