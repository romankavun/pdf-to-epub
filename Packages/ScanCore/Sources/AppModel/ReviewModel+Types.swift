import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Observation
import TextReview

public extension ReviewModel {
    /// How a run of text is set.
    enum Style: Sendable, Equatable {
        case plain
        case emphasis
        case strong
        /// The label of a linked note.
        case noteReference
    }

    /// A stretch of a block's text with one style, flagged or not.
    struct Run: Sendable, Equatable {
        public var text: String
        public var style: Style
        /// Why the run, a single word, looks misread; `nil` for ordinary text.
        public var reason: SuspiciousWordDetector.Reason?

        public init(text: String, style: Style = .plain, reason: SuspiciousWordDetector.Reason? = nil) {
            self.text = text
            self.style = style
            self.reason = reason
        }
    }

    /// What a block is.
    enum Kind: Sendable, Equatable {
        case heading(level: Int)
        case paragraph
        case figure(imageID: ImageResource.ID)
        /// The text of a linked note, which the document keeps apart from the
        /// flow of blocks.
        case note(label: String)
        /// A block the user left out of the document. It stays in the review so
        /// that it can be brought back.
        case ignored
    }

    /// Identifies a block or a note text across the pages it is shown on.
    enum ItemID: Sendable, Hashable {
        /// A block, by its index in the corrected document's blocks.
        case block(Int)
        /// The text of a note in ``Document/notes``.
        case note(Note.ID)
        /// A block left out of the document, by its index in
        /// ``ProjectModel/ignored``.
        case ignored(Int)
    }

    /// A button a selected block shows.
    enum ItemAction: Sendable, Equatable {
        case editText
        case editCaption
        case bringBack
        case ignore
        /// The menu of types.
        case changeType
        case mergeWithNext
    }

    /// The look of a block's frame.
    enum Outline: Sendable, Equatable {
        /// The block as a whole is in doubt: its text was probably
        /// misrecognized, or it is a figure that may hide a page of text.
        case unreliable
        case flagged
        case note
        case ignored
        case plain
    }

    /// The part of a block or a note text that lies on one page.
    ///
    /// A paragraph that runs onto the next page appears on both pages with
    /// the same ``id`` and text; only ``box`` and the continuation flags
    /// differ.
    struct Item: Sendable, Equatable, Identifiable {
        public var id: ItemID
        public var kind: Kind
        /// Where the block starts: what corrections are recorded against.
        public var anchor: BlockAnchor
        /// The whole text of the block, on every page it is shown on; for a
        /// figure, its caption.
        public var runs: [Run]
        /// The area the block covers on this page, normalized, origin at the
        /// top-left corner.
        public var box: CGRect
        /// The number of OCR-suspect words in ``runs``.
        public var issueCount: Int
        /// The number of words in ``runs`` that the dictionary does not know.
        public var misspellingCount = 0
        /// The words of the document's language that the spelling rule judged
        /// in ``runs``, and how many it did not know; empty for an ignored
        /// block and without a dictionary.
        public var spelling = SuspiciousWordDetector.SpellingTally()
        /// Whether the block is a figure that is all there is on its page,
        /// over the text area and without a caption: the page's text was
        /// probably taken for a picture and never read.
        public var mayHideText = false
        /// Whether the block starts on an earlier page.
        public var continuesFromPreviousPage = false
        /// Whether the block runs on to a later page.
        public var continuesOnNextPage = false

        /// What can be done to this block once it is selected, in the order
        /// the buttons appear. Kept here so the view only draws it.
        public var actions: [ItemAction] {
            switch kind {
            case .ignored: [.bringBack]
            case .note: [.editText]
            case .figure: [.editCaption, .ignore]
            case .heading, .paragraph: [.editText, .changeType, .mergeWithNext]
            }
        }

        /// Whether the editor of this block offers "split at cursor".
        public var offersSplit: Bool {
            textType != nil || kind.isNote
        }

        /// Whether so many words are unknown that the whole text was
        /// probably misrecognized (see
        /// ``SuspiciousWordDetector/SpellingTally/isProbablyMisrecognized``).
        public var isProbablyMisrecognized: Bool {
            spelling.isProbablyMisrecognized
        }

        /// Whether the block is a stop of ``ReviewModel/goToNextIssue()``:
        /// it has OCR-suspect words, its text was probably misrecognized, or
        /// it may hide text.
        public var isIssue: Bool {
            issueCount > 0 || isProbablyMisrecognized || mayHideText
        }

        /// How the block's frame is told apart from others: doubt about the
        /// whole block wins, then flagged words.
        public var outline: Outline {
            if isProbablyMisrecognized || mayHideText {
                .unreliable
            } else if issueCount > 0 {
                .flagged
            } else if kind.isNote {
                .note
            } else if kind == .ignored {
                .ignored
            } else {
                .plain
            }
        }

        /// The text as the editor shows it: a note reference is its label in
        /// `⟦` `⟧` brackets.
        public var editableText: String {
            runs.map { $0.style == .noteReference ? "⟦\($0.text)⟧" : $0.text }.joined()
        }

        /// The text as corrections record it.
        var canonicalText: String {
            runs.map { $0.style == .noteReference ? "\u{FFFC}" : $0.text }.joined()
        }

        /// The type of a block that is a paragraph or a heading; `nil` for
        /// the rest.
        var textType: BlockType? {
            switch kind {
            case .paragraph: .paragraph
            case let .heading(level): .heading(level: level)
            case .figure, .note, .ignored: nil
            }
        }
    }

    /// One page image with every block and note text that lies on it.
    struct Page: Sendable, Equatable, Identifiable {
        /// The page's index in the document.
        public var id: Int
        public var url: URL
        /// Top to bottom. Empty for a cover or a blank page.
        public var items: [Item]

        /// Whether the page's only content is a figure that may hide text
        /// (see ``Item/mayHideText``).
        public var mayHideText: Bool {
            items.contains(where: \.mayHideText)
        }
    }

    /// A block that a correction could be applied to as well.
    struct Candidate: Sendable, Equatable, Identifiable {
        public var anchor: BlockAnchor
        /// The page the block starts on.
        public var page: Int
        /// The start of its text, to recognize it by.
        public var text: String

        public var id: BlockAnchor {
            anchor
        }

        public init(anchor: BlockAnchor, page: Int, text: String) {
            self.anchor = anchor
            self.page = page
            self.text = text
        }
    }

    /// A correction the user just made, offered for more places. It stands
    /// until accepted, dismissed or replaced by the next one.
    enum Proposal: Sendable, Equatable {
        /// Give these blocks the same type.
        case type(BlockType, candidates: [Candidate])
        /// Replace `find` with `replacement` wherever it stands as a whole
        /// word; `occurrences` counts the other places it stands now.
        case word(find: String, replacement: String, occurrences: Int)
    }
}

extension ReviewModel.Kind {
    var isNote: Bool {
        if case .note = self {
            true
        } else {
            false
        }
    }
}
