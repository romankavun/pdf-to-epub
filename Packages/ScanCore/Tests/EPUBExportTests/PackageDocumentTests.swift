import DocumentModel
@testable import EPUBExport
import Foundation
import Testing

@Suite("PackageDocument and NavigationDocument")
struct PackageDocumentTests {
    /// 2026-01-02 03:04:05 UTC
    private let modified = Date(timeIntervalSince1970: 1_767_323_045)

    private func opf(_ document: Document = Fixtures.document) -> String {
        PackageDocument.render(document, modified: modified)
    }

    @Test("declares the required metadata with escaped values")
    func metadata() {
        let opf = opf()
        #expect(opf.contains("<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"pub-id\""))
        #expect(opf.contains("<dc:identifier id=\"pub-id\">urn:uuid:0f8fad5b-d9cb-469f-a165-70867728950e</dc:identifier>"))
        #expect(opf.contains("<dc:title>Salt &amp; Stone</dc:title>"))
        #expect(opf.contains("<dc:language>uk</dc:language>"))
        #expect(opf.contains("<dc:creator>Ada Example</dc:creator>"))
        #expect(opf.contains("<meta property=\"dcterms:modified\">2026-01-02T03:04:05Z</meta>"))
    }

    @Test("omits the creator when the author is unknown")
    func noAuthor() {
        var document = Fixtures.document
        document.metadata.author = nil
        #expect(!opf(document).contains("dc:creator"))
    }

    @Test("lists navigation, stylesheet, chapters and images in the manifest")
    func manifest() {
        let opf = opf()
        #expect(opf.contains("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"))
        #expect(opf.contains("<item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>"))
        #expect(opf.contains("<item id=\"chapter-001\" href=\"chapter-001.xhtml\" media-type=\"application/xhtml+xml\"/>"))
        #expect(opf.contains("<item id=\"chapter-002\" href=\"chapter-002.xhtml\" media-type=\"application/xhtml+xml\"/>"))
        #expect(opf.contains("<item id=\"image-2\" href=\"images/fig-001.png\" media-type=\"image/png\"/>"))
    }

    @Test("marks only the cover image as cover-image")
    func cover() {
        let opf = opf()
        #expect(opf.contains("<item id=\"image-1\" href=\"images/cover.png\" media-type=\"image/png\" properties=\"cover-image\"/>"))
        #expect(opf.components(separatedBy: "cover-image").count == 2)
        var document = Fixtures.document
        document.coverImageID = nil
        #expect(!self.opf(document).contains("cover-image"))
    }

    @Test("puts chapters in the spine in reading order")
    func spine() throws {
        let opf = opf()
        let first = try #require(opf.range(of: "<itemref idref=\"chapter-001\"/>"))
        let second = try #require(opf.range(of: "<itemref idref=\"chapter-002\"/>"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test("navigation document links every chapter by its escaped title")
    func navigation() {
        let nav = NavigationDocument.render(Fixtures.document)
        #expect(nav.contains("<nav epub:type=\"toc\""))
        #expect(nav.contains("<li><a href=\"chapter-001.xhtml\">First &lt;steps&gt;</a></li>"))
        #expect(nav.contains("<li><a href=\"chapter-002.xhtml\">Second</a></li>"))
        #expect(nav.contains("<title>Salt &amp; Stone</title>"))
        #expect(nav.contains("xml:lang=\"uk\""))
    }
}
