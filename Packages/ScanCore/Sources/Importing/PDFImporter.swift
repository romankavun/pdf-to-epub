import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why a PDF could not be imported.
public enum PDFImportError: Error, Equatable, Sendable {
    /// The file is missing or is not a PDF the system can read.
    case unreadable(URL)
    /// The PDF is encrypted and needs a password; the importer does not ask
    /// for one.
    case passwordRequired(URL)
    /// The PDF has no pages.
    case noPages(URL)
    /// Page `page` (one-based) could not be drawn.
    case cannotRender(URL, page: Int)
    /// The image file at this URL could not be written.
    case cannotWrite(URL)
}

/// Turns a PDF into a folder of page images, one lossless PNG per page.
///
/// The rest of the pipeline works on image files, so a PDF is reduced to
/// that form once and everything after it, recognition, note colours,
/// illustrations and the review's page scans, behaves as for a folder of
/// clean pages. Whatever text layer the PDF has is ignored on purpose: the
/// product recognizes text from pixels only.
///
/// Pages are drawn one at a time and written straight to disk, so a document
/// of hundreds of pages never has more than one bitmap in memory.
public struct PDFImporter: Sendable {
    /// File extension of PDFs, lowercase.
    public static let fileExtension = "pdf"

    private let resolution: Double
    private let longestSide: Int

    /// - Parameters:
    ///   - resolution: Pixels per inch for pages that are not a single
    ///     image. 200 gives body text about 30 pixels tall, enough for
    ///     Vision without making files huge.
    ///   - longestSide: The most pixels a page image may have along its
    ///     longer side.
    public init(resolution: Double = 200, longestSide: Int = 4096) {
        self.resolution = resolution
        self.longestSide = longestSide
    }

    /// Whether `url` names a PDF; decided by the file extension, as a
    /// folder of scans has none.
    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }

    /// The number of pages of the PDF at `url`.
    ///
    /// Cheap, so it can be used to check a file when it is chosen, before
    /// any page is drawn.
    public func pageCount(of url: URL) throws -> Int {
        try open(url).numberOfPages
    }

    /// Draws every page of the PDF at `url` into `folder`, which must exist,
    /// as `page-0001.png`, `page-0002.png` and so on, and returns the files
    /// in page order. The names sort in reading order for
    /// ``ImageFolderImporter`` too.
    ///
    /// A page that is one embedded image is drawn at that image's own pixel
    /// size, so a scan is not resampled; any other page is drawn at the
    /// importer's resolution. Either way no more than the longest side
    /// given to ``init(resolution:longestSide:)`` is used. Pages are written
    /// as PNG because JPEG artifacts would blur the colour of note markers.
    ///
    /// Runs off the caller's actor and honours task cancellation between
    /// pages.
    ///
    /// - Parameter progress: Called after each page with the number of pages
    ///   done and the total.
    @concurrent
    public func renderPages(
        of url: URL,
        into folder: URL,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> [URL] {
        let document = try open(url)
        let total = document.numberOfPages
        var files: [URL] = []
        files.reserveCapacity(total)
        for number in 1 ... total {
            try Task.checkCancellation()
            guard let page = document.page(at: number) else { throw PDFImportError.cannotRender(url, page: number) }
            let file = folder.appendingPathComponent(String(format: "page-%04d.png", number))
            try autoreleasepool {
                guard let image = render(page) else { throw PDFImportError.cannotRender(url, page: number) }
                try Self.writePNG(image, to: file)
            }
            files.append(file)
            progress(number, total)
        }
        return files
    }

    // MARK: - Opening

    private func open(_ url: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFImportError.unreadable(url) }
        // An empty password unlocks documents that only restrict editing.
        if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") {
            throw PDFImportError.passwordRequired(url)
        }
        guard document.numberOfPages > 0 else { throw PDFImportError.noPages(url) }
        return document
    }

    // MARK: - Drawing

    private func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let shown = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard shown.width > 0, shown.height > 0 else { return nil }

        let scale = min(
            PageImagePlacement.pixelsPerPoint(of: page) ?? resolution / 72,
            Double(longestSide) / max(shown.width, shown.height)
        )
        let width = max(1, Int((shown.width * scale).rounded()))
        let height = max(1, Int((shown.height * scale).rounded()))

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // PDF pages have no background of their own; paper is white.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        // Maps the crop box, rotated as the page asks, exactly onto the bitmap.
        context.concatenate(page.getDrawingTransform(
            .cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0,
            preserveAspectRatio: false
        ))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw PDFImportError.cannotWrite(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PDFImportError.cannotWrite(url) }
    }
}
