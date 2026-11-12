/// A block-level element of a chapter.
public enum Block: Sendable, Codable, Equatable {
    /// A heading. `level` 1 is a chapter title; larger numbers nest deeper.
    case heading(level: Int, content: [Inline])
    /// A paragraph of body text.
    case paragraph([Inline])
    /// An illustration with an optional caption.
    case figure(Figure)

    /// Identifiers of the notes this block refers to, in order of appearance.
    /// A note referenced twice is listed twice.
    public var referencedNoteIDs: [Note.ID] {
        let content: [Inline] = switch self {
        case let .heading(_, content): content
        case let .paragraph(content): content
        case let .figure(figure): figure.caption
        }
        return content.compactMap { inline in
            if case let .noteReference(id) = inline { id } else { nil }
        }
    }
}

/// An illustration placed between paragraphs.
public struct Figure: Sendable, Codable, Equatable {
    /// Identifier of an ``ImageResource`` in ``Document/images``.
    public var imageID: ImageResource.ID
    /// Description for readers who cannot see the image. Empty when the image
    /// is decorative or nothing better than the caption is known.
    public var alternativeText: String
    /// Caption printed with the image; empty when there is none.
    public var caption: [Inline]

    public init(imageID: ImageResource.ID, alternativeText: String, caption: [Inline] = []) {
        self.imageID = imageID
        self.alternativeText = alternativeText
        self.caption = caption
    }
}

/// A run of inline content inside a block.
///
/// Formatting does not nest: this matches what can realistically be recovered
/// from a page image and keeps user corrections simple.
public enum Inline: Sendable, Codable, Equatable, ExpressibleByStringLiteral {
    case text(String)
    /// Italic in the source.
    case emphasis(String)
    /// Bold in the source.
    case strong(String)
    /// A reference to a ``Note`` in ``Document/notes``; rendered as the note's label.
    case noteReference(Note.ID)

    public init(stringLiteral value: String) {
        self = .text(value)
    }
}

public extension [Inline] {
    /// The readable text without formatting. Note references contribute
    /// nothing, so the result is suitable for titles and search.
    var plainText: String {
        map { inline in
            switch inline {
            case let .text(string), let .emphasis(string), let .strong(string): string
            case .noteReference: ""
            }
        }.joined()
    }
}
