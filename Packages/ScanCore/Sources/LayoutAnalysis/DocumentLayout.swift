import DocumentModel

/// The structure recovered from the pages of a document.
public struct DocumentLayout: Sendable, Equatable {
    /// Headings, paragraphs and figures in reading order. The text of a
    /// linked note is not among them.
    public var blocks: [Block]
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

    public init(blocks: [Block], notes: [Note] = [], unlinkedReferences: Int = 0, unlinkedNotes: Int = 0) {
        self.blocks = blocks
        self.notes = notes
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }
}
