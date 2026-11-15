import CoreGraphics
import DocumentModel
import OCR

/// Everything found on one page that layout analysis works from.
public struct PageContent: Sendable, Equatable {
    /// Recognized text lines, in any order. May include text recognized
    /// inside ``pictures``; the analyzer discards it.
    public var lines: [TextLine]
    /// Illustrations on the page.
    public var pictures: [PagePicture]

    /// Note markers found on the page by their colour. The text of
    /// ``lines`` is expected not to contain them: they are erased before
    /// recognition.
    public var markers: [NoteMarker]

    /// How heavy the strokes are on each line, measured from the page
    /// image. Empty when the page was not measured, in which case no line
    /// counts as bold.
    public var lineInk: [LineInk]

    public init(
        lines: [TextLine], pictures: [PagePicture] = [], markers: [NoteMarker] = [], lineInk: [LineInk] = []
    ) {
        self.lines = lines
        self.pictures = pictures
        self.markers = markers
        self.lineInk = lineInk
    }
}

/// The weight of the ink in one area of a page: the share of its pixels
/// that are text rather than background.
///
/// Bold text has thicker strokes, so at the same typeface its share is
/// clearly higher than that of the body text. Only the comparison with the
/// rest of the document is meaningful, never the number itself.
public struct LineInk: Sendable, Equatable {
    /// The measured area on the page, normalized, origin at the top-left.
    public var box: CGRect
    /// Share of the area covered by ink, 0...1.
    public var density: Double

    public init(box: CGRect, density: Double) {
        self.box = box
        self.density = density
    }
}

/// A note marker located on a page: a reference inside the text, or the
/// label that opens the text of a note.
public struct NoteMarker: Sendable, Equatable {
    /// Position on the page, normalized, origin at the top-left corner.
    public var box: CGRect
    /// The marker as read by OCR: possibly empty or with look-alike
    /// characters. Layout analysis repairs it from the numbering sequence.
    public var label: String

    public init(box: CGRect, label: String) {
        self.box = box
        self.label = label
    }
}

/// An illustration located on a page.
public struct PagePicture: Sendable, Equatable {
    /// Identifier of the cropped image in ``Document/images``.
    public var imageID: ImageResource.ID
    /// Position on the page, normalized, origin at the top-left corner.
    public var box: CGRect

    public init(imageID: ImageResource.ID, box: CGRect) {
        self.imageID = imageID
        self.box = box
    }
}
