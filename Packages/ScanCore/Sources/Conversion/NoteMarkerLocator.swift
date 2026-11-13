import CoreGraphics
import Foundation
import LayoutAnalysis

/// Something that can find the note markers on a page image.
///
/// The converter depends on this protocol rather than on image decoding, so
/// it can be tested with canned markers.
public protocol NoteMarkerLocator: Sendable {
    /// The boxes of the note markers on the image at `url`, normalized, with
    /// the origin at the top-left corner, in reading order.
    func markers(inImageAt url: URL) throws -> [CGRect]
}

/// Finds note markers in a page image file with ``NoteMarkerDetector``.
public struct ImageNoteMarkerLocator: NoteMarkerLocator {
    private let detector: NoteMarkerDetector

    public init(detector: NoteMarkerDetector = NoteMarkerDetector()) {
        self.detector = detector
    }

    public func markers(inImageAt url: URL) throws -> [CGRect] {
        guard let page = PageImage(url: url) else { throw PictureExtractionError.unreadableImage(url) }
        return detector.markerRegions(in: page.bitmap)
    }
}
