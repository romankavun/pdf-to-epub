/// The pixels of a page image as plain values, so that preprocessing can be
/// tested on pages built in code.
///
/// Kept apart from `LayoutAnalysis.PageBitmap` on purpose: preprocessing
/// runs before layout analysis and must not depend on it.
public struct ScanBitmap: Sendable, Equatable {
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

    /// An image of one grey level.
    public init(width: Int, height: Int, gray: UInt8) {
        self.width = max(0, width)
        self.height = max(0, height)
        pixels = [UInt8](repeating: gray, count: self.width * self.height * Self.bytesPerPixel)
    }

    /// Sets one pixel; coordinates outside the image are ignored.
    public mutating func setColor(red: UInt8, green: UInt8, blue: UInt8, x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = (y * width + x) * Self.bytesPerPixel
        pixels[offset] = red
        pixels[offset + 1] = green
        pixels[offset + 2] = blue
    }

    /// The colour of one pixel, which must lie in the image.
    public func color(x: Int, y: Int) -> ScanColor {
        let offset = (y * width + x) * Self.bytesPerPixel
        return ScanColor(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }

    /// The part of the image inside `rect`, clipped to the image.
    public func cropped(to rect: PixelRect) -> ScanBitmap {
        let left = max(0, rect.x), top = max(0, rect.y)
        let right = min(width, rect.x + rect.width), bottom = min(height, rect.y + rect.height)
        guard left < right, top < bottom else { return ScanBitmap(width: 0, height: 0, gray: 0) }
        var cropped: [UInt8] = []
        cropped.reserveCapacity((right - left) * (bottom - top) * Self.bytesPerPixel)
        for row in top ..< bottom {
            let start = (row * width + left) * Self.bytesPerPixel
            cropped.append(contentsOf: pixels[start ..< start + (right - left) * Self.bytesPerPixel])
        }
        return ScanBitmap(uncheckedWidth: right - left, height: bottom - top, pixels: cropped)
    }

    /// For pixels built by this module, whose count is right by construction.
    init(uncheckedWidth width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// An opaque colour of a ``ScanBitmap`` pixel.
public struct ScanColor: Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The colour as one number, for counting colours.
    var key: UInt32 {
        UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }
}

/// A rectangle in whole pixels, origin at the top-left corner of the image.
public struct PixelRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
