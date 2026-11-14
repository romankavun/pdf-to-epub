import CoreGraphics

/// The pixels of a page image as plain values, so that pixel-based heuristics
/// can be tested on pages built in code and do not depend on an image
/// framework.
public struct PageBitmap: Sendable, Equatable {
    /// An opaque colour. Alpha is not modelled: pages are flattened on load.
    public struct Color: Sendable, Equatable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Bytes per pixel in ``pixels``.
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    /// RGBX bytes, four per pixel, rows from the top of the page down. The
    /// fourth byte of each pixel is ignored.
    public private(set) var pixels: [UInt8]

    /// - Returns: `nil` when `pixels` does not hold exactly
    ///   `width * height * 4` bytes or a dimension is negative.
    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width >= 0, height >= 0, pixels.count == width * height * Self.bytesPerPixel else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A page of a single colour.
    public init(width: Int, height: Int, color: Color) {
        self.width = max(0, width)
        self.height = max(0, height)
        pixels = []
        pixels.reserveCapacity(self.width * self.height * Self.bytesPerPixel)
        for _ in 0 ..< self.width * self.height {
            pixels += [color.red, color.green, color.blue, 255]
        }
    }

    /// Paints a rectangle given in pixels, clipped to the page.
    public mutating func fill(x: Int, y: Int, width: Int, height: Int, with color: Color) {
        for row in max(0, y) ..< max(0, min(self.height, y + height)) {
            for column in max(0, x) ..< max(0, min(self.width, x + width)) {
                let offset = (row * self.width + column) * Self.bytesPerPixel
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
            }
        }
    }

    /// The colour of the page itself: the most common colour on its border.
    /// Black for an empty bitmap.
    public var backgroundColor: Color {
        guard width > 0, height > 0 else { return Color(red: 0, green: 0, blue: 0) }
        var counts: [UInt32: Int] = [:]
        func count(_ column: Int, _ row: Int) {
            let offset = (row * width + column) * Self.bytesPerPixel
            let key = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2])
            counts[key, default: 0] += 1
        }
        for column in 0 ..< width {
            count(column, 0)
            count(column, height - 1)
        }
        for row in 0 ..< height {
            count(0, row)
            count(width - 1, row)
        }
        // Ties are broken by value so that the result does not depend on
        // dictionary order.
        let key = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key ?? 0
        return Color(red: UInt8(key >> 16 & 0xFF), green: UInt8(key >> 8 & 0xFF), blue: UInt8(key & 0xFF))
    }
}

public extension PageBitmap {
    /// How much of an area is covered by ink, 0...1: the average difference
    /// from the page's background colour, so that the soft edges of
    /// anti-aliased strokes count in proportion to their coverage.
    ///
    /// Used to tell bold from regular text, whose only difference at the
    /// same typeface is stroke thickness. The number means something only
    /// next to the same measure of other lines of the document.
    ///
    /// - Parameter region: Normalized, origin at the top-left corner;
    ///   clipped to the page. Zero when nothing of it lies on the page.
    func inkDensity(in region: CGRect) -> Double {
        let left = max(0, Int((region.minX * Double(width)).rounded(.down)))
        let right = min(width, Int((region.maxX * Double(width)).rounded(.up)))
        let top = max(0, Int((region.minY * Double(height)).rounded(.down)))
        let bottom = min(height, Int((region.maxY * Double(height)).rounded(.up)))
        guard left < right, top < bottom else { return 0 }

        let background = backgroundColor
        var total = 0
        for row in top ..< bottom {
            for column in left ..< right {
                let offset = (row * width + column) * Self.bytesPerPixel
                total += abs(Int(pixels[offset]) - Int(background.red))
                    + abs(Int(pixels[offset + 1]) - Int(background.green))
                    + abs(Int(pixels[offset + 2]) - Int(background.blue))
            }
        }
        return Double(total) / Double((right - left) * (bottom - top) * 3 * 255)
    }
}
