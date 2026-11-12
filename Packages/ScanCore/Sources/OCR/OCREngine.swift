import Foundation

/// Something that can read the text on a page image.
///
/// The rest of the pipeline depends on this protocol rather than on Vision,
/// so it can be tested with canned pages.
public protocol OCREngine: Sendable {
    /// Recognizes the text lines on the image at `url`.
    func recognize(imageAt url: URL) async throws -> RecognizedPage
}

/// Why a page could not be recognized.
public enum OCRError: Error, Equatable, Sendable {
    /// The file is missing or is not an image the system can decode.
    case unreadableImage(URL)
}
