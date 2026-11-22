import CoreGraphics

/// Finds note markers on a page by their colour.
///
/// The sample sets draw a note reference, and the label that starts a note's
/// text, as a link: a short token in a saturated blue next to ordinary dark
/// text. The colour is a far better signal than the recognized text, where
/// the marker is fused into the neighbouring word and often misread
/// (ADR 0001, ADR 0003).
///
/// Link-coloured text that is not a marker is left alone: a contents entry
/// has no dark text beside it, and a web address is much longer than a
/// marker.
public struct NoteMarkerDetector: Sendable {
    /// Thresholds for the heuristics.
    public struct Options: Sendable, Equatable {
        /// A pixel is link-coloured when its blue channel exceeds both other
        /// channels by more than this.
        public var minimumBlueExcess = 50
        /// Smallest height of a marker as a fraction of the page height.
        /// Anything lower is a stray pixel.
        public var minimumHeight = 0.004
        /// A marker is at most this many times wider than the height of the
        /// link-coloured ink on its line; longer runs are links.
        public var maximumAspect = 4.0
        /// How different from the background, summed over three channels, a
        /// neutral pixel must be to count as dark text beside a marker.
        public var minimumTextContrast = 150

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Marker boxes from top to bottom and, on one line, left to right, in
    /// normalized coordinates with the origin at the top-left corner.
    public func markerRegions(in bitmap: PageBitmap) -> [CGRect] {
        guard bitmap.width > 0, bitmap.height > 0 else { return [] }
        let background = bitmap.backgroundColor
        let minimumRows = options.minimumHeight * Double(bitmap.height)

        return bitmap.pixels.withUnsafeBufferPointer { pixels in
            let view = PixelView(pixels: pixels, width: bitmap.width, background: background, options: options)
            let linkColumns = (0 ..< bitmap.height).map { row in
                (0 ..< bitmap.width).filter { view.isLink(column: $0, row: row) }
            }
            var regions: [CGRect] = []
            var row = 0
            while row < bitmap.height {
                guard !linkColumns[row].isEmpty else { row += 1; continue }
                var end = row
                while end < bitmap.height, !linkColumns[end].isEmpty {
                    end += 1
                }
                let band = row ..< end
                for columns in runs(of: linkColumns[band].joined(), maximumGap: max(2, band.count * 6 / 10)) {
                    // The rows this run really occupies: a raised reference
                    // is lower than the band of its line.
                    let rows = band.filter { linkColumns[$0].contains(where: columns.contains) }
                    guard let top = rows.first, let bottom = rows.last,
                          Double(bottom - top + 1) >= minimumRows,
                          Double(columns.count) <= options.maximumAspect * Double(band.count),
                          view.hasText(beside: columns, rows: top ..< bottom + 1, within: band.count)
                    else { continue }
                    regions.append(CGRect(
                        x: Double(columns.lowerBound) / Double(bitmap.width),
                        y: Double(top) / Double(bitmap.height),
                        width: Double(columns.count) / Double(bitmap.width),
                        height: Double(bottom - top + 1) / Double(bitmap.height)
                    ))
                }
                row = end
            }
            return regions
        }
    }

    /// Groups column indices into runs separated by more than `maximumGap`
    /// empty columns, left to right.
    private func runs(of columns: some Sequence<Int>, maximumGap: Int) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        for column in Set(columns).sorted() {
            if let last = runs.last, column - last.upperBound <= maximumGap {
                runs[runs.count - 1] = last.lowerBound ..< column + 1
            } else {
                runs.append(column ..< column + 1)
            }
        }
        return runs
    }
}

/// Classifies the pixels of a page for marker detection.
private struct PixelView {
    let pixels: UnsafeBufferPointer<UInt8>
    let width: Int
    let background: PageBitmap.Color
    let options: NoteMarkerDetector.Options

    private func blueExcess(_ offset: Int) -> Int {
        Int(pixels[offset + 2]) - max(Int(pixels[offset]), Int(pixels[offset + 1]))
    }

    func isLink(column: Int, row: Int) -> Bool {
        blueExcess((row * width + column) * PageBitmap.bytesPerPixel) > options.minimumBlueExcess
    }

    /// Dark and colourless: ordinary text, not the pale fringe of a
    /// link-coloured glyph.
    private func isText(column: Int, row: Int) -> Bool {
        let offset = (row * width + column) * PageBitmap.bytesPerPixel
        let contrast = abs(Int(pixels[offset]) - Int(background.red))
            + abs(Int(pixels[offset + 1]) - Int(background.green))
            + abs(Int(pixels[offset + 2]) - Int(background.blue))
        return contrast > options.minimumTextContrast && blueExcess(offset) < options.minimumBlueExcess / 2
    }

    /// Whether ordinary text lies within `distance` pixels to the left or
    /// right of `columns` on the given rows.
    func hasText(beside columns: Range<Int>, rows: Range<Int>, within distance: Int) -> Bool {
        let left = max(0, columns.lowerBound - distance) ..< columns.lowerBound
        let right = columns.upperBound ..< min(width, columns.upperBound + distance)
        return rows.contains { row in
            left.contains { isText(column: $0, row: row) } || right.contains { isText(column: $0, row: row) }
        }
    }
}
