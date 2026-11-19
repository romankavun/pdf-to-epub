import Conversion
import DocumentModel
import EPUBExport
import Foundation
import Importing
import OCR
import Preprocessing

/// Everything ``ConversionModel`` needs from the rest of the package, as one
/// seam, so the model can be tested without touching files or Vision.
public protocol ConversionPipeline: Sendable {
    /// The page images in `folder`, in reading order.
    func pageURLs(in folder: URL) throws -> [URL]

    /// The number of pages of the PDF at `pdf`; fails when it cannot be read.
    func pdfPageCount(of pdf: URL) throws -> Int

    /// Draws the pages of `pdf` into `folder`, which must exist, and returns
    /// the image files in page order. Honours task cancellation.
    func renderPages(
        of pdf: URL,
        into folder: URL,
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void
    ) async throws -> [URL]

    /// Converts the pages into a document. Honours task cancellation.
    ///
    /// - Parameters:
    ///   - preparedFolder: An existing folder where pages of a paper scan
    ///     are prepared (cropped, cleaned, deskewed) before recognition;
    ///     the result's page URLs then point into it. `nil` reads the pages
    ///     as they are.
    ///   - progress: Called from any thread after each page with the number
    ///     of pages done and the total.
    func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        preparingPagesIn preparedFolder: URL?,
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void
    ) async throws -> Conversion

    /// Writes `document` as an EPUB file at `url`, replacing an existing file.
    func export(_ document: Document, to url: URL) async throws
}

/// The real pipeline: image folder or PDF, preparation of paper scans, Vision
/// OCR, layout analysis, EPUB.
public struct LivePipeline: ConversionPipeline {
    public init() {}

    /// The languages Vision is asked to recognize for a document in `language`.
    ///
    /// English is always included because documents in other languages quote
    /// English names and terms; an English document needs nothing else.
    static func recognitionLanguages(for language: String) -> [String] {
        language.hasPrefix("en") ? ["en-US"] : [language, "en-US"]
    }

    public func pageURLs(in folder: URL) throws -> [URL] {
        try ImageFolderImporter().pageURLs(in: folder)
    }

    public func pdfPageCount(of pdf: URL) throws -> Int {
        try PDFImporter().pageCount(of: pdf)
    }

    public func renderPages(
        of pdf: URL,
        into folder: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        try await PDFImporter().renderPages(of: pdf, into: folder, progress: progress)
    }

    public func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        preparingPagesIn preparedFolder: URL?,
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void
    ) async throws -> Conversion {
        let engine = VisionOCREngine(languages: Self.recognitionLanguages(for: metadata.language))
        return try await DocumentConverter(engine: engine, preparer: preparedFolder.map { ScanPagePreparer(folder: $0) })
            .analyze(pageURLs: pageURLs, metadata: metadata, progress: progress)
    }

    /// Runs off the caller's actor: zipping a document with hundreds of images
    /// would otherwise freeze the window.
    @concurrent
    public func export(_ document: Document, to url: URL) async throws {
        try EPUBExporter().export(document, to: url)
    }
}
