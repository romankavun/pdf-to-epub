import CoreGraphics
import Foundation
import ImageIO
import LayoutAnalysis
import OCR
import UniformTypeIdentifiers

/// Finds pictures with ``PictureDetector`` and crops them from the page
/// image file.
///
/// Crops are stored as PNG, without scaling: the pages are clean pages, and
/// a lossless copy of the pixels is the most faithful reproduction.
public struct ImagePictureExtractor: PictureExtractor {
    private let detector: PictureDetector

    public init(detector: PictureDetector = PictureDetector()) {
        self.detector = detector
    }

    public func pictures(inImageAt url: URL, lines: [TextLine]) throws -> [ExtractedPicture] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bitmap = Self.bitmap(of: image)
        else { throw PictureExtractionError.unreadableImage(url) }

        return try detector.pictureRegions(in: bitmap, lines: lines).map { region in
            let pixels = CGRect(
                x: region.minX * CGFloat(image.width), y: region.minY * CGFloat(image.height),
                width: region.width * CGFloat(image.width), height: region.height * CGFloat(image.height)
            ).integral
            guard let crop = image.cropping(to: pixels), let data = Self.pngData(of: crop) else {
                throw PictureExtractionError.cannotEncode(url)
            }
            return ExtractedPicture(box: region, pngData: data)
        }
    }

    /// Draws the image into plain RGBX bytes, flattening any transparency
    /// and colour profile.
    private static func bitmap(of image: CGImage) -> PageBitmap? {
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
        return drawn ? PageBitmap(width: width, height: height, pixels: pixels) : nil
    }

    private static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
