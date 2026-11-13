import CoreGraphics
import Foundation
import ImageIO
import LayoutAnalysis

/// A page image file decoded for pixel analysis.
struct PageImage {
    let image: CGImage
    let bitmap: PageBitmap

    /// - Returns: `nil` when the file is missing or cannot be decoded.
    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        // Drawn into plain RGBX bytes, which flattens any transparency and
        // colour profile.
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * PageBitmap.bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * PageBitmap.bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            // The first byte row of a bitmap context is the top of the image.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let bitmap = PageBitmap(width: width, height: height, pixels: pixels) else { return nil }
        self.image = image
        self.bitmap = bitmap
    }
}
