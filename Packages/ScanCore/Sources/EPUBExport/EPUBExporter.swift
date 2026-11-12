import DocumentModel
import Foundation

/// Writes a ``Document`` as an EPUB 3 file.
///
/// The output contains one XHTML document per chapter, a flat table of
/// contents, embedded images, and notes rendered as pop-up footnotes at the
/// end of the chapter that refers to them.
public struct EPUBExporter: Sendable {
    public init() {}

    /// Exports `document` to `url`, replacing any existing file.
    ///
    /// - Parameter modified: The publication's last-modified time, recorded in
    ///   its metadata. Defaults to now; pass a fixed date for reproducible
    ///   output.
    /// - Throws: ``EPUBExportError`` when the document is inconsistent, or a file
    ///   system error when writing fails.
    public func export(_ document: Document, to url: URL, modified: Date = .now) throws {
        let archive = try ZipWriter.archive(entries(for: document, modified: modified))
        try archive.write(to: url, options: .atomic)
    }

    /// The files of the EPUB container in the order they are written.
    func entries(for document: Document, modified: Date) throws -> [ZipEntry] {
        guard !document.chapters.isEmpty else { throw EPUBExportError.noChapters }
        if let coverID = document.coverImageID, document.image(withID: coverID) == nil {
            throw EPUBExportError.missingImage(id: coverID)
        }
        var filenames = Set<String>()
        for image in document.images where !filenames.insert(image.filename).inserted {
            throw EPUBExportError.duplicateImageFilename(image.filename)
        }

        let content = EPUBLayout.contentDirectory + "/"
        func textEntry(_ path: String, _ text: String) -> ZipEntry {
            ZipEntry(path: path, data: Data(text.utf8), compress: true)
        }
        var entries = [
            // Must be first and uncompressed (EPUB Open Container Format).
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), compress: false),
            textEntry("META-INF/container.xml", Self.container),
            textEntry(content + EPUBLayout.packageDocument, PackageDocument.render(document, modified: modified)),
            textEntry(content + EPUBLayout.navigationDocument, NavigationDocument.render(document)),
            textEntry(content + EPUBLayout.stylesheet, Self.stylesheet),
        ]
        let renderer = ChapterRenderer(document: document)
        for (index, chapter) in document.chapters.enumerated() {
            try entries.append(textEntry(content + EPUBLayout.chapterPath(index: index), renderer.render(chapter)))
        }
        for image in document.images {
            entries.append(ZipEntry(path: content + EPUBLayout.imagePath(image), data: image.data, compress: true))
        }
        return entries
    }

    private static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="\(EPUBLayout.contentDirectory)/\(EPUBLayout.packageDocument)" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>

    """

    /// Deliberately small: reading systems apply the reader's own font and
    /// size preferences, and heavy styling fights them.
    private static let stylesheet = """
    body { margin: 0 5%; line-height: 1.4; }
    h1, h2, h3, h4, h5, h6 { text-align: left; line-height: 1.2; page-break-after: avoid; }
    p { margin: 0; text-indent: 1.5em; text-align: justify; }
    h1 + p, h2 + p, h3 + p, h4 + p, h5 + p, h6 + p, figure + p { text-indent: 0; }
    figure { margin: 1em 0; text-align: center; page-break-inside: avoid; }
    figure img { max-width: 100%; height: auto; }
    figcaption { font-size: 0.85em; font-style: italic; }
    a.noteref { font-size: 0.75em; vertical-align: super; line-height: 0; text-decoration: none; }
    section.notes { margin-top: 2em; font-size: 0.85em; }
    section.notes p { text-indent: 0; margin-bottom: 0.5em; }

    """
}
