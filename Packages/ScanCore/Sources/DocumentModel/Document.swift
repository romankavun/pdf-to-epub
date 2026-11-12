/// A converted document: the single source of truth that the review UI edits and
/// the EPUB exporter reads.
public struct Document: Sendable, Codable, Equatable {
    /// Bibliographic data written to the EPUB package document.
    public var metadata: DocumentMetadata
    /// Chapters in reading order.
    public var chapters: [Chapter]

    public init(metadata: DocumentMetadata, chapters: [Chapter]) {
        self.metadata = metadata
        self.chapters = chapters
    }

    /// Every block of the document in reading order, ignoring chapter boundaries.
    public var blocks: [Block] {
        chapters.flatMap(\.blocks)
    }
}

/// Bibliographic data about a document.
public struct DocumentMetadata: Sendable, Codable, Equatable {
    public var title: String
    /// `nil` when the author is unknown; EPUB does not require one.
    public var author: String?
    /// BCP 47 language tag of the main text, for example `uk` or `en`.
    public var language: String

    public init(title: String, author: String?, language: String) {
        self.title = title
        self.author = author
        self.language = language
    }
}

/// A top-level section of a document. Each chapter becomes one XHTML file and one
/// table-of-contents entry in the exported EPUB.
public struct Chapter: Sendable, Codable, Equatable {
    /// Title shown in the table of contents.
    public var title: String
    /// Content in reading order.
    public var blocks: [Block]

    public init(title: String, blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }
}

/// A block-level element of a chapter.
///
/// Text is plain for now; inline structure (note references, emphasis) is
/// added when the layout stage needs it.
public enum Block: Sendable, Codable, Equatable {
    /// A heading. `level` 1 is a chapter title; larger numbers nest deeper.
    case heading(level: Int, text: String)
    /// A paragraph of body text.
    case paragraph(text: String)
}
