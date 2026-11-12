import DocumentModel
import Foundation
import Testing

@Suite("Document")
struct DocumentTests {
    private let sample = Document(
        metadata: DocumentMetadata(title: "Sample", author: "A. Author", language: "uk"),
        chapters: [
            Chapter(title: "One", blocks: [
                .heading(level: 1, text: "One"),
                .paragraph(text: "First paragraph."),
            ]),
        ]
    )

    @Test("survives a JSON round trip unchanged")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        #expect(decoded == sample)
    }

    @Test("a document without chapters has no blocks")
    func emptyDocumentHasNoBlocks() {
        let empty = Document(metadata: DocumentMetadata(title: "Empty", author: nil, language: "en"), chapters: [])
        #expect(empty.blocks.isEmpty)
    }

    @Test("blocks are listed in reading order across chapters")
    func blocksInReadingOrder() {
        var document = sample
        document.chapters.append(Chapter(title: "Two", blocks: [.paragraph(text: "Second chapter.")]))
        #expect(document.blocks == [
            .heading(level: 1, text: "One"),
            .paragraph(text: "First paragraph."),
            .paragraph(text: "Second chapter."),
        ])
    }
}
