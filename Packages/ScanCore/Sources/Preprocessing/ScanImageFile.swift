import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading and writing ``ScanBitmap`` as image files.
public enum ScanImageFile {
    /// The image at `url` drawn into RGBX bytes, which flattens any
    /// transparency and colour profile; `nil` when it cannot be decoded.
    ///
    /// Device RGB, like the rest of the package reads pages, so a page
    /// written by ``writePNG(_:to:)`` reads back with the same values here
    /// and in later stages.
    public static func read(_ url: URL) -> ScanBitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * ScanBitmap.bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = context(for: buffer.baseAddress, width: width, height: height) else { return false }
            // The first byte row of a bitmap context is the top of the image.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ScanBitmap(width: width, height: height, pixels: pixels) : nil
    }

    /// Writes `bitmap` as a PNG at `url`, replacing a file there. PNG is
    /// lossless, so link colours survive for note-marker detection.
    ///
    /// - Returns: Whether the file was written.
    public static func writePNG(_ bitmap: ScanBitmap, to url: URL) -> Bool {
        guard bitmap.width > 0, bitmap.height > 0 else { return false }
        var pixels = bitmap.pixels
        let image = pixels.withUnsafeMutableBytes { buffer in
            context(for: buffer.baseAddress, width: bitmap.width, height: bitmap.height)?.makeImage()
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func context(for data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * ScanBitmap.bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    }
}
