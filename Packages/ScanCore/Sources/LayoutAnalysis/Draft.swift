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
    /// A heading of the given level; 1 is the largest (see ``HeadingStyle``).
    case heading(level: Int, [Piece])
    case paragraph([Piece])
    case figure(imageID: ImageResource.ID, caption: [Piece])
    /// The text of a note, opened by the marker with the given index.
    case note(marker: Int, [Piece])
}

/// What sets a heading apart.
enum HeadingStyle {
    /// Set in larger type than the body text.
    case larger
    /// Set in the body size in heavier ink than the text.
    case bold
    /// Set in the body size, centred, short and set apart by blank lines.
    case centered

    /// The heading level before levels are made contiguous.
    var level: Int {
        self == .larger ? 1 : 2
    }

    var rule: DecidingRule {
        switch self {
        case .larger: .largerThanText
        case .bold: .bodySizeBold
        case .centered: .bodySizeCentered
        }
    }
}

/// One line of a block as it was measured on its page.
struct MeasuredLine {
    var page: Int
    var box: CGRect
    /// Ink density, when the page image was measured.
    var ink: Double?
}

/// A block being assembled from consecutive lines.
struct Draft {
    /// Whether the block is a heading, and how it stands out from the body
    /// text; `nil` for any other block.
    let headingStyle: HeadingStyle?
    /// Index of the figure block this draft directly follows, while it is
    /// still a candidate for that figure's caption.
    var figureIndex: Int?
    /// The marker that opens the block, which makes it the text of a note.
    let noteMarker: Int?
    /// Whether the block is set with a hanging indent: its first line starts
    /// at the margin and the lines after it are indented. Only notes in a
    /// list are recognized as such.
    let isHanging: Bool
    /// The vertical step from the line before the block to its first line;
    /// `nil` at the top of a page or under a picture.
    let stepAbove: Double?
    /// Whether the block starts right under a picture.
    let isUnderPicture: Bool
    private(set) var pieces: [Piece] = []
    /// Every line of the block, in order.
    private(set) var lines: [MeasuredLine] = []
    /// The areas the block covers; `nil` until its first line is added.
    private(set) var source: BlockSource?

    var isHeading: Bool {
        headingStyle != nil
    }

    init(
        headingStyle: HeadingStyle?, figureIndex: Int? = nil, noteMarker: Int? = nil, isHanging: Bool = false,
        stepAbove: Double? = nil, isUnderPicture: Bool = false
    ) {
        self.headingStyle = headingStyle
        self.figureIndex = figureIndex
        self.noteMarker = noteMarker
        self.isHanging = isHanging
        self.stepAbove = stepAbove
        self.isUnderPicture = isUnderPicture || figureIndex != nil
    }

    /// The deciding rule of the block when it is not a caption.
    var rule: DecidingRule {
        if noteMarker != nil {
            .noteText
        } else if let headingStyle {
            headingStyle.rule
        } else {
            .paragraph
        }
    }

    var isEmpty: Bool {
        pieces.isEmpty
    }

    var text: String {
        pieces.plainText
    }

    /// Adds the content of the next line, which lies at `box` on `page`.
    ///
    /// - Parameter removesSoftHyphens: Whether a hyphen that ends the
    ///   previous line was added by the typesetter (see
    ///   ``LayoutAnalyzer/Options/removesSoftHyphens``).
    mutating func append(
        _ line: [Piece], page: Int, box: CGRect, ink: Double? = nil, removesSoftHyphens: Bool = false
    ) {
        lines.append(MeasuredLine(page: page, box: box, ink: ink))
        if source == nil {
            source = BlockSource(page: page, box: box)
        } else {
            source?.add(box, onPage: page)
        }
        guard let first = line.first else { return }
        switch (pieces.last, first) {
        case let (.text(before), .text(next)):
            // "half-" + "baked": the line broke after a hyphen that belongs
            // to the word. Digital typesetting breaks there without adding a hyphen of
            // their own, so it is kept. A printed document hyphenates words to
            // fill its lines, "con-" + "tainers", and that hyphen goes; one
            // before a capital ("Anglo-" + "Saxon") is part of the word.
            let brokeAfterHyphen = before.hasSuffix("-") && before.dropLast().last?.isLetter == true
            let isSoftHyphen = brokeAfterHyphen && removesSoftHyphens && next.first?.isLowercase == true
            let joined = isSoftHyphen ? String(before.dropLast()) : before
            pieces[pieces.count - 1] = .text(joined + (brokeAfterHyphen ? "" : " ") + next)
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
        } else if let headingStyle {
            .heading(level: headingStyle.level, pieces)
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
