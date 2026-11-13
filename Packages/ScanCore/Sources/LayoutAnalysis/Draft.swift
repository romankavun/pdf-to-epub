import CoreGraphics
import DocumentModel

/// A run of inline content before notes are linked.
enum Piece: Equatable {
    case text(String)
    /// A note marker, by its index among all markers of the document.
    case reference(Int)
}

extension [Piece] {
    /// The readable text; markers contribute nothing.
    var plainText: String {
        map { piece in
            if case let .text(text) = piece {
                text
            } else {
                ""
            }
        }.joined()
    }
}

/// A block before notes are linked.
enum DraftBlock: Equatable {
    case heading([Piece])
    case paragraph([Piece])
    case figure(imageID: ImageResource.ID, caption: [Piece])
    /// The text of a note, opened by the marker with the given index.
    case note(marker: Int, [Piece])
}

/// A block being assembled from consecutive lines.
struct Draft {
    let isHeading: Bool
    /// Index of the figure block this draft directly follows, while it is
    /// still a candidate for that figure's caption.
    var figureIndex: Int?
    /// The marker that opens the block, which makes it the text of a note.
    let noteMarker: Int?
    /// Whether the block is set with a hanging indent: its first line starts
    /// at the margin and the lines after it are indented. Only notes in a
    /// list are recognized as such.
    let isHanging: Bool
    private(set) var pieces: [Piece] = []
    /// The areas the block covers; `nil` until its first line is added.
    private(set) var source: BlockSource?

    init(isHeading: Bool, figureIndex: Int? = nil, noteMarker: Int? = nil, isHanging: Bool = false) {
        self.isHeading = isHeading
        self.figureIndex = figureIndex
        self.noteMarker = noteMarker
        self.isHanging = isHanging
    }

    var isEmpty: Bool {
        pieces.isEmpty
    }

    var text: String {
        pieces.plainText
    }

    /// Adds the content of the next line, which lies at `box` on `page`.
    mutating func append(_ line: [Piece], page: Int, box: CGRect) {
        if source == nil {
            source = BlockSource(page: page, box: box)
        } else {
            source?.add(box, onPage: page)
        }
        guard let first = line.first else { return }
        switch (pieces.last, first) {
        case let (.text(before), .text(next)):
            // "half-" + "baked": the line broke after a hyphen that belongs
            // to the word. clean-page sources break there without adding a hyphen of
            // their own, so it is kept. (Paper scans with soft hyphenation
            // need more than this.)
            let brokeAfterHyphen = before.hasSuffix("-") && before.dropLast().last?.isLetter == true
            pieces[pieces.count - 1] = .text(before + (brokeAfterHyphen ? "" : " ") + next)
        case let (.reference, .text(next)):
            pieces.append(.text((next.isClosingPunctuation ? "" : " ") + next))
        default:
            // A marker that opens a line belongs to the word that ended the
            // line before it.
            pieces.append(first)
        }
        pieces += line.dropFirst()
    }

    var block: DraftBlock {
        if let noteMarker {
            .note(marker: noteMarker, pieces)
        } else if isHeading {
            .heading(pieces)
        } else {
            .paragraph(pieces)
        }
    }
}

extension StringProtocol {
    /// Whether the text starts with punctuation that is written right after
    /// the word before it, with no space.
    var isClosingPunctuation: Bool {
        first.map { ".,;:!?…)]»”’".contains($0) } ?? false
    }
}
