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
        guard let page = PageImage(url: url) else { throw PictureExtractionError.unreadableImage(url) }
        let image = page.image, bitmap = page.bitmap

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

    private static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
