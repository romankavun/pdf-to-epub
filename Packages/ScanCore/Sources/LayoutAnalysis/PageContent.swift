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

    public init(lines: [TextLine], pictures: [PagePicture] = []) {
        self.lines = lines
        self.pictures = pictures
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
