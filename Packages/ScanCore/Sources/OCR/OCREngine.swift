import CoreGraphics
import Foundation

/// Something that can read the text on a page image.
///
/// The rest of the pipeline depends on this protocol rather than on Vision,
/// so it can be tested with canned pages.
public protocol OCREngine: Sendable {
    /// Recognizes the text lines on the image at `url`.
    ///
    /// - Parameter regions: Areas to blank out before recognition, in
    ///   normalized coordinates with the origin at the top-left corner. Note
    ///   markers are erased this way: left in place, they are fused into the
    ///   neighbouring word and misread.
    func recognize(imageAt url: URL, erasing regions: [CGRect]) async throws -> RecognizedPage

    /// Reads the short label (a number, a letter, a roman numeral) inside
    /// each region of the image at `url`.
    ///
    /// - Returns: One string per region, in the same order; empty where
    ///   nothing could be read. Labels are returned as read, so look-alike
    ///   characters (`I` for `1`) are still to be expected.
    func readLabels(inImageAt url: URL, regions: [CGRect]) async throws -> [String]
}

public extension OCREngine {
    /// Recognizes the text lines on the image at `url` as it is.
    func recognize(imageAt url: URL) async throws -> RecognizedPage {
        try await recognize(imageAt: url, erasing: [])
    }
}

/// Why a page could not be recognized.
public enum OCRError: Error, Equatable, Sendable {
    /// The file is missing or is not an image the system can decode.
    case unreadableImage(URL)
    /// Recognition of the image did not finish in time, even after retries.
    case timedOut(URL)
}
