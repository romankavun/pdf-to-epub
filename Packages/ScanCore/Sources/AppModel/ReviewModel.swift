import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Observation
import TextReview

/// State behind the review screen: the converted document laid out page by
/// page next to the scans it was read from, with suspicious words flagged,
/// a way to step through them, and the user's corrections.
///
/// Every correction goes through the model to the ``ProjectModel``, which
/// keeps it apart from the recognized text and saves it; the model then
/// rebuilds the pages from the corrected document.
@MainActor
@Observable
public final class ReviewModel {
    public let project: ProjectModel
    /// The document's embedded images, for showing figures.
    public let images: [ImageResource.ID: Data]
    public private(set) var pages: [Page] = []
    /// The total number of OCR-suspect words in the document.
    public private(set) var issueCount = 0
    /// The total number of words the spell checker does not know. Counted
    /// and navigated apart from ``issueCount``, which has priority.
    public private(set) var misspellingCount = 0
    /// Whether the review marks misspelled words. Off by default: they are
    /// numerous and mostly harmless, and OCR suspects come first.
    public var showsSpelling = false
    /// Words the user chose to ignore, lowercased. They are no longer
    /// flagged anywhere. Kept for this review only, not in the project.
    public internal(set) var ignoredWords: Set<String> = []
    /// The page being viewed.
    public private(set) var pageIndex = 0
    /// The block in focus, always on the page being viewed.
    public private(set) var selectedItemID: Item.ID?
    /// The block or note being edited, if any; it is the selected one.
    public internal(set) var editingItemID: Item.ID?
    /// The text in the editor while editing; see ``Item/editableText``.
    public var draft = ""
    public internal(set) var proposal: Proposal?

    /// Blocks and notes with at least one flagged word, in the order of
    /// the pages they start on, top to bottom. A block on two pages is one
    /// stop, on the page it starts on.
    private var flagged: [(itemID: ItemID, page: Int)] = []
    /// Like ``flagged``, for blocks with misspelled words.
    private var misspelled: [(itemID: ItemID, page: Int)] = []
    let detector: SuspiciousWordDetector

    public init(project: ProjectModel, detector: SuspiciousWordDetector = SuspiciousWordDetector()) {
        self.project = project
        self.detector = detector
        images = Dictionary(project.base.document.images.map { ($0.id, $0.data) }) { first, _ in first }
        rebuild()
    }

    /// A review of a document that is not kept anywhere, for a conversion with
    /// no project behind it.
    public convenience init(conversion: Conversion, detector: SuspiciousWordDetector = SuspiciousWordDetector()) {
        self.init(project: ProjectModel(base: conversion), detector: detector)
    }

    // MARK: - Building the pages

    /// Shows the project's current state, keeping the page and following the
    /// selected block to where it is now.
    func rebuild() {
        let selectedAnchor = selectedItem?.anchor
        let shown = items()
        pages = Self.pages(showing: shown, urls: project.conversion.pageURLs)
        issueCount = shown.reduce(0) { $0 + $1.item.issueCount }
        misspellingCount = shown.reduce(0) { $0 + $1.item.misspellingCount }
        flagged = Self.stops(of: shown) { $0.issueCount > 0 }
        misspelled = Self.stops(of: shown) { $0.misspellingCount > 0 }
        selectedItemID = selectedAnchor.flatMap { anchor in
            currentPage?.items.first { $0.anchor == anchor }?.id
        }
        if editingItemID != selectedItemID {
            editingItemID = nil
        }
    }

    /// Every block, then every linked note, then every ignored block, each
    /// with its runs and where it lies. An item's box is the one on the page
    /// it starts on.
    private func items() -> [(item: Item, source: BlockSource)] {
        let document = project.conversion.document
        let labels = Dictionary(project.base.document.notes.map { ($0.id, $0.label) }) { first, _ in first }
        func item(
            _ id: ItemID, _ kind: Kind, _ content: [Inline], _ source: BlockSource, flagging: Bool = true
        ) -> (Item, BlockSource) {
            var runs = Self.runs(of: content, noteLabels: labels, detector: detector)
            if !flagging {
                runs = runs.map { Run(text: $0.text, style: $0.style) }
            } else if !ignoredWords.isEmpty {
                for index in runs.indices where ignoredWords.contains(runs[index].text.lowercased()) {
                    runs[index].reason = nil
                }
            }
            let issues = runs.count { $0.reason?.isOCRSuspect == true }
            var item = Item(
                id: id, kind: kind, anchor: BlockAnchor(source), runs: runs, box: source.box, issueCount: issues
            )
            item.misspellingCount = runs.count { $0.reason == .misspelled }
            return (item, source)
        }
        let blocks = zip(document.blocks, project.conversion.blockSources).enumerated().map { index, pair in
            let (block, source) = pair
            return switch block {
            case let .heading(level, content): item(.block(index), .heading(level: level), content, source)
            case let .paragraph(content): item(.block(index), .paragraph, content, source)
            case let .figure(figure): item(.block(index), .figure(imageID: figure.imageID), figure.caption, source)
            }
        }
        let notes = zip(document.notes, project.conversion.noteSources).map { note, source in
            item(.note(note.id), .note(label: note.label), note.content, source)
        }
        let ignored = project.ignored.enumerated().map { index, ignored in
            let content: [Inline] = switch ignored.block {
            case let .heading(_, content), let .paragraph(content): content
            case let .figure(figure): figure.caption
            }
            return item(.ignored(index), .ignored, content, ignored.source, flagging: false)
        }
        return blocks + notes + ignored
    }

    /// The pages at `urls`, each with the part of every item that lies on
    /// it, top to bottom.
    private static func pages(showing items: [(item: Item, source: BlockSource)], urls: [URL]) -> [Page] {
        var itemsByPage: [Int: [Item]] = [:]
        for (item, source) in items {
            // A merged block can have several areas on one page; they are
            // shown as one, covering them all.
            var boxes: [(page: Int, box: CGRect)] = []
            for area in source.areas {
                if let position = boxes.firstIndex(where: { $0.page == area.page }) {
                    boxes[position].box = boxes[position].box.union(area.box)
                } else {
                    boxes.append((area.page, area.box))
                }
            }
            for (position, area) in boxes.enumerated() {
                var part = item
                part.box = area.box
                part.continuesFromPreviousPage = position > 0
                part.continuesOnNextPage = position < boxes.count - 1
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

    // MARK: - Navigation

    /// The page being viewed; `nil` only for a document without pages.
    public var currentPage: Page? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
    }

    /// The block in focus.
    public var selectedItem: Item? {
        currentPage?.items.first { $0.id == selectedItemID }
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
        cancelEditing()
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
        if editingItemID != itemID {
            cancelEditing()
        }
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

    // MARK: - Misspellings

    /// How many blocks and notes have misspelled words.
    public var misspelledItemCount: Int {
        misspelled.count
    }

    /// Which misspelling stop the selected block is, counting from 1; `nil`
    /// when the selection has no misspelled word.
    public var misspellingPosition: Int? {
        misspelled.firstIndex { $0.itemID == selectedItemID }.map { $0 + 1 }
    }

    /// Like ``goToNextIssue()``, for blocks with misspelled words.
    public func goToNextMisspelling() {
        guard !misspelled.isEmpty else { return }
        let next = if let position = misspellingPosition {
            position % misspelled.count
        } else {
            misspelled.firstIndex { $0.page >= pageIndex } ?? 0
        }
        select(itemID: misspelled[next].itemID)
    }

    /// Like ``goToPreviousIssue()``, for blocks with misspelled words.
    public func goToPreviousMisspelling() {
        guard !misspelled.isEmpty else { return }
        let previous = if let position = misspellingPosition {
            (position - 2 + misspelled.count) % misspelled.count
        } else {
            misspelled.lastIndex { $0.page < pageIndex } ?? misspelled.count - 1
        }
        select(itemID: misspelled[previous].itemID)
    }

    // MARK: - Helpers

    /// The items that pass `isFlagged`, in the order of the pages they start
    /// on, top to bottom.
    private static func stops(
        of shown: [(item: Item, source: BlockSource)], where isFlagged: (Item) -> Bool
    ) -> [(itemID: ItemID, page: Int)] {
        shown.enumerated()
            .filter { isFlagged($0.element.item) }
            .sorted {
                let (left, right) = ($0.element.source.start, $1.element.source.start)
                return (left.page, left.box.minY, $0.offset) < (right.page, right.box.minY, $1.offset)
            }
            .map { ($0.element.item.id, $0.element.source.page) }
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
