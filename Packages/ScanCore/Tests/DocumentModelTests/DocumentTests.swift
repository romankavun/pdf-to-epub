import DocumentModel
import Foundation
import Testing

@Suite("Document")
struct DocumentTests {
    private let sample = Document(
        metadata: DocumentMetadata(identifier: "urn:uuid:1", title: "Sample", author: "A. Author", language: "uk"),
        chapters: [
            Chapter(title: "One", blocks: [
                .heading(level: 1, content: ["One"]),
                .paragraph(["Plain, ", .emphasis("stressed"), .noteReference("n1"), "."]),
                .figure(Figure(imageID: "img1", alternativeText: "A valley", caption: ["Fig. 1"])),
            ]),
        ],
        notes: [Note(id: "n1", label: "1", content: ["Explanation."])],
        images: [ImageResource(id: "img1", filename: "valley.png", mediaType: "image/png", data: Data([1, 2, 3]))],
        coverImageID: "img1"
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
        #expect(empty.notes.isEmpty)
        #expect(empty.images.isEmpty)
        #expect(empty.coverImageID == nil)
    }

    @Test("blocks are listed in reading order across chapters")
    func blocksInReadingOrder() {
        var document = sample
        document.chapters.append(Chapter(title: "Two", blocks: [.paragraph(["Second chapter."])]))
        #expect(document.blocks.count == 4)
        #expect(document.blocks.last == .paragraph(["Second chapter."]))
    }

    @Test("metadata gets a unique identifier when none is given")
    func defaultIdentifierIsUnique() {
        let first = DocumentMetadata(title: "A", author: nil, language: "en")
        let second = DocumentMetadata(title: "A", author: nil, language: "en")
        #expect(first.identifier.hasPrefix("urn:uuid:"))
        #expect(first.identifier != second.identifier)
    }

    @Test("looks up notes and images by identifier")
    func lookup() {
        #expect(sample.note(withID: "n1")?.label == "1")
        #expect(sample.note(withID: "missing") == nil)
        #expect(sample.image(withID: "img1")?.filename == "valley.png")
        #expect(sample.image(withID: "missing") == nil)
    }
}

@Suite("Inline")
struct InlineTests {
    @Test("a string literal is plain text")
    func stringLiteral() {
        let inline: Inline = "hello"
        #expect(inline == .text("hello"))
    }

    @Test("plain text drops formatting and note references")
    func plainText() {
        let content: [Inline] = ["Plain, ", .emphasis("stressed"), " and ", .strong("bold"), .noteReference("n1"), "."]
        #expect(content.plainText == "Plain, stressed and bold.")
    }

    @Test("note references are listed in order of appearance")
    func referencedNotes() {
        let blocks: [Block] = [
            .heading(level: 1, content: ["Title", .noteReference("b")]),
            .paragraph(["x", .noteReference("a"), .noteReference("b")]),
            .figure(Figure(imageID: "i", alternativeText: "", caption: ["c", .noteReference("c")])),
        ]
        #expect(blocks.flatMap(\.referencedNoteIDs) == ["b", "a", "b", "c"])
    }
}

@Suite("Chapter splitting")
struct ChapterSplittingTests {
    @Test("splits at level 1 headings and names leading content after the fallback title")
    func splitsAtTopHeadings() {
        let blocks: [Block] = [
            .paragraph(["Preface"]),
            .heading(level: 1, content: ["One"]),
            .heading(level: 2, content: ["Part"]),
            .paragraph(["Text"]),
            .heading(level: 1, content: ["Two"]),
        ]
        let chapters = Chapter.chapters(from: blocks, fallbackTitle: "Document")
        #expect(chapters.map(\.title) == ["Document", "One", "Two"])
        #expect(chapters.map(\.blocks.count) == [1, 3, 1])
    }

    @Test("no blocks, no chapters")
    func empty() {
        #expect(Chapter.chapters(from: [], fallbackTitle: "Document").isEmpty)
    }
}
