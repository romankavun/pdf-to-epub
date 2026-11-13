import DocumentModel
import Foundation
import OCR

/// Turns recognized lines into headings and paragraphs using line geometry.
///
/// The OCR engine's own paragraph grouping is not used: on real pages it
/// splits indented first lines from their paragraphs (ADR 0001). Everything
/// here is measured relative to the document's own typical line, so it does not
/// depend on page size or resolution.
public struct LayoutAnalyzer: Sendable {
    /// Thresholds for the heuristics. Distances are fractions of the page
    /// width or height; factors are multiples of the document's median values.
    public struct Options: Sendable, Equatable {
        /// How far right of the body margin a line must start to count as a
        /// paragraph's indented first line.
        public var indentThreshold = 0.015
        /// A vertical step larger than this many median line steps separates
        /// paragraphs (a blank line is about two steps).
        public var paragraphGapFactor = 1.5
        /// A line at least this many times taller than the median is a heading.
        public var headingHeightFactor = 1.5
        /// A tall line sharing more than this fraction of its height with a
        /// line above or below is a mis-measured body line, not a heading.
        public var headingOverlapTolerance = 0.1
        /// A numeric last line below this height on the page is a page number.
        public var pageNumberZone = 0.85
        /// A block right under a picture, followed by a vertical step of at
        /// least this many median line steps, is the picture's caption. The
        /// extra space is what sets a caption apart from the paragraph that
        /// simply follows a picture.
        public var captionGapFactor = 2.75

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Blocks of a document without illustrations or notes, in reading order.
    ///
    /// - Parameter pages: Pages in reading order. Lines within a page may be
    ///   in any order.
    public func blocks(from pages: [RecognizedPage]) -> [Block] {
        blocks(from: pages.map { PageContent(lines: $0.lines) })
    }

    /// The blocks of ``layout(of:)`` alone.
    public func blocks(from pages: [PageContent]) -> [Block] {
        layout(of: pages).blocks
    }

    /// The structure of the whole document in reading order.
    ///
    /// Text lying inside a picture is discarded: it is part of the image,
    /// and lettering on a poster or a cover would otherwise turn into
    /// headings. Each picture becomes a figure placed where it stands on the
    /// page, with the block right under it as its caption when that block
    /// looks like one (see ``Options/captionGapFactor``).
    ///
    /// A note marker inside a line becomes a reference; a paragraph that
    /// starts with a marker is the text of a note and leaves the flow of
    /// blocks. References are then linked to notes by label and order (see
    /// ``DocumentLayout``).
    ///
    /// - Parameter pages: Pages in reading order. Lines, pictures and
    ///   markers within a page may be in any order.
    public func layout(of pages: [PageContent]) -> DocumentLayout {
        var markers: [NoteMarker] = []
        let pages = pages.map { page in
            defer { markers += page.markers }
            return elements(of: page, firstMarkerIndex: markers.count)
        }
        // A document of pictures only has no text to measure; the metrics are
        // then never consulted.
        let metrics = Metrics(pages: pages.map { $0.compactMap(\.row?.line) })
            ?? Metrics(lineHeight: 0, lineStep: 0, margin: 0)

        var assembly = Assembly()
        for (pageIndex, page) in pages.enumerated() {
            var previous: TextLine?
            for element in page {
                switch element {
                case let .picture(picture):
                    flush(&assembly, metrics: metrics)
                    assembly.blocks.append(.figure(imageID: picture.imageID, caption: []))
                    assembly.sources.append(BlockSource(page: pageIndex, box: picture.box))
                    // Whatever comes next is judged as a possible caption.
                    assembly.draft = Draft(isHeading: false, figureIndex: assembly.blocks.count - 1)
                    previous = nil
                case let .row(row):
                    let line = row.line
                    let step = previous.map { Double(line.box.minY - $0.box.minY) }
                    let isHeading = Double(line.box.height) >= options.headingHeightFactor * metrics.lineHeight
                        && !overlapsNeighbour(line, among: page)
                    if continues(assembly.draft, with: row, isHeading: isHeading, step: step, metrics: metrics) {
                        assembly.draft?.append(
                            row.pieces(skippingLeadingMarker: false), page: pageIndex, box: line.box
                        )
                    } else {
                        flush(&assembly, gapBelow: step, metrics: metrics)
                        // A block that opens with a marker is the text of a note.
                        var draft = Draft(
                            isHeading: isHeading, noteMarker: row.leadingMarker,
                            isHanging: row.leadingMarker != nil && !isIndented(line, metrics: metrics)
                        )
                        draft.append(row.pieces(skippingLeadingMarker: true), page: pageIndex, box: line.box)
                        assembly.draft = draft
                    }
                    previous = line
                }
            }
            // A caption never runs onto the next page, but an ordinary
            // paragraph under a picture may.
            if let pending = assembly.draft, pending.figureIndex != nil {
                if isCaption(pending, gapBelow: nil, metrics: metrics) {
                    flush(&assembly, metrics: metrics)
                } else {
                    assembly.draft?.figureIndex = nil
                }
            }
        }
        flush(&assembly, metrics: metrics)
        return NoteLinker(markers: markers).layout(of: assembly.blocks, sources: assembly.sources)
    }

    /// Whether `row` belongs to the block being assembled.
    ///
    /// - Parameter step: Distance from the top of the previous line on the
    ///   same page; `nil` for the first line of a page or under a picture.
    private func continues(
        _ draft: Draft?, with row: Row, isHeading: Bool, step: Double?, metrics: Metrics
    ) -> Bool {
        guard let draft else { return false }
        if draft.isEmpty {
            // The first line under a picture; a heading is no caption.
            return !isHeading
        }
        if row.isRemainder {
            return !draft.isHeading
        }
        if isHeading {
            // Only a wrapped heading continues: same page, directly below.
            return draft.isHeading && step.map { $0 < 2 * Double(row.line.box.height) } == true
        }
        // After a note, a line that opens with a marker is the next note.
        // At the top of a page only a numbered list item is certain to be
        // one; a bare marker there may be a reference carried over.
        if draft.isHeading || (draft.noteMarker != nil && row.leadingMarker != nil)
            || (step == nil && row.opensListItem)
        {
            return false
        }
        // A paragraph's first line is indented; in a note set with a
        // hanging indent it is the other way round.
        if isIndented(row.line, metrics: metrics) != draft.isHanging {
            return false
        }
        // The first line of a page: the block from the previous page runs on.
        return step.map { $0 <= options.paragraphGapFactor * metrics.lineStep } ?? true
    }

    private func isIndented(_ line: TextLine, metrics: Metrics) -> Bool {
        Double(line.box.minX) > metrics.margin + options.indentThreshold
    }

    /// Ends the block being assembled: it becomes the caption of the figure
    /// it follows, or a block of its own.
    ///
    /// - Parameter gapBelow: Distance to the next line on the same page,
    ///   when there is one.
    private func flush(_ assembly: inout Assembly, gapBelow: Double? = nil, metrics: Metrics) {
        guard let finished = assembly.draft else { return }
        assembly.draft = nil
        // A picture with nothing under it leaves an empty caption draft.
        guard !finished.isEmpty, let source = finished.source else { return }
        if let index = finished.figureIndex, case let .figure(imageID, _) = assembly.blocks[index],
           isCaption(finished, gapBelow: gapBelow, metrics: metrics)
        {
            assembly.blocks[index] = .figure(imageID: imageID, caption: finished.pieces)
            assembly.sources[index].add(source)
        } else {
            assembly.blocks.append(finished.block)
            assembly.sources.append(source)
        }
    }

    /// Whether the box of `line` runs into a line above or below it.
    ///
    /// The OCR engine now and then reports an ordinary body line with a box
    /// two or three lines high. Such a box overlaps its neighbours, which a
    /// real heading never does, so height alone must not make it a heading.
    /// Boxes side by side (one line reported in pieces) do not count.
    private func overlapsNeighbour(_ line: TextLine, among page: [PageElement]) -> Bool {
        page.contains { element in
            guard let other = element.row?.line, other != line else { return false }
            let shared = min(line.box.maxY, other.box.maxY) - max(line.box.minY, other.box.minY)
            let stacked = min(line.box.maxX, other.box.maxX) > max(line.box.minX, other.box.minX)
            return stacked && Double(shared) > options.headingOverlapTolerance * Double(line.box.height)
        }
    }

    /// Whether the block right under a picture is that picture's caption.
    private func isCaption(_ draft: Draft, gapBelow: Double?, metrics: Metrics) -> Bool {
        guard !draft.isEmpty, !draft.isHeading, draft.noteMarker == nil else { return false }
        if draft.text.prefixMatch(of: Self.figureLabel) != nil {
            return true
        }
        guard let gapBelow else { return false }
        return gapBelow >= options.captionGapFactor * metrics.lineStep
    }

    /// "Fig. 3", "Figure 12", "Мал. 27", "Рис. 5", "Іл. 2": how captions
    /// are numbered in English and Ukrainian documents.
    private static var figureLabel: Regex<Substring> {
        /(?i)(?:figure|fig|мал|рис|іл)\.?\s*\d/
    }
}

/// The blocks finished so far and the one in progress.
private struct Assembly {
    var blocks: [DraftBlock] = []
    /// The origin of each block of `blocks`.
    var sources: [BlockSource] = []
    var draft: Draft?
}
