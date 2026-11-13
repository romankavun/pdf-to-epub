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
/// Works for pictures that span the column with text above and below, which
/// is how clean-page sources place them. Text flowing beside a picture is not handled.
public struct PictureDetector: Sendable {
    /// Thresholds for the heuristics.
    public struct Options: Sendable, Equatable {
        /// Smallest height of a picture as a fraction of the page height;
        /// about three lines of body text. Lower bands are text or ornaments.
        public var minimumHeight = 0.05
        /// How far a pixel may differ from the background, summed over the
        /// three channels, and still count as background. Small, because a
        /// picture's white ground is often only slightly lighter than the page.
        public var backgroundTolerance = 12
        /// A band with at least this share of its ink inside recognized text
        /// lines is text.
        public var textInkShare = 0.7

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
        let spans = inkSpans(in: bitmap, background: bitmap.backgroundColor)
        let minimumRows = Int((options.minimumHeight * Double(bitmap.height)).rounded(.up))

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
            if band.rows.count >= minimumRows, !isText(band, in: bitmap, lines: lines) {
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

    /// For every row, the columns from the first to just past the last
    /// non-background pixel, or `nil` for a blank row.
    private func inkSpans(in bitmap: PageBitmap, background: PageBitmap.Color) -> [Range<Int>?] {
        bitmap.pixels.withUnsafeBufferPointer { pixels in
            (0 ..< bitmap.height).map { row in
                let base = row * bitmap.width * PageBitmap.bytesPerPixel
                func isInk(_ column: Int) -> Bool {
                    self.isInk(pixels, at: base + column * PageBitmap.bytesPerPixel, background: background)
                }
                guard let first = (0 ..< bitmap.width).first(where: isInk),
                      let last = (first ..< bitmap.width).last(where: isInk)
                else { return nil }
                return first ..< last + 1
            }
        }
    }

    private func isInk(
        _ pixels: UnsafeBufferPointer<UInt8>, at offset: Int, background: PageBitmap.Color
    ) -> Bool {
        let difference = abs(Int(pixels[offset]) - Int(background.red))
            + abs(Int(pixels[offset + 1]) - Int(background.green))
            + abs(Int(pixels[offset + 2]) - Int(background.blue))
        return difference > options.backgroundTolerance
    }

    /// Whether the ink of `band` is accounted for by recognized text lines.
    private func isText(_ band: Band, in bitmap: PageBitmap, lines: [TextLine]) -> Bool {
        // Line boxes in pixels, limited to the band.
        let boxes = lines.compactMap { line -> Band? in
            let rows = Int(Double(line.box.minY) * Double(bitmap.height)) ..<
                Int((Double(line.box.maxY) * Double(bitmap.height)).rounded(.up))
            let columns = Int(Double(line.box.minX) * Double(bitmap.width)) ..<
                Int((Double(line.box.maxX) * Double(bitmap.width)).rounded(.up))
            let clipped = Band(rows: rows.clamped(to: band.rows), columns: columns.clamped(to: band.columns))
            return clipped.rows.isEmpty || clipped.columns.isEmpty ? nil : clipped
        }
        guard !boxes.isEmpty else { return false }

        let background = bitmap.backgroundColor
        var ink = 0, inkInText = 0
        bitmap.pixels.withUnsafeBufferPointer { pixels in
            var covered = [Bool](repeating: false, count: bitmap.width)
            for row in band.rows {
                for column in band.columns {
                    covered[column] = false
                }
                for box in boxes where box.rows.contains(row) {
                    for column in box.columns {
                        covered[column] = true
                    }
                }
                let base = row * bitmap.width * PageBitmap.bytesPerPixel
                for column in band.columns
                    where isInk(pixels, at: base + column * PageBitmap.bytesPerPixel, background: background)
                {
                    ink += 1
                    if covered[column] {
                        inkInText += 1
                    }
                }
            }
        }
        return ink > 0 && Double(inkInText) >= options.textInkShare * Double(ink)
    }
}
