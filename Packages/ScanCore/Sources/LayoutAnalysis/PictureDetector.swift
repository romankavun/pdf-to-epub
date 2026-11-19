import CoreGraphics
import OCR

/// Finds illustrations on a page from its pixels.
///
/// A page is cut into horizontal bands of rows that contain anything other
/// than the background colour. Lines of text are separated by blank rows, so
/// text gives low bands; a band much taller than a line is a picture, unless
/// nearly all of its ink lies inside recognized text lines (a large title
/// whose lines touch). Text recognized *inside* a picture does not explain
/// the picture: most of the ink is outside the text boxes.
///
/// Paper scans add marks that are not part of the page's content: the edges
/// of the document page and the gutter shadow are thin lines along the whole page
/// height, which would put ink in every row; the back of the leaf shows
/// through as faint grey text. Thin vertical lines taller than a picture's
/// minimum height are therefore dropped before bands are built, and ink is
/// weighed by how dark it is, so faint marks count for little against the
/// recognized text.
///
/// Works for pictures that span the column with text above and below, which
/// is how clean-page sources place them. Text flowing beside a picture is not handled.
public struct PictureDetector: Sendable {
    /// Thresholds for the heuristics.
    public struct Options: Sendable, Equatable {
        /// Smallest height of a picture as a fraction of the page height;
        /// about three lines of body text. Lower bands are text or ornaments.
        /// A thin vertical line at least this tall is a page edge or a gutter
        /// shadow and is ignored.
        public var minimumHeight = 0.05
        /// How far a pixel may differ from the background, summed over the
        /// three channels, and still count as background. Small, because a
        /// picture's white ground is often only slightly lighter than the page.
        public var backgroundTolerance = 12
        /// A band with at least this share of its ink inside recognized text
        /// lines is text. Ink is weighed by its difference from the
        /// background, so faint show-through and specks count for little.
        public var textInkShare = 0.7
        /// Widest ink, as a fraction of the page width, that still counts as
        /// a thin vertical line (page edge, gutter shadow) when it runs at
        /// least ``minimumHeight`` down the page.
        public var maximumLineWidth = 0.015

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Picture regions from top to bottom, in normalized coordinates with
    /// the origin at the top-left corner.
    ///
    /// - Parameter lines: Text recognized on the same page, used to tell a
    ///   tall block of text from a picture.
    public func pictureRegions(in bitmap: PageBitmap, lines: [TextLine] = []) -> [CGRect] {
        guard bitmap.width > 0, bitmap.height > 0 else { return [] }
        let minimumRows = Int((options.minimumHeight * Double(bitmap.height)).rounded(.up))
        var ink = InkMap(bitmap: bitmap, tolerance: options.backgroundTolerance)
        // Page edges and the gutter shadow lie beside the text; the sides of
        // a frame round a picture lie within the text column and are kept.
        let textColumns = lines.isEmpty ? nil
            : Int(Double(lines.map(\.box.minX).min() ?? 0) * Double(bitmap.width)) ..<
            Int((Double(lines.map(\.box.maxX).max() ?? 0) * Double(bitmap.width)).rounded(.up))
        let lineWidth = max(1, Int(options.maximumLineWidth * Double(bitmap.width)))
        ink.eraseThinVerticalLines(maximumWidth: lineWidth, minimumLength: minimumRows, outside: textColumns)
        let spans = ink.spans()

        var regions: [CGRect] = []
        var row = 0
        while row < bitmap.height {
            guard spans[row] != nil else { row += 1; continue }
            var end = row
            var left = bitmap.width, right = 0
            while end < bitmap.height, let span = spans[end] {
                left = min(left, span.lowerBound)
                right = max(right, span.upperBound)
                end += 1
            }
            let band = Band(rows: row ..< end, columns: left ..< right)
            if band.rows.count >= minimumRows,
               ink.isFramed(rows: band.rows, columns: band.columns, lineWidth: lineWidth)
               || !isText(band, ink: ink, lines: lines)
            {
                regions.append(CGRect(
                    x: Double(left) / Double(bitmap.width),
                    y: Double(row) / Double(bitmap.height),
                    width: Double(right - left) / Double(bitmap.width),
                    height: Double(end - row) / Double(bitmap.height)
                ))
            }
            row = end
        }
        return regions
    }

    /// A run of consecutive rows with ink, and the columns the ink spans.
    private struct Band {
        var rows: Range<Int>
        var columns: Range<Int>
    }

    /// Whether the ink of `band` is accounted for by recognized text lines.
    private func isText(_ band: Band, ink: InkMap, lines: [TextLine]) -> Bool {
        // Line boxes in pixels, limited to the band.
        let boxes = lines.compactMap { line -> Band? in
            let rows = Int(Double(line.box.minY) * Double(ink.height)) ..<
                Int((Double(line.box.maxY) * Double(ink.height)).rounded(.up))
            let columns = Int(Double(line.box.minX) * Double(ink.width)) ..<
                Int((Double(line.box.maxX) * Double(ink.width)).rounded(.up))
            let clipped = Band(rows: rows.clamped(to: band.rows), columns: columns.clamped(to: band.columns))
            return clipped.rows.isEmpty || clipped.columns.isEmpty ? nil : clipped
        }
        guard !boxes.isEmpty else { return false }

        var total = 0, inText = 0
        var covered = [Bool](repeating: false, count: ink.width)
        for row in band.rows {
            for column in band.columns {
                covered[column] = false
            }
            for box in boxes where box.rows.contains(row) {
                for column in box.columns {
                    covered[column] = true
                }
            }
            for column in band.columns {
                let weight = Int(ink[column, row])
                total += weight
                if covered[column] {
                    inText += weight
                }
            }
        }
        return total > 0 && Double(inText) >= options.textInkShare * Double(total)
    }
}

/// How much each pixel of a page differs from the page's background: the
/// summed difference of the three channels, or zero within the tolerance.
private struct InkMap {
    let width: Int
    let height: Int
    private var weights: [UInt16]

    init(bitmap: PageBitmap, tolerance: Int) {
        width = bitmap.width
        height = bitmap.height
        let background = bitmap.backgroundColor
        weights = bitmap.pixels.withUnsafeBufferPointer { pixels in
            (0 ..< bitmap.width * bitmap.height).map { index in
                let offset = index * PageBitmap.bytesPerPixel
                let difference = abs(Int(pixels[offset]) - Int(background.red))
                    + abs(Int(pixels[offset + 1]) - Int(background.green))
                    + abs(Int(pixels[offset + 2]) - Int(background.blue))
                return difference > tolerance ? UInt16(difference) : 0
            }
        }
    }

    subscript(column: Int, row: Int) -> UInt16 {
        weights[row * width + column]
    }

    /// For every row, the columns from the first to just past the last ink
    /// pixel, or `nil` for a blank row.
    func spans() -> [Range<Int>?] {
        (0 ..< height).map { row in
            let base = row * width
            guard let first = (0 ..< width).first(where: { weights[base + $0] > 0 }),
                  let last = (first ..< width).last(where: { weights[base + $0] > 0 })
            else { return nil }
            return first ..< last + 1
        }
    }

    /// Erases chains of narrow ink runs that run at least `minimumLength`
    /// rows down the page: page edges and gutter shadows of a scan, straight
    /// or slightly slanted. A run joins the chain of a run in the same or a
    /// neighbouring column up to `minimumLength` rows above it, because a
    /// faint edge is broken into pieces where it fades below the tolerance.
    ///
    /// Text and pictures keep their ink where it matters: a glyph's strokes
    /// are short and lie in rows with other ink, and a picture's rows are
    /// wide. Only runs outside `textColumns`, the columns the recognized
    /// text spans, are erased, so the sides of a frame round a picture in
    /// the text column stay; with no text, any line goes, and thin strokes
    /// of a sparse drawing can then be erased too (see the illustrations
    /// feature page).
    mutating func eraseThinVerticalLines(maximumWidth: Int, minimumLength: Int, outside textColumns: Range<Int>?) {
        var chains = Chains()
        // The latest narrow run that covered each column.
        var latest = [Int?](repeating: nil, count: width)
        for row in 0 ..< height {
            for columns in runs(inRow: row) where columns.count <= maximumWidth {
                let run = chains.add(row: row, columns: columns)
                // Neighbouring columns count, so that a slanted line stays
                // one chain.
                for neighbour in max(0, columns.lowerBound - 1) ..< min(width, columns.upperBound + 1) {
                    if let above = latest[neighbour], chains.runs[above].row < row,
                       row - chains.runs[above].row <= minimumLength
                    {
                        chains.join(run, above)
                    }
                }
                for column in columns {
                    latest[column] = run
                }
            }
        }
        // Glyph strokes join chains too, across the gaps between lines, so a
        // chain may reach into the text; only its runs beside the text go.
        for run in chains.runs(inChainsSpanning: minimumLength) where !(textColumns?.overlaps(run.columns) ?? false) {
            for column in run.columns {
                weights[run.row * width + column] = 0
            }
        }
    }

    /// Whether a thin line runs down the left and the right edge of the
    /// area for at least four fifths of its rows: a frame round a picture,
    /// such as a clipping of printed text, which is a picture however well
    /// the engine reads its print. Counted column by column rather than by
    /// chains, as the chains of glyph strokes run into each other.
    func isFramed(rows: Range<Int>, columns: Range<Int>, lineWidth: Int) -> Bool {
        guard !rows.isEmpty, !columns.isEmpty else { return false }
        let edges = [
            max(0, columns.lowerBound - lineWidth) ..< min(width, columns.lowerBound + lineWidth),
            max(0, columns.upperBound - lineWidth) ..< min(width, columns.upperBound + lineWidth),
        ]
        var counts = [Int](repeating: 0, count: width)
        for row in rows {
            for run in runs(inRow: row) where run.count <= lineWidth && edges.contains(where: { $0.overlaps(run) }) {
                for column in run {
                    counts[column] += 1
                }
            }
        }
        let needed = (rows.count * 4 + 4) / 5
        return edges.allSatisfy { edge in edge.contains { counts[$0] >= needed } }
    }

    /// The runs of consecutive ink pixels in a row, left to right.
    private func runs(inRow row: Int) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var column = 0
        while column < width {
            guard self[column, row] > 0 else { column += 1; continue }
            var end = column
            while end < width, self[end, row] > 0 {
                end += 1
            }
            runs.append(column ..< end)
            column = end
        }
        return runs
    }
}

/// Runs of ink in single rows, joined into chains (a union-find forest).
private struct Chains {
    struct Run {
        var row: Int
        var columns: Range<Int>
    }

    private(set) var runs: [Run] = []
    private var parent: [Int] = []

    /// Adds a run as a chain of its own and returns its index.
    mutating func add(row: Int, columns: Range<Int>) -> Int {
        runs.append(Run(row: row, columns: columns))
        parent.append(parent.count)
        return runs.count - 1
    }

    mutating func join(_ first: Int, _ second: Int) {
        parent[root(first)] = root(second)
    }

    /// The runs of every chain whose rows, from its top run to its bottom
    /// run, number at least `length`.
    mutating func runs(inChainsSpanning length: Int) -> [Run] {
        var top: [Int: Int] = [:], bottom: [Int: Int] = [:]
        for (index, run) in runs.enumerated() {
            let chain = root(index)
            top[chain] = min(top[chain] ?? run.row, run.row)
            bottom[chain] = max(bottom[chain] ?? run.row, run.row)
        }
        return runs.indices.compactMap { index in
            let chain = root(index)
            guard let first = top[chain], let last = bottom[chain], last - first + 1 >= length else { return nil }
            return runs[index]
        }
    }

    private mutating func root(_ run: Int) -> Int {
        var run = run
        while parent[run] != run {
            parent[run] = parent[parent[run]]
            run = parent[run]
        }
        return run
    }
}
