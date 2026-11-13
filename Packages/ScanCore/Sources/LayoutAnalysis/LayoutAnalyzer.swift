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

    /// Blocks of a document without illustrations, in reading order.
    ///
    /// - Parameter pages: Pages in reading order. Lines within a page may be
    ///   in any order.
    public func blocks(from pages: [RecognizedPage]) -> [Block] {
        blocks(from: pages.map { PageContent(lines: $0.lines) })
    }

    /// Blocks of the whole document in reading order.
    ///
    /// Text lying inside a picture is discarded: it is part of the image,
    /// and lettering on a poster or a cover would otherwise turn into
    /// headings. Each picture becomes a figure placed where it stands on the
    /// page, with the block right under it as its caption when that block
    /// looks like one (see ``Options/captionGapFactor``).
    ///
    /// - Parameter pages: Pages in reading order. Lines and pictures within
    ///   a page may be in any order.
    public func blocks(from pages: [PageContent]) -> [Block] {
        let pages = pages.map(elements)
        let lines = pages.map { $0.compactMap(\.line) }
        // A document of pictures only has no text to measure; the metrics are
        // then never consulted.
        let metrics = Metrics(pages: lines) ?? Metrics(lineHeight: 0, lineStep: 0, margin: 0)

        var assembly = Assembly()
        for page in pages {
            var previous: TextLine?
            for element in page {
                switch element {
                case let .picture(picture):
                    flush(&assembly, metrics: metrics)
                    assembly.blocks.append(.figure(Figure(imageID: picture.imageID, alternativeText: "")))
                    // Whatever comes next is judged as a possible caption.
                    assembly.draft = Draft(isHeading: false, figureIndex: assembly.blocks.count - 1)
                    previous = nil
                case let .line(line):
                    let step = previous.map { Double(line.box.minY - $0.box.minY) }
                    let isHeading = Double(line.box.height) >= options.headingHeightFactor * metrics.lineHeight
                        && !overlapsNeighbour(line, among: page)
                    if !continues(assembly.draft, with: line, isHeading: isHeading, step: step, metrics: metrics) {
                        flush(&assembly, gapBelow: step, metrics: metrics)
                        assembly.draft = Draft(isHeading: isHeading)
                    }
                    assembly.draft?.append(line.text)
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
        return assembly.blocks
    }

    /// Whether `line` belongs to the block being assembled.
    ///
    /// - Parameter step: Distance from the top of the previous line on the
    ///   same page; `nil` for the first line of a page or under a picture.
    private func continues(
        _ draft: Draft?, with line: TextLine, isHeading: Bool, step: Double?, metrics: Metrics
    ) -> Bool {
        guard let draft else { return false }
        if draft.isEmpty {
            // The first line under a picture; a heading is no caption.
            return !isHeading
        }
        if isHeading {
            // Only a wrapped heading continues: same page, directly below.
            return draft.isHeading && step.map { $0 < 2 * Double(line.box.height) } == true
        }
        if draft.isHeading || Double(line.box.minX) > metrics.margin + options.indentThreshold {
            return false
        }
        // The first line of a page, not indented: the paragraph from the
        // previous page runs on.
        return step.map { $0 <= options.paragraphGapFactor * metrics.lineStep } ?? true
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
        guard !finished.isEmpty else { return }
        if let index = finished.figureIndex, case var .figure(figure) = assembly.blocks[index],
           isCaption(finished, gapBelow: gapBelow, metrics: metrics)
        {
            figure.caption = [.text(finished.text)]
            assembly.blocks[index] = .figure(figure)
        } else {
            assembly.blocks.append(finished.block)
        }
    }

    /// Whether the box of `line` runs into a line above or below it.
    ///
    /// The OCR engine now and then reports an ordinary body line with a box
    /// two or three lines high. Such a box overlaps its neighbours, which a
    /// real heading never does, so height alone must not make it a heading.
    /// Boxes side by side (one line reported in pieces) do not count.
    private func overlapsNeighbour(_ line: TextLine, among page: [Element]) -> Bool {
        page.contains { element in
            guard let other = element.line, other != line else { return false }
            let shared = min(line.box.maxY, other.box.maxY) - max(line.box.minY, other.box.minY)
            let stacked = min(line.box.maxX, other.box.maxX) > max(line.box.minX, other.box.minX)
            return stacked && Double(shared) > options.headingOverlapTolerance * Double(line.box.height)
        }
    }

    /// Whether the block right under a picture is that picture's caption.
    private func isCaption(_ draft: Draft, gapBelow: Double?, metrics: Metrics) -> Bool {
        guard !draft.isEmpty, !draft.isHeading else { return false }
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

    /// The lines and pictures of a page from top to bottom, without the page
    /// number and without text that lies inside a picture.
    private func elements(of page: PageContent) -> [Element] {
        let outside = page.lines.filter { line in
            !page.pictures.contains { $0.box.contains(CGPoint(x: line.box.midX, y: line.box.midY)) }
        }
        let lines = withoutPageNumber(joiningPieces(outside).sorted { $0.box.minY < $1.box.minY })
        return (lines.map(Element.line) + page.pictures.map(Element.picture)).sorted { $0.top < $1.top }
    }

    /// Joins boxes that sit side by side on one row into a single line.
    ///
    /// The OCR engine sometimes reports one visual line as two or more
    /// pieces. Left alone, a right-hand piece looks like an indented line and
    /// breaks the paragraph. Pieces share most of their height and do not
    /// overlap horizontally; lines above each other never satisfy both.
    private func joiningPieces(_ lines: [TextLine]) -> [TextLine] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.box.minX < $1.box.minX }) {
            let row = rows.firstIndex { row in
                row.allSatisfy { other in
                    let shared = min(line.box.maxY, other.box.maxY) - max(line.box.minY, other.box.minY)
                    return shared > 0.5 * min(line.box.height, other.box.height) && other.box.maxX <= line.box.minX
                }
            }
            if let row {
                rows[row].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.compactMap { row in
            guard var joined = row.first else { return nil }
            for piece in row.dropFirst() {
                joined.text += " " + piece.text
                joined.box = joined.box.union(piece.box)
                joined.confidence = min(joined.confidence, piece.confidence)
            }
            return joined
        }
    }

    /// Removes the last line when it looks like a page number: short, digits
    /// only, near the bottom of the page.
    private func withoutPageNumber(_ lines: [TextLine]) -> [TextLine] {
        guard let last = lines.last, last.box.minY > options.pageNumberZone else { return lines }
        let text = last.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 4, text.allSatisfy(\.isNumber) else { return lines }
        return Array(lines.dropLast())
    }
}

/// A thing on a page that takes part in reading order.
private enum Element {
    case line(TextLine)
    case picture(PagePicture)

    var top: CGFloat {
        switch self {
        case let .line(line): line.box.minY
        case let .picture(picture): picture.box.minY
        }
    }

    var line: TextLine? {
        if case let .line(line) = self {
            line
        } else {
            nil
        }
    }
}

/// Typical measurements of a document's body text.
private struct Metrics {
    /// Median line height.
    let lineHeight: Double
    /// Median vertical distance between the tops of consecutive lines.
    let lineStep: Double
    /// Left edge of unindented body lines.
    let margin: Double

    init(lineHeight: Double, lineStep: Double, margin: Double) {
        self.lineHeight = lineHeight
        self.lineStep = lineStep
        self.margin = margin
    }

    /// `nil` when there are no lines at all.
    init?(pages: [[TextLine]]) {
        let lines = pages.flatMap(\.self)
        guard let lineHeight = Self.median(lines.map { Double($0.box.height) }) else { return nil }
        self.lineHeight = lineHeight

        let steps = pages.flatMap { lines in
            zip(lines, lines.dropFirst()).map { Double($1.box.minY - $0.box.minY) }
        }
        // A document of single-line pages has no steps; any positive value works
        // because the step is then never compared against anything.
        lineStep = Self.median(steps) ?? lineHeight

        // The most common left edge among long lines. Continuation lines
        // outnumber indented first lines in prose, so the mode is the margin.
        let bucketWidth = 0.01
        let long = lines.filter { $0.box.width > 0.5 }
        let edges = (long.isEmpty ? lines : long).map { Double($0.box.minX) }
        let buckets = Dictionary(grouping: edges) { ($0 / bucketWidth).rounded() }
        let modal = buckets.max { left, right in
            left.value.count != right.value.count ? left.value.count < right.value.count : left.key > right.key
        }
        margin = modal.flatMap { Self.median($0.value) } ?? 0
    }

    /// Lower median, so that an even split between two values picks the smaller.
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[(values.count - 1) / 2]
    }
}

/// The blocks finished so far and the one in progress.
private struct Assembly {
    var blocks: [Block] = []
    var draft: Draft?
}

/// A block being assembled from consecutive lines.
private struct Draft {
    let isHeading: Bool
    /// Index of the figure block this draft directly follows, while it is
    /// still a candidate for that figure's caption.
    var figureIndex: Int?
    private(set) var text = ""

    init(isHeading: Bool, figureIndex: Int? = nil) {
        self.isHeading = isHeading
        self.figureIndex = figureIndex
    }

    var isEmpty: Bool {
        text.isEmpty
    }

    mutating func append(_ line: String) {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { text = line; return }
        // "half-" + "baked": the line broke after a hyphen that belongs to the
        // word. clean-page sources break there without adding a hyphen of their own, so
        // it is kept. (Paper scans with soft hyphenation need more than this.)
        let brokeAfterHyphen = text.hasSuffix("-") && text.dropLast().last?.isLetter == true
        text += (brokeAfterHyphen ? "" : " ") + line
    }

    var block: Block {
        isHeading ? .heading(level: 1, content: [.text(text)]) : .paragraph([.text(text)])
    }
}
