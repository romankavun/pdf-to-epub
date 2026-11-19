/// Whitens the paper of a cropped scanned page and removes what lies around
/// the text: page edges, the gutter shadow, corner ticks and show-through.
///
/// Two passes:
///
/// 1. **Levels.** The paper's brightness is measured in small tiles, so a
///    gradual shadow or uneven yellowing is followed, and every pixel is
///    scaled so that anything a little darker than the local paper becomes
///    white. Show-through from the back of the page is faint grey, a few
///    shades darker than the paper, and goes with it. All three channels of
///    a pixel are scaled by the same factor, so a coloured pixel keeps its
///    hue: link-coloured note markers stay detectable by colour.
/// 2. **Debris.** Dark or grey connected shapes that touch the image's
///    border (a gutter shadow, the bed beyond a page edge) are painted
///    white, and so are long thin shapes in the outer band (page edges,
///    ticks) and anything in a corner of the band. Shapes of the size of
///    letters elsewhere in the band are kept: they are page numbers and
///    running lines.
///
/// Pictures on the page are scaled like the paper, so their lightest tones
/// turn white; that is the price of a clean page for recognition.
public struct BackgroundCleaner: Sendable {
    /// The side of the square tiles the paper level is measured in, px.
    static let tileSize = 32
    /// How much darker than the local paper a pixel may be and still turn
    /// white. Show-through on the sample scans was at most about 30 shades
    /// below the paper; the lightest anti-aliased text edges are lost too,
    /// which recognition does not mind.
    static let whiteMargin = 30
    /// A tile darker than the page's paper by more than this is not paper
    /// (a picture, a dense heading, a deep shadow) and does not set the
    /// level.
    static let maximumShadow = 40
    /// A pixel at most this bright, after levels, is a mark for debris
    /// search. Page edges are often only grey, so it is well above text ink.
    static let inkLevel = 230
    /// The outer band where thin shapes are debris, as a share of the
    /// shorter side.
    static let band = 0.05

    public init() {}

    /// The page with white paper and without debris around the text.
    ///
    /// Not idempotent: every pass darkens mid-tones a little, so a page is
    /// cleaned once, when it is first prepared.
    public func cleaned(_ bitmap: ScanBitmap) -> ScanBitmap {
        guard bitmap.width > 0, bitmap.height > 0 else { return bitmap }
        var result = levelled(bitmap)
        removeDebris(from: &result)
        return result
    }

    // MARK: - Levels

    private func levelled(_ bitmap: ScanBitmap) -> ScanBitmap {
        let width = bitmap.width, height = bitmap.height
        let luminance = bitmap.luminance
        let paper = Self.mode(of: luminance.filter { $0 >= 96 }) ?? 255
        let tile = Self.tileSize
        let columns = (width + tile - 1) / tile, rows = (height + tile - 1) / tile

        // The 90th percentile of a tile is paper unless text covers most
        // of it.
        var levels = [Int](repeating: paper, count: columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                var histogram = [Int](repeating: 0, count: 256)
                var count = 0
                for y in row * tile ..< min(height, (row + 1) * tile) {
                    for x in column * tile ..< min(width, (column + 1) * tile) {
                        histogram[Int(luminance[y * width + x])] += 1
                        count += 1
                    }
                }
                let level = Self.percentile(0.9, of: histogram, count: count)
                levels[row * columns + column] = level < paper - Self.maximumShadow ? paper : level
            }
        }

        var pixels = bitmap.pixels
        for y in 0 ..< height {
            for x in 0 ..< width {
                let level = Self.interpolated(levels, columns: columns, rows: rows, x: x, y: y)
                let white = max(64.0, level - Double(Self.whiteMargin))
                let scale = 255 / white
                let offset = (y * width + x) * ScanBitmap.bytesPerPixel
                for channel in 0 ..< 3 {
                    pixels[offset + channel] = UInt8(min(255, (Double(pixels[offset + channel]) * scale).rounded()))
                }
            }
        }
        return ScanBitmap(uncheckedWidth: width, height: height, pixels: pixels)
    }

    /// The paper level at a pixel, interpolated between tile centres.
    private static func interpolated(_ levels: [Int], columns: Int, rows: Int, x: Int, y: Int) -> Double {
        let tile = Double(tileSize)
        let fx = min(max(0, (Double(x) + 0.5) / tile - 0.5), Double(columns - 1))
        let fy = min(max(0, (Double(y) + 0.5) / tile - 0.5), Double(rows - 1))
        let left = Int(fx), top = Int(fy)
        let right = min(columns - 1, left + 1), bottom = min(rows - 1, top + 1)
        let dx = fx - Double(left), dy = fy - Double(top)
        func level(_ column: Int, _ row: Int) -> Double {
            Double(levels[row * columns + column])
        }
        let upper = level(left, top) * (1 - dx) + level(right, top) * dx
        let lower = level(left, bottom) * (1 - dx) + level(right, bottom) * dx
        return upper * (1 - dy) + lower * dy
    }

    private static func mode(of values: [UInt8]) -> Int? {
        guard !values.isEmpty else { return nil }
        var histogram = [Int](repeating: 0, count: 256)
        for value in values {
            histogram[Int(value)] += 1
        }
        return histogram.indices.max { histogram[$0] < histogram[$1] }
    }

    private static func percentile(_ fraction: Double, of histogram: [Int], count: Int) -> Int {
        let target = Int((Double(count) * fraction).rounded(.up))
        var seen = 0
        for (value, number) in histogram.enumerated() {
            seen += number
            if seen >= target {
                return value
            }
        }
        return 255
    }

    // MARK: - Debris

    private func removeDebris(from bitmap: inout ScanBitmap) {
        let width = bitmap.width, height = bitmap.height
        let luminance = bitmap.luminance
        let ink = luminance.map { Int($0) <= Self.inkLevel }
        let shapes = Shape.find(in: ink, width: width, height: height)
        guard !shapes.isEmpty else { return }

        let band = max(4, Int(Self.band * Double(min(width, height))))
        // Letters are the common case; their height is the yardstick for
        // "long".
        let heights = shapes.filter { $0.area >= 8 }.map(\.height).sorted()
        let letterHeight = heights.isEmpty ? 8 : heights[heights.count / 2]

        for shape in shapes {
            let touchesBorder = shape.minX == 0 || shape.minY == 0
                || shape.maxX == width - 1 || shape.maxY == height - 1
            let inSideBand = shape.maxX < band || shape.minX >= width - band
            let inEndBand = shape.maxY < band || shape.minY >= height - band
            let long = max(shape.width, shape.height) >= 2 * letterHeight
                && max(shape.width, shape.height) >= 4 * min(shape.width, shape.height)
            // Text never reaches a corner of the band: page numbers and
            // running lines stay within the text column.
            let inCorner = inSideBand && inEndBand
            guard touchesBorder || inCorner || ((inSideBand || inEndBand) && long) else { continue }
            for index in shape.pixels {
                // The shape and its anti-aliased rim.
                let x = index % width, y = index / width
                for ny in max(0, y - 1) ... min(height - 1, y + 1) {
                    for nx in max(0, x - 1) ... min(width - 1, x + 1) {
                        bitmap.setColor(red: 255, green: 255, blue: 255, x: nx, y: ny)
                    }
                }
            }
        }
    }
}

/// A set of 8-connected ink pixels.
private struct Shape {
    var pixels: [Int] = []
    var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min

    var width: Int {
        maxX - minX + 1
    }

    var height: Int {
        maxY - minY + 1
    }

    var area: Int {
        pixels.count
    }

    /// The connected shapes of `ink`, a row-major mask.
    static func find(in ink: [Bool], width: Int, height: Int) -> [Shape] {
        var visited = [Bool](repeating: false, count: ink.count)
        var shapes: [Shape] = []
        var stack: [Int] = []
        for start in ink.indices where ink[start] && !visited[start] {
            var shape = Shape()
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                shape.pixels.append(index)
                shape.minX = min(shape.minX, x)
                shape.maxX = max(shape.maxX, x)
                shape.minY = min(shape.minY, y)
                shape.maxY = max(shape.maxY, y)
                for ny in max(0, y - 1) ... min(height - 1, y + 1) {
                    for nx in max(0, x - 1) ... min(width - 1, x + 1) {
                        let next = ny * width + nx
                        if ink[next], !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            shapes.append(shape)
        }
        return shapes
    }
}

extension ScanBitmap {
    /// The mean of the three channels of every pixel, row by row.
    var luminance: [UInt8] {
        var values = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeBufferPointer { pixels in
            for index in values.indices {
                let offset = index * Self.bytesPerPixel
                values[index] = UInt8((Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3)
            }
        }
        return values
    }
}
