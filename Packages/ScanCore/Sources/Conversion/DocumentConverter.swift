import DocumentModel
import Foundation
import LayoutAnalysis
import OCR

/// Runs the whole pipeline from page images to a ``Document``.
public struct DocumentConverter: Sendable {
    private let engine: any OCREngine
    private let analyzer: LayoutAnalyzer

    public init(engine: any OCREngine, analyzer: LayoutAnalyzer = LayoutAnalyzer()) {
        self.engine = engine
        self.analyzer = analyzer
    }

    /// Converts the pages at `pageURLs`, given in reading order.
    ///
    /// Pages are recognized one after another. The call honours task
    /// cancellation between pages.
    ///
    /// - Parameter progress: Called after each page with the number of pages
    ///   done and the total.
    public func convert(
        pageURLs: [URL],
        metadata: DocumentMetadata,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Document {
        var pages: [RecognizedPage] = []
        pages.reserveCapacity(pageURLs.count)
        for url in pageURLs {
            try Task.checkCancellation()
            try await pages.append(engine.recognize(imageAt: url))
            progress(pages.count, pageURLs.count)
        }
        let blocks = analyzer.blocks(from: pages)
        return Document(metadata: metadata, chapters: Self.chapters(from: blocks, fallbackTitle: metadata.title))
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
