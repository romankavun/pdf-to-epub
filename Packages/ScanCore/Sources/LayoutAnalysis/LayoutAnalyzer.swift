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
        /// A numeric last line below this height on the page is a page number.
        public var pageNumberZone = 0.85

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Blocks of the whole document in reading order.
    ///
    /// - Parameter pages: Pages in reading order. Lines within a page may be
    ///   in any order.
    public func blocks(from pages: [RecognizedPage]) -> [Block] {
        let pages = pages.map { page in
            withoutPageNumber(page.lines.sorted { $0.box.minY < $1.box.minY })
        }
        guard let metrics = Metrics(pages: pages) else { return [] }

        var blocks: [Block] = []
        var draft: Draft?
        func flush() {
            if let draft {
                blocks.append(draft.block)
            }
            draft = nil
        }

        for lines in pages {
            for (index, line) in lines.enumerated() {
                let previous = index > 0 ? lines[index - 1] : nil
                let step = previous.map { Double(line.box.minY - $0.box.minY) }
                let height = Double(line.box.height)
                let isHeading = height >= options.headingHeightFactor * metrics.lineHeight
                let continues: Bool = if isHeading {
                    // Only a wrapped heading continues: same page, directly below.
                    draft?.isHeading == true && step.map { $0 < 2 * height } == true
                } else if draft == nil || draft?.isHeading == true {
                    false
                } else if Double(line.box.minX) > metrics.margin + options.indentThreshold {
                    false
                } else if let step {
                    step <= options.paragraphGapFactor * metrics.lineStep
                } else {
                    // First line of a page, not indented: the paragraph from
                    // the previous page runs on.
                    true
                }
                if !continues {
                    flush()
                    draft = Draft(isHeading: isHeading)
                }
                draft?.append(line.text)
            }
        }
        flush()
        return blocks
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

/// Typical measurements of a document's body text.
private struct Metrics {
    /// Median line height.
    let lineHeight: Double
    /// Median vertical distance between the tops of consecutive lines.
    let lineStep: Double
    /// Left edge of unindented body lines.
    let margin: Double

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

/// A block being assembled from consecutive lines.
private struct Draft {
    let isHeading: Bool
    private var text = ""

    init(isHeading: Bool) {
        self.isHeading = isHeading
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
