import CoreGraphics
import DocumentModel

/// Where a block comes from, so that a review screen can show the scan it
/// was read from.
public struct BlockSource: Sendable, Equatable, Codable {
    /// Index of the page the block starts on.
    public var page: Int
    /// The area the block covers on that page, normalized, origin at the
    /// top-left corner. The part of a block that runs onto the next page is
    /// not included.
    public var box: CGRect

    public init(page: Int, box: CGRect) {
        self.page = page
        self.box = box
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
        unlinkedReferences: Int = 0,
        unlinkedNotes: Int = 0
    ) {
        self.blocks = blocks
        self.sources = sources
        self.notes = notes
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }
}
