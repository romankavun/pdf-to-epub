import Conversion
import CoreGraphics
import DocumentModel
import Foundation
import LayoutAnalysis
import Observation
import TextReview

/// State behind the review screen: the converted document laid out page by
/// page next to the scans it was read from, with suspicious words flagged
/// and a way to step through them.
///
/// Read-only for now: it shows what the pipeline produced, corrections come
/// later.
@MainActor
@Observable
public final class ReviewModel {
    /// How a run of text is set.
    public enum Style: Sendable, Equatable {
        case plain
        case emphasis
        case strong
        /// The label of a linked note.
        case noteReference
    }

    /// A stretch of a block's text with one style, flagged or not.
    public struct Run: Sendable, Equatable {
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
    public enum Kind: Sendable, Equatable {
        case heading(level: Int)
        case paragraph
        case figure(imageID: ImageResource.ID)
    }

    /// One block of the document as shown in review.
    public struct Item: Sendable, Equatable, Identifiable {
        /// The block's index in ``Document/blocks``.
        public var id: Int
        public var kind: Kind
        /// The block's text; for a figure, its caption.
        public var runs: [Run]
        /// The area the block covers on its page, normalized, origin at the
        /// top-left corner.
        public var box: CGRect
        /// The number of flagged words in ``runs``.
        public var issueCount: Int
    }

    /// One page image with the blocks that start on it.
    public struct Page: Sendable, Equatable, Identifiable {
        /// The page's index in the document.
        public var id: Int
        public var url: URL
        /// Empty for a cover, a blank page, or a page that only continues a
        /// block from the page before.
        public var items: [Item]
    }

    public let pages: [Page]
    /// The document's embedded images, for showing figures.
    public let images: [ImageResource.ID: Data]
    /// The total number of flagged words in the document.
    public let issueCount: Int
    /// The page being viewed.
    public private(set) var pageIndex = 0
    /// The block in focus, always on the page being viewed.
    public private(set) var selectedItemID: Item.ID?

    /// Blocks with at least one flagged word, in reading order.
    private let flagged: [(itemID: Item.ID, page: Int)]

    public init(conversion: Conversion, detector: SuspiciousWordDetector = SuspiciousWordDetector()) {
        let document = conversion.document
        let labels = Dictionary(document.notes.map { ($0.id, $0.label) }) { first, _ in first }
        var itemsByPage: [Int: [Item]] = [:]
        var flagged: [(itemID: Item.ID, page: Int)] = []
        for (index, (block, source)) in zip(document.blocks, conversion.blockSources).enumerated() {
            let (kind, content): (Kind, [Inline]) = switch block {
            case let .heading(level, content): (.heading(level: level), content)
            case let .paragraph(content): (.paragraph, content)
            case let .figure(figure): (.figure(imageID: figure.imageID), figure.caption)
            }
            let runs = Self.runs(of: content, noteLabels: labels, detector: detector)
            let issues = runs.count { $0.reason != nil }
            itemsByPage[source.page, default: []].append(
                Item(id: index, kind: kind, runs: runs, box: source.box, issueCount: issues)
            )
            if issues > 0 {
                flagged.append((index, source.page))
            }
        }
        pages = conversion.pageURLs.enumerated().map { index, url in
            Page(id: index, url: url, items: itemsByPage[index] ?? [])
        }
        images = Dictionary(document.images.map { ($0.id, $0.data) }) { first, _ in first }
        issueCount = pages.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.issueCount } }
        self.flagged = flagged
    }

    /// The page being viewed; `nil` only for a document without pages.
    public var currentPage: Page? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
    }

    /// The number of blocks that contain flagged words: the stops of
    /// ``goToNextIssue()``.
    public var flaggedItemCount: Int {
        flagged.count
    }

    /// Which stop the selected block is, counting from 1; `nil` when the
    /// selection is not a flagged block.
    public var issuePosition: Int? {
        flagged.firstIndex { $0.itemID == selectedItemID }.map { $0 + 1 }
    }

    public var canGoToNextPage: Bool {
        pageIndex + 1 < pages.count
    }

    public var canGoToPreviousPage: Bool {
        pageIndex > 0
    }

    /// Shows page `index` with nothing selected. Ignores an index outside
    /// the document.
    public func goToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        pageIndex = index
        selectedItemID = nil
    }

    public func goToNextPage() {
        goToPage(pageIndex + 1)
    }

    public func goToPreviousPage() {
        goToPage(pageIndex - 1)
    }

    /// Puts the block in focus and shows its page.
    public func select(itemID: Item.ID) {
        guard let page = pages.first(where: { $0.items.contains { $0.id == itemID } }) else { return }
        pageIndex = page.id
        selectedItemID = itemID
    }

    /// Moves the focus to the next flagged block: after the selected one,
    /// or from the page being viewed when nothing flagged is selected.
    /// Wraps around at the end of the document.
    public func goToNextIssue() {
        guard !flagged.isEmpty else { return }
        let next = if let position = issuePosition {
            position % flagged.count
        } else {
            flagged.firstIndex { $0.page >= pageIndex } ?? 0
        }
        select(itemID: flagged[next].itemID)
    }

    /// Moves the focus to the previous flagged block: before the selected
    /// one, or before the page being viewed when nothing flagged is
    /// selected. Wraps around at the start of the document.
    public func goToPreviousIssue() {
        guard !flagged.isEmpty else { return }
        let previous = if let position = issuePosition {
            (position - 2 + flagged.count) % flagged.count
        } else {
            flagged.lastIndex { $0.page < pageIndex } ?? flagged.count - 1
        }
        select(itemID: flagged[previous].itemID)
    }

    private static func runs(
        of content: [Inline], noteLabels: [Note.ID: String], detector: SuspiciousWordDetector
    ) -> [Run] {
        content.flatMap { inline -> [Run] in
            let (text, style): (String, Style) = switch inline {
            case let .text(text): (text, .plain)
            case let .emphasis(text): (text, .emphasis)
            case let .strong(text): (text, .strong)
            case let .noteReference(id): (noteLabels[id] ?? "?", .noteReference)
            }
            if style == .noteReference {
                return [Run(text: text, style: style)]
            }
            return detector.segments(of: text).map { Run(text: $0.text, style: style, reason: $0.reason) }
        }
    }
}
