import DocumentModel
import Foundation
import LayoutAnalysis
import OCR

/// Runs the whole pipeline from page images to a ``Document``.
public struct DocumentConverter: Sendable {
    /// A picture on the first page at least this tall, as a fraction of the
    /// page height, is taken to be the document's cover.
    static let coverHeight = 0.5

    private let engine: any OCREngine
    private let pictureExtractor: any PictureExtractor
    private let analyzer: LayoutAnalyzer

    public init(
        engine: any OCREngine,
        pictureExtractor: any PictureExtractor = ImagePictureExtractor(),
        analyzer: LayoutAnalyzer = LayoutAnalyzer()
    ) {
        self.engine = engine
        self.pictureExtractor = pictureExtractor
        self.analyzer = analyzer
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
    /// - Parameter progress: Called after each page with the number of pages
    ///   done and the total.
    public func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Document {
        var pages: [PageContent] = []
        pages.reserveCapacity(pageURLs.count)
        var images: [ImageResource] = []
        var coverImageID: ImageResource.ID?

        for url in pageURLs {
            try Task.checkCancellation()
            let lines = try await engine.recognize(imageAt: url).lines
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
                pages.append(PageContent(lines: lines, pictures: pictures))
            }
            progress(pages.count, pageURLs.count)
        }
        let blocks = analyzer.blocks(from: pages)
        return Document(
            metadata: metadata,
            chapters: Self.chapters(from: blocks, fallbackTitle: metadata.title),
            images: images,
            coverImageID: coverImageID
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
