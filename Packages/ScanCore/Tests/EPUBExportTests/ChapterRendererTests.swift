import DocumentModel
@testable import EPUBExport
import Testing

@Suite("ChapterRenderer")
struct ChapterRendererTests {
    private let renderer = ChapterRenderer(document: Fixtures.document)

    private func first() throws -> String {
        try renderer.render(Fixtures.document.chapters[0])
    }

    @Test("produces an XHTML document in the document's language with an escaped title")
    func documentShell() throws {
        let xhtml = try first()
        #expect(xhtml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n"))
        #expect(xhtml.contains("xmlns:epub=\"http://www.idpf.org/2007/ops\""))
        #expect(xhtml.contains("xml:lang=\"uk\" lang=\"uk\""))
        #expect(xhtml.contains("<title>First &lt;steps&gt;</title>"))
        #expect(xhtml.contains("<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>"))
    }

    @Test("renders headings at their level, clamped to h1...h6")
    func headings() throws {
        let xhtml = try first()
        #expect(xhtml.contains("<h1>First &lt;steps&gt;</h1>"))
        #expect(xhtml.contains("<h2>Details</h2>"))
        let deep = try renderer.render(Chapter(title: "t", blocks: [
            .heading(level: 9, content: ["deep"]), .heading(level: 0, content: ["top"]),
        ]))
        #expect(deep.contains("<h6>deep</h6>"))
        #expect(deep.contains("<h1>top</h1>"))
    }

    @Test("renders paragraphs with escaped text and inline formatting")
    func paragraphs() throws {
        let xhtml = try first()
        #expect(xhtml.contains("<p>Plain &amp; simple, <em>stressed</em> and <strong>bold</strong>"))
    }

    @Test("renders a note reference as a noteref link carrying the note's label")
    func noteReference() throws {
        let xhtml = try first()
        #expect(xhtml.contains(
            "<a class=\"noteref\" epub:type=\"noteref\" id=\"ref-n1\" href=\"#note-n1\">1</a>"
        ))
        #expect(xhtml.contains("href=\"#note-n2\">b</a>"))
    }

    @Test("gives only the first reference to a note an id, so ids stay unique")
    func repeatedReference() throws {
        let xhtml = try first()
        #expect(xhtml.components(separatedBy: "id=\"ref-n1\"").count == 2)
        #expect(xhtml.components(separatedBy: "href=\"#note-n1\"").count == 3)
    }

    @Test("appends each referenced note once, in order of first reference, with a back link")
    func notesSection() throws {
        let xhtml = try first()
        #expect(xhtml.contains("<section class=\"notes\" epub:type=\"footnotes\">"))
        #expect(xhtml.contains(
            "<aside id=\"note-n1\" epub:type=\"footnote\"><p><a href=\"#ref-n1\">1</a> First note with <em>style</em>.</p></aside>"
        ))
        #expect(xhtml.components(separatedBy: "<aside ").count == 3)
        let firstNote = try #require(xhtml.range(of: "id=\"note-n1\""))
        let secondNote = try #require(xhtml.range(of: "id=\"note-n2\""))
        #expect(firstNote.lowerBound < secondNote.lowerBound)
        #expect(!xhtml.contains("Never referenced."))
    }

    @Test("omits the notes section when the chapter has no references")
    func noNotesSection() throws {
        let xhtml = try renderer.render(Fixtures.document.chapters[1])
        #expect(!xhtml.contains("class=\"notes\""))
    }

    @Test("renders a figure with escaped alternative text and a caption only when present")
    func figures() throws {
        #expect(try first().contains(
            "<figure><img src=\"images/fig-001.png\" alt=\"A &quot;quoted&quot; valley\"/><figcaption>Fig. 1. Valley</figcaption></figure>"
        ))
        #expect(try renderer.render(Fixtures.document.chapters[1]).contains(
            "<figure><img src=\"images/fig-001.png\" alt=\"\"/></figure>"
        ))
    }

    @Test("fails when a note reference or a figure points at nothing")
    func danglingReferences() {
        #expect(throws: EPUBExportError.missingNote(id: "ghost")) {
            try renderer.render(Chapter(title: "t", blocks: [.paragraph([.noteReference("ghost")])]))
        }
        #expect(throws: EPUBExportError.missingImage(id: "ghost")) {
            try renderer.render(Chapter(title: "t", blocks: [.figure(Figure(imageID: "ghost", alternativeText: ""))]))
        }
    }
}
