import Foundation

/// Something that turns a page image into the image the rest of the
/// pipeline should read.
///
/// The converter depends on this protocol rather than on image decoding, so
/// it can be tested with canned files.
public protocol PagePreparing: Sendable {
    /// What kind of input the document with these pages is; decided once, before
    /// any page is prepared.
    func profile(ofDocumentWith pageURLs: [URL]) throws -> InputProfile

    /// The image to recognize for the page at `url` of a document of `profile`:
    /// a new file when the page was prepared, `url` itself when it was not.
    func prepare(pageAt url: URL, as profile: InputProfile) throws -> URL
}

/// Why a page could not be prepared.
public enum PreprocessingError: Error, Equatable {
    /// The file is missing or is not an image.
    case unreadableImage(URL)
    /// The prepared image could not be written.
    case cannotWrite(URL)
}

/// Prepares scanned pages for recognition and writes them as PNG files into
/// a folder: crops the page off the scanner bed (``PageCrop``), then whitens
/// its paper and removes debris around the text (``BackgroundCleaner``),
/// and rotates its lines level (``Deskew``).
///
/// Every later stage (recognition, note-marker colours, ink weight,
/// picture crops, the review) reads the prepared file, so all of them agree
/// on page coordinates. Pages of a document of clean pages are not touched; every
/// page of a scanned document is written, so all of them end up in one folder.
public struct ScanPagePreparer: PagePreparing {
    private let folder: URL
    private let crop: PageCrop
    private let cleaner: BackgroundCleaner
    private let deskew: Deskew

    /// - Parameter folder: Where prepared pages are written, under the name
    ///   of the original file with a `.png` extension. It must exist; a file
    ///   of the same name is replaced.
    public init(
        folder: URL,
        crop: PageCrop = PageCrop(),
        cleaner: BackgroundCleaner = BackgroundCleaner(),
        deskew: Deskew = Deskew()
    ) {
        self.folder = folder
        self.crop = crop
        self.cleaner = cleaner
        self.deskew = deskew
    }

    /// Samples a few pages spread over the document; see ``InputProfile``.
    public func profile(ofDocumentWith pageURLs: [URL]) throws -> InputProfile {
        let pages = try InputProfile.sampleIndices(pageCount: pageURLs.count).map { index in
            let url = pageURLs[index]
            guard let bitmap = ScanImageFile.read(url) else { throw PreprocessingError.unreadableImage(url) }
            return InputProfile(of: bitmap)
        }
        return InputProfile(ofDocument: pages)
    }

    public func prepare(pageAt url: URL, as profile: InputProfile) throws -> URL {
        guard profile == .scannedPage else { return url }
        guard let bitmap = ScanImageFile.read(url) else { throw PreprocessingError.unreadableImage(url) }
        let page = crop.pageBox(in: bitmap).map { bitmap.cropped(to: $0) } ?? bitmap
        // Cleaned before deskewing, so page edges do not sway the angle and
        // the rotation's new corners are white like the cleaned paper.
        let prepared = deskew.straightened(cleaner.cleaned(page))
        let target = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
        guard ScanImageFile.writePNG(prepared, to: target) else { throw PreprocessingError.cannotWrite(target) }
        return target
    }
}
