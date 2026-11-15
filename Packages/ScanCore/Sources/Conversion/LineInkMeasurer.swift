import Foundation
import LayoutAnalysis
import OCR

/// Something that can measure how heavy the ink of each recognized line is.
///
/// The converter depends on this protocol rather than on image decoding, so
/// it can be tested with canned measurements.
public protocol LineInkMeasurer: Sendable {
    /// The ink of every line of the page image at `url`.
    func ink(inImageAt url: URL, lines: [TextLine]) throws -> [LineInk]
}

/// Measures lines in a page image file with ``PageBitmap/inkDensity(in:)``.
public struct ImageLineInkMeasurer: LineInkMeasurer {
    public init() {}

    public func ink(inImageAt url: URL, lines: [TextLine]) throws -> [LineInk] {
        guard !lines.isEmpty else { return [] }
        guard let page = PageImage(url: url) else { throw PictureExtractionError.unreadableImage(url) }
        return lines.map { LineInk(box: $0.box, density: page.bitmap.inkDensity(in: $0.box)) }
    }
}
