import Foundation

/// A converted document: the single source of truth that the review UI edits and
/// the EPUB exporter reads.
public struct Document: Sendable, Codable, Equatable {
    /// Bibliographic data written to the EPUB package document.
    public var metadata: DocumentMetadata
    /// Chapters in reading order.
    public var chapters: [Chapter]
    /// Every note of the document, whether it was a page footnote or an endnote in
    /// the source. Text refers to them with ``Inline/noteReference(_:)``.
    public var notes: [Note]
    /// Image files used by figures and the cover.
    public var images: [ImageResource]
    /// Identifier of the image in ``images`` used as the cover, if any.
    public var coverImageID: ImageResource.ID?

    public init(
        metadata: DocumentMetadata,
        chapters: [Chapter],
        notes: [Note] = [],
        images: [ImageResource] = [],
        coverImageID: ImageResource.ID? = nil
    ) {
        self.metadata = metadata
        self.chapters = chapters
        self.notes = notes
        self.images = images
        self.coverImageID = coverImageID
    }

    /// Every block of the document in reading order, ignoring chapter boundaries.
    public var blocks: [Block] {
        chapters.flatMap(\.blocks)
    }

    /// The note with the given identifier, or `nil` if there is none.
    public func note(withID id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    /// The image with the given identifier, or `nil` if there is none.
    public func image(withID id: ImageResource.ID) -> ImageResource? {
        images.first { $0.id == id }
    }
}

/// Bibliographic data about a document.
public struct DocumentMetadata: Sendable, Codable, Equatable {
    /// Globally unique identifier of the publication, required by EPUB.
    /// Stays the same across re-exports so readers treat them as one document.
    public var identifier: String
    public var title: String
    /// `nil` when the author is unknown; EPUB does not require one.
    public var author: String?
    /// BCP 47 language tag of the main text, for example `uk` or `en`.
    public var language: String

    /// - Parameter identifier: Defaults to a new random `urn:uuid:` value.
    public init(identifier: String? = nil, title: String, author: String?, language: String) {
        self.identifier = identifier ?? "urn:uuid:\(UUID().uuidString.lowercased())"
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

/// A note attached to a place in the text.
public struct Note: Sendable, Codable, Equatable, Identifiable {
    public typealias ID = String

    /// Unique within the document. Not shown to the reader.
    public var id: ID
    /// The marker printed in the text, for example `1`, `*` or `b`.
    public var label: String
    public var content: [Inline]

    public init(id: ID, label: String, content: [Inline]) {
        self.id = id
        self.label = label
        self.content = content
    }
}

/// An image file embedded in the document.
public struct ImageResource: Sendable, Codable, Equatable, Identifiable {
    public typealias ID = String

    /// Unique within the document.
    public var id: ID
    /// File name inside the EPUB, for example `figure-004.png`. Must be unique.
    public var filename: String
    /// MIME type, for example `image/png` or `image/jpeg`.
    public var mediaType: String
    /// Encoded image file contents.
    public var data: Data

    public init(id: ID, filename: String, mediaType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.data = data
    }
}
