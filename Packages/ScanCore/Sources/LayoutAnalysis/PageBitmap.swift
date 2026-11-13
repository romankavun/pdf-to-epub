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
}
