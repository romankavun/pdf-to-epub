import DocumentModel
import Foundation
import LayoutAnalysis
import OCR

/// The outcome of converting a document: the document and what could not be
/// resolved on the way, for the user to review.
public struct Conversion: Sendable, Equatable {
    public var document: Document
    /// Note references left in the text as plain labels because no note
    /// could be matched to them.
    public var unlinkedReferences: Int
    /// Note texts left in the body as paragraphs because nothing refers to
    /// them.
    public var unlinkedNotes: Int
    /// The page images the document was converted from, in reading order.
    public var pageURLs: [URL]
    /// The origin of each block of ``Document/blocks``, in the same order;
    /// ``BlockSource/page`` indexes ``pageURLs``.
    public var blockSources: [BlockSource]

    public init(
        document: Document,
        unlinkedReferences: Int = 0,
        unlinkedNotes: Int = 0,
        pageURLs: [URL] = [],
        blockSources: [BlockSource] = []
    ) {
        self.document = document
        self.pageURLs = pageURLs
        self.blockSources = blockSources
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }
}

/// Runs the whole pipeline from page images to a ``Document``.
public struct DocumentConverter: Sendable {
    /// A picture on the first page at least this tall, as a fraction of the
    /// page height, is taken to be the document's cover.
    static let coverHeight = 0.5

    private let engine: any OCREngine
    private let pictureExtractor: any PictureExtractor
    private let markerLocator: any NoteMarkerLocator
    private let analyzer: LayoutAnalyzer

    public init(
        engine: any OCREngine,
        pictureExtractor: any PictureExtractor = ImagePictureExtractor(),
        markerLocator: any NoteMarkerLocator = ImageNoteMarkerLocator(),
        analyzer: LayoutAnalyzer = LayoutAnalyzer()
    ) {
        self.engine = engine
        self.pictureExtractor = pictureExtractor
        self.markerLocator = markerLocator
        self.analyzer = analyzer
    }

    /// Converts the pages at `pageURLs` and returns the document alone; see
    /// ``analyze(pageURLs:metadata:progress:)``.
    public func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Document {
        try await analyze(pageURLs: pageURLs, metadata: metadata, progress: progress).document
    }

    /// Converts the pages at `pageURLs`, given in reading order.
    ///
    /// Pages are processed one after another. The call honours task
    /// cancellation between pages.
    ///
    /// Illustrations are embedded as `figure-NNN.png`, numbered in reading
    /// order. When the first page is mostly one picture, that picture
    /// becomes the cover and the page contributes nothing else: the text on
    /// a cover repeats the title page.
    ///
    /// Note markers are located by colour and erased before recognition, so
    /// they do not corrupt the words next to them; their labels are read
    /// separately and the references are linked to the note texts.
    ///
    /// - Parameter progress: Called after each page with the number of pages
    ///   done and the total.
    public func analyze(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Conversion {
        var pages: [PageContent] = []
        pages.reserveCapacity(pageURLs.count)
        var images: [ImageResource] = []
        var coverImageID: ImageResource.ID?

        for url in pageURLs {
            try Task.checkCancellation()
            let markerBoxes = try markerLocator.markers(inImageAt: url)
            let lines = try await engine.recognize(imageAt: url, erasing: markerBoxes).lines
            let labels = markerBoxes.isEmpty ? [] : try await engine.readLabels(inImageAt: url, regions: markerBoxes)
            let markers = markerBoxes.enumerated().map { index, box in
                NoteMarker(box: box, label: index < labels.count ? labels[index] : "")
            }
            let extracted = try pictureExtractor.pictures(inImageAt: url, lines: lines)
                .sorted { $0.box.minY < $1.box.minY }

            let cover = pages.isEmpty
                ? extracted.max { $0.box.height < $1.box.height }
                .flatMap { Double($0.box.height) >= Self.coverHeight ? $0 : nil }
                : nil
            if let cover {
                let image = Self.image(id: "cover", data: cover.pngData)
                images.append(image)
                coverImageID = image.id
                pages.append(PageContent(lines: []))
            } else {
                var pictures: [PagePicture] = []
                for picture in extracted {
                    let number = String(images.count(where: { $0.id != coverImageID }) + 1)
                    let id = "figure-" + String(repeating: "0", count: max(0, 3 - number.count)) + number
                    images.append(Self.image(id: id, data: picture.pngData))
                    pictures.append(PagePicture(imageID: id, box: picture.box))
                }
                pages.append(PageContent(lines: lines, pictures: pictures, markers: markers))
            }
            progress(pages.count, pageURLs.count)
        }
        let layout = analyzer.layout(of: pages)
        let document = Document(
            metadata: metadata,
            chapters: Self.chapters(from: layout.blocks, fallbackTitle: metadata.title),
            notes: layout.notes,
            images: images,
            coverImageID: coverImageID
        )
        return Conversion(
            document: document, unlinkedReferences: layout.unlinkedReferences, unlinkedNotes: layout.unlinkedNotes,
            pageURLs: pageURLs, blockSources: layout.sources
        )
    }

    private static func image(id: ImageResource.ID, data: Data) -> ImageResource {
        ImageResource(id: id, filename: id + ".png", mediaType: "image/png", data: data)
    }

    /// Splits blocks into chapters at every level 1 heading.
    ///
    /// Content before the first heading (title page, preface without a
    /// heading) becomes a chapter named after the document, because every
    /// chapter needs a title for the table of contents.
    static func chapters(from blocks: [Block], fallbackTitle: String) -> [Chapter] {
        var chapters: [Chapter] = []
        for block in blocks {
            if case let .heading(level, content) = block, level == 1 {
                chapters.append(Chapter(title: content.plainText, blocks: [block]))
            } else if chapters.isEmpty {
                chapters.append(Chapter(title: fallbackTitle, blocks: [block]))
            } else {
                chapters[chapters.count - 1].blocks.append(block)
            }
        }
        return chapters
    }
}
