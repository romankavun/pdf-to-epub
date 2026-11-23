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
        /// A line whose top is above this fraction of the page height may be
        /// a running header.
        public var runningHeaderZone = 0.1
        /// A line whose top is below this fraction of the page height may be
        /// a running footer or page number.
        public var runningFooterZone = 0.88
        /// A running line must recur on at least this many pages...
        public var runningLineMinimumPages = 3
        /// ...and on at least this share of all pages (headers that differ
        /// on left and right pages recur on about half).
        public var runningLineMinimumShare = 0.1
        /// Recurrences must lie within this distance (a fraction of the page
        /// height) of each other.
        public var runningLineHeightTolerance = 0.02
        /// A block right under a picture, followed by a vertical step of at
        /// least this many median line steps, is the picture's caption. The
        /// extra space is what sets a caption apart from the paragraph that
        /// simply follows a picture.
        public var captionGapFactor = 2.75
        /// A heading at body size is at most this wide (a fraction of the
        /// page width); wider lines are paragraphs.
        public var bodyHeadingMaximumWidth = 0.7
        /// A heading at body size has at most this many characters.
        public var bodyHeadingMaximumLength = 100
        /// A centered line in body weight is a heading only when it has at
        /// most this many words; longer ones are dedications and epigraphs.
        public var centeredHeadingMaximumWords = 8
        /// How far the middle of a centered line may be from the middle of
        /// the page (a fraction of the page width).
        public var bodyHeadingCenterTolerance = 0.04
        /// A line is bold when its ink density is at least this many times
        /// the document's typical density.
        public var boldInkFactor = 1.15
        /// Whether a hyphen at the end of a line was added by the typesetter
        /// and is dropped when the word is joined ("con-" + "tainers"). True
        /// for printed documents; digital typesetting breaks lines without adding hyphens,
        /// so for their clean pages a line-end hyphen is part of the word.
        public var removesSoftHyphens = false
        /// Whether each page's margin is measured on its own, following a
        /// leaf that is cropped differently or lies at a slant (see
        /// `PageMargin`). Clean pages share one margin, which a page with no
        /// unindented line, such as a page of one-line notes, could not
        /// measure.
        public var measuresMarginPerPage = false

        public init() {}

        /// Thresholds for photographed or scanned printed pages.
        ///
        /// Each leaf is cropped from the scanner bed on its own, so running
        /// lines drift up and down from page to page by more than on a
        /// clean page, and a printed document hyphenates words at line ends.
        public static var scannedPage: Options {
            var options = Options()
            options.runningLineHeightTolerance = 0.05
            options.removesSoftHyphens = true
            options.measuresMarginPerPage = true
            return options
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// This analyzer with the thresholds of ``Options/scannedPage`` in place of
    /// its own for the things that differ in print; its other options stay.
    public var forScannedPages: LayoutAnalyzer {
        var copy = self
        let scan = Options.scannedPage
        copy.options.runningLineHeightTolerance = scan.runningLineHeightTolerance
        copy.options.removesSoftHyphens = scan.removesSoftHyphens
        copy.options.measuresMarginPerPage = scan.measuresMarginPerPage
        return copy
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
        var pageNumbers: [Row?] = []
        let elements = pages.map { page in
            defer { markers += page.markers }
            let found = elements(of: page, firstMarkerIndex: markers.count)
            pageNumbers.append(found.pageNumber)
            return found.elements
        }
        let (pages, runningLines) = withoutRunningLines(elements)
        // A document of pictures only has no text to measure; the metrics are
        // then never consulted.
        let metrics = Metrics(pages: pages.map { $0.compactMap(\.row?.line) })
            ?? Metrics(lineHeight: 0, lineStep: 0, margin: 0)

        let context = StyleContext(
            metrics: metrics, pages: pages, margins: pages.map { margin(of: $0, metrics: metrics) },
            typicalInk: typicalInk(of: pages)
        )
        var assembly = Assembly()
        for (pageIndex, page) in pages.enumerated() {
            assemble(page, at: pageIndex, into: &assembly, context: context)
        }
        flush(&assembly, context: context)
        promoteBodySizeHeadings(in: &assembly.blocks)
        var layout = NoteLinker(markers: markers)
            .layout(of: assembly.blocks, sources: assembly.sources, styles: assembly.styles)
        layout.styles.pageFurniture = pageFurniture(
            pageNumbers: pageNumbers, runningLines: runningLines, context: context
        )
        return layout
    }

    /// Adds the blocks of one page to `assembly`; the last block stays open,
    /// as it may run onto the next page.
    private func assemble(
        _ page: [PageElement], at pageIndex: Int, into assembly: inout Assembly, context: StyleContext
    ) {
        let metrics = context.metrics
        let measures = PageMeasures(metrics: metrics, margin: context.margins[pageIndex])
        var previous: TextLine?
        var afterPicture = false
        for (elementIndex, element) in page.enumerated() {
            switch element {
            case let .picture(picture):
                flush(&assembly, context: context)
                assembly.blocks.append(.figure(imageID: picture.imageID, caption: []))
                assembly.sources.append(BlockSource(page: pageIndex, box: picture.box))
                assembly.styles.append(style(
                    ofPictureAt: picture.box, page: pageIndex,
                    stepAbove: previous.map { Double(picture.box.minY - $0.box.minY) }, context: context
                ))
                // Whatever comes next is judged as a possible caption.
                assembly.draft = Draft(headingStyle: nil, figureIndex: assembly.blocks.count - 1)
                previous = nil
                afterPicture = true
            case let .row(row):
                let line = row.line
                let step = previous.map { Double(line.box.minY - $0.box.minY) }
                let headingStyle = headingStyle(
                    at: elementIndex, in: page, metrics: metrics, typicalInk: context.typicalInk
                )
                let isHeading = headingStyle != nil
                if continues(assembly.draft, with: row, isHeading: isHeading, step: step, on: measures) {
                    assembly.draft?.append(
                        row.pieces(skippingLeadingMarker: false), page: pageIndex, box: line.box, ink: row.ink,
                        removesSoftHyphens: options.removesSoftHyphens
                    )
                } else {
                    flush(&assembly, gapBelow: step, context: context)
                    // A block that opens with a marker is the text of a note.
                    var draft = Draft(
                        headingStyle: headingStyle, noteMarker: row.leadingMarker,
                        isHanging: row.leadingMarker != nil && !isIndented(line, margin: measures.margin),
                        stepAbove: step, isUnderPicture: afterPicture
                    )
                    draft.append(
                        row.pieces(skippingLeadingMarker: true), page: pageIndex, box: line.box, ink: row.ink
                    )
                    assembly.draft = draft
                }
                previous = line
                afterPicture = false
            }
        }
        endPage(&assembly, context: context)
    }

    /// Where unindented lines start on `page`: its own margin for paper
    /// scans, the document's for clean pages (see
    /// ``Options/measuresMarginPerPage``).
    private func margin(of page: [PageElement], metrics: Metrics) -> PageMargin {
        options.measuresMarginPerPage
            ? PageMargin(lines: page.compactMap(\.row?.line), documentMargin: metrics.margin)
            : PageMargin(constant: metrics.margin)
    }

    /// A caption never runs onto the next page, but an ordinary paragraph
    /// under a picture may.
    private func endPage(_ assembly: inout Assembly, context: StyleContext) {
        guard let pending = assembly.draft, pending.figureIndex != nil else { return }
        if captionRule(of: pending, gapBelow: nil, metrics: context.metrics) != nil {
            flush(&assembly, context: context)
        } else {
            assembly.draft?.figureIndex = nil
        }
    }

    /// How the line at `index` of `page` stands out as a heading, if it does.
    private func headingStyle(
        at index: Int, in page: [PageElement], metrics: Metrics, typicalInk: Double?
    ) -> HeadingStyle? {
        guard let line = page[index].row?.line else { return nil }
        if Double(line.box.height) >= options.headingHeightFactor * metrics.lineHeight {
            return overlapsNeighbour(line, among: page) ? nil : .larger
        }
        return bodySizeHeadingStyle(at: index, in: page, metrics: metrics, typicalInk: typicalInk)
    }

    /// A document whose only headings are set at body size has no use for a
    /// second level: they become level 1.
    private func promoteBodySizeHeadings(in blocks: inout [DraftBlock]) {
        let hasLarger = blocks.contains {
            if case .heading(1, _) = $0 {
                true
            } else {
                false
            }
        }
        guard !hasLarger else { return }
        blocks = blocks.map { block in
            if case let .heading(_, pieces) = block {
                .heading(level: 1, pieces)
            } else {
                block
            }
        }
    }

    /// Whether `row` belongs to the block being assembled.
    ///
    /// - Parameter step: Distance from the top of the previous line on the
    ///   same page; `nil` for the first line of a page or under a picture.
    private func continues(
        _ draft: Draft?, with row: Row, isHeading: Bool, step: Double?, on measures: PageMeasures
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
        if isIndented(row.line, margin: measures.margin) != draft.isHanging {
            return false
        }
        // The first line of a page: the block from the previous page runs on.
        return step.map { $0 <= options.paragraphGapFactor * measures.metrics.lineStep } ?? true
    }

    /// Measured against the page's own margin at the line's height (see
    /// ``PageMargin``).
    private func isIndented(_ line: TextLine, margin: PageMargin) -> Bool {
        Double(line.box.minX) > margin.at(Double(line.box.minY)) + options.indentThreshold
    }

    /// Ends the block being assembled: it becomes the caption of the figure
    /// it follows, or a block of its own.
    ///
    /// - Parameter gapBelow: Distance to the next line on the same page,
    ///   when there is one.
    private func flush(_ assembly: inout Assembly, gapBelow: Double? = nil, context: StyleContext) {
        guard let finished = assembly.draft else { return }
        assembly.draft = nil
        // A picture with nothing under it leaves an empty caption draft.
        guard !finished.isEmpty, let source = finished.source else { return }
        func style(_ rule: DecidingRule) -> BlockStyle {
            self.style(of: MeasuredBlock(
                lines: finished.lines, rule: rule, stepAbove: finished.stepAbove, stepBelow: gapBelow,
                isUnderPicture: finished.isUnderPicture, opensWithNoteLabel: finished.noteMarker != nil
            ), context: context)
        }
        if let index = finished.figureIndex, case let .figure(imageID, _) = assembly.blocks[index],
           let rule = captionRule(of: finished, gapBelow: gapBelow, metrics: context.metrics)
        {
            assembly.blocks[index] = .figure(imageID: imageID, caption: finished.pieces)
            assembly.sources[index].add(source)
            // A captioned figure looks like its caption.
            assembly.styles[index] = style(rule)
        } else {
            assembly.blocks.append(finished.block)
            assembly.sources.append(source)
            assembly.styles.append(style(finished.rule))
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

    /// How the block right under a picture was found to be that picture's
    /// caption; `nil` when it is not one.
    private func captionRule(of draft: Draft, gapBelow: Double?, metrics: Metrics) -> DecidingRule? {
        guard !draft.isEmpty, !draft.isHeading, draft.noteMarker == nil else { return nil }
        if draft.text.prefixMatch(of: Self.figureLabel) != nil {
            return .captionByLabel
        }
        guard let gapBelow else { return nil }
        return gapBelow >= options.captionGapFactor * metrics.lineStep ? .captionByGap : nil
    }

    /// "Fig. 3", "Figure 12", "Мал. 27", "Рис. 5", "Іл. 2": how captions
    /// are numbered in English and Ukrainian documents.
    private static var figureLabel: Regex<Substring> {
        /(?i)(?:figure|fig|мал|рис|іл)\.?\s*\d/
    }
}

/// The document's typical measurements together with the margin of the page at
/// hand, which is what deciding whether a line continues a block needs.
private struct PageMeasures {
    let metrics: Metrics
    let margin: PageMargin
}

/// The blocks finished so far and the one in progress.
private struct Assembly {
    var blocks: [DraftBlock] = []
    /// The origin of each block of `blocks`.
    var sources: [BlockSource] = []
    /// The style of each block of `blocks`.
    var styles: [BlockStyle] = []
    var draft: Draft?
}
