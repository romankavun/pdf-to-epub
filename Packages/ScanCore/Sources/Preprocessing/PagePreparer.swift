import Foundation

/// Something that turns a page image into the image the rest of the
/// pipeline should read.
///
/// The converter depends on this protocol rather than on image decoding, so
/// it can be tested with canned files.
public protocol PagePreparing: Sendable {
    /// The image to recognize for the page at `url`: a new file when the
    /// page needed preparing, `url` itself when it did not.
    func prepare(pageAt url: URL) throws -> URL
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
/// its paper and removes debris around the text (``BackgroundCleaner``).
///
/// Every later stage (recognition, note-marker colours, ink weight,
/// picture crops, the review) reads the prepared file, so all of them agree
/// on page coordinates. A page that needs nothing is not copied.
public struct ScanPagePreparer: PagePreparing {
    private let folder: URL
    private let crop: PageCrop
    private let cleaner: BackgroundCleaner

    /// - Parameter folder: Where prepared pages are written, under the name
    ///   of the original file with a `.png` extension. It must exist; a file
    ///   of the same name is replaced.
    public init(folder: URL, crop: PageCrop = PageCrop(), cleaner: BackgroundCleaner = BackgroundCleaner()) {
        self.folder = folder
        self.crop = crop
        self.cleaner = cleaner
    }

    public func prepare(pageAt url: URL) throws -> URL {
        guard let bitmap = ScanImageFile.read(url) else { throw PreprocessingError.unreadableImage(url) }
        guard let box = crop.pageBox(in: bitmap) else { return url }
        let prepared = cleaner.cleaned(bitmap.cropped(to: box))
        let target = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
        guard ScanImageFile.writePNG(prepared, to: target) else { throw PreprocessingError.cannotWrite(target) }
        return target
    }
}
