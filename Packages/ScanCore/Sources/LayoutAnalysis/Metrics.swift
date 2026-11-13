import OCR

/// Typical measurements of a document's body text.
struct Metrics {
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

        let steps: [Double] = pages.flatMap { lines in
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
