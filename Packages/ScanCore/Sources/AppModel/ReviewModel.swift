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
        /// The text of a linked note, which the document keeps apart from the
        /// flow of blocks.
        case note(label: String)
    }

    /// Identifies a block or a note text across the pages it is shown on.
    public enum ItemID: Sendable, Hashable {
        /// A block, by its index in ``Document/blocks``.
        case block(Int)
        /// The text of a note in ``Document/notes``.
        case note(Note.ID)
    }

    /// The part of a block or a note text that lies on one page.
    ///
    /// A paragraph that runs onto the next page appears on both pages with
    /// the same ``id`` and text; only ``box`` and the continuation flags
    /// differ.
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: ItemID
        public var kind: Kind
        /// The whole text of the block, on every page it is shown on; for a
        /// figure, its caption.
        public var runs: [Run]
        /// The area the block covers on this page, normalized, origin at the
        /// top-left corner.
        public var box: CGRect
        /// The number of flagged words in ``runs``.
        public var issueCount: Int
        /// Whether the block starts on an earlier page.
        public var continuesFromPreviousPage = false
        /// Whether the block runs on to a later page.
        public var continuesOnNextPage = false
    }

    /// One page image with every block and note text that lies on it.
    public struct Page: Sendable, Equatable, Identifiable {
        /// The page's index in the document.
        public var id: Int
        public var url: URL
        /// Top to bottom. Empty for a cover or a blank page.
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

    /// Blocks and notes with at least one flagged word, in the order of
    /// the pages they start on, top to bottom. A block on two pages is one
    /// stop, on the page it starts on.
    private let flagged: [(itemID: ItemID, page: Int)]

    public init(conversion: Conversion, detector: SuspiciousWordDetector = SuspiciousWordDetector()) {
        let shown = Self.items(of: conversion, detector: detector)
        pages = Self.pages(showing: shown, urls: conversion.pageURLs)
        images = Dictionary(conversion.document.images.map { ($0.id, $0.data) }) { first, _ in first }
        issueCount = shown.reduce(0) { $0 + $1.item.issueCount }
        flagged = shown.enumerated()
            .filter { $0.element.item.issueCount > 0 }
            .sorted {
                let (left, right) = ($0.element.source.start, $1.element.source.start)
                return (left.page, left.box.minY, $0.offset) < (right.page, right.box.minY, $1.offset)
            }
            .map { ($0.element.item.id, $0.element.source.page) }
    }

    /// Every block, then every linked note, each with its runs and where it
    /// lies. An item's box is the one on the page it starts on.
    private static func items(
        of conversion: Conversion, detector: SuspiciousWordDetector
    ) -> [(item: Item, source: BlockSource)] {
        let document = conversion.document
        let labels = Dictionary(document.notes.map { ($0.id, $0.label) }) { first, _ in first }
        func item(_ id: ItemID, _ kind: Kind, _ content: [Inline], _ source: BlockSource) -> (Item, BlockSource) {
            let runs = runs(of: content, noteLabels: labels, detector: detector)
            let issues = runs.count { $0.reason != nil }
            return (Item(id: id, kind: kind, runs: runs, box: source.box, issueCount: issues), source)
        }
        let blocks = zip(document.blocks, conversion.blockSources).enumerated().map { index, pair in
            let (block, source) = pair
            return switch block {
            case let .heading(level, content): item(.block(index), .heading(level: level), content, source)
            case let .paragraph(content): item(.block(index), .paragraph, content, source)
            case let .figure(figure): item(.block(index), .figure(imageID: figure.imageID), figure.caption, source)
            }
        }
        let notes = zip(document.notes, conversion.noteSources).map { note, source in
            item(.note(note.id), .note(label: note.label), note.content, source)
        }
        return blocks + notes
    }

    /// The pages at `urls`, each with the part of every item that lies on
    /// it, top to bottom.
    private static func pages(showing items: [(item: Item, source: BlockSource)], urls: [URL]) -> [Page] {
        var itemsByPage: [Int: [Item]] = [:]
        for (item, source) in items {
            let areas = source.areas
            for (position, area) in areas.enumerated() {
                var part = item
                part.box = area.box
                part.continuesFromPreviousPage = position > 0
                part.continuesOnNextPage = position < areas.count - 1
                itemsByPage[area.page, default: []].append(part)
            }
        }
        return urls.enumerated().map { index, url in
            // Notes come after all blocks in `items`; on the page they sit
            // where they are printed. Equal tops keep their order.
            let items = (itemsByPage[index] ?? []).enumerated()
                .sorted { ($0.element.box.minY, $0.offset) < ($1.element.box.minY, $1.offset) }
                .map(\.element)
            return Page(id: index, url: url, items: items)
        }
    }

    /// The page being viewed; `nil` only for a document without pages.
    public var currentPage: Page? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
    }

    /// The number of blocks and note texts that contain flagged words: the stops of
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

    /// Puts the block in focus. Stays on the page being viewed when part of
    /// the block lies on it; otherwise shows the page the block starts on.
    public func select(itemID: Item.ID) {
        if currentPage?.items.contains(where: { $0.id == itemID }) == true {
            selectedItemID = itemID
            return
        }
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
