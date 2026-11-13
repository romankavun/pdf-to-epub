import CoreGraphics
import Foundation
import OCR

/// Something that can find the illustrations on a page image and cut them
/// out.
///
/// The converter depends on this protocol rather than on image decoding, so
/// it can be tested with canned pictures.
public protocol PictureExtractor: Sendable {
    /// The illustrations on the image at `url`.
    ///
    /// - Parameter lines: Text recognized on the same page; it helps tell a
    ///   block of large text from a picture.
    func pictures(inImageAt url: URL, lines: [TextLine]) throws -> [ExtractedPicture]
}

/// An illustration cut out of a page.
public struct ExtractedPicture: Sendable, Equatable {
    /// Where the picture was on the page, normalized, origin at the top-left
    /// corner.
    public var box: CGRect
    /// The picture alone, encoded as PNG at the page's resolution.
    public var pngData: Data

    public init(box: CGRect, pngData: Data) {
        self.box = box
        self.pngData = pngData
    }
}

/// Why the pictures of a page could not be extracted.
public enum PictureExtractionError: Error, Equatable, Sendable {
    /// The file is missing or is not an image the system can decode.
    case unreadableImage(URL)
    /// A region of the image at this URL could not be cropped or encoded.
    case cannotEncode(URL)
}
