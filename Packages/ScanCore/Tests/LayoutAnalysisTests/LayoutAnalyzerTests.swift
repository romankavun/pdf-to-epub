import DocumentModel
import Foundation
@testable import LayoutAnalysis
import OCR
import Testing

/// Geometry used by the tests, mirroring a typical page: body lines are
/// 0.017 tall, 0.02 apart, start at x = 0.05; a first line is indented to 0.08.
private let margin = 0.05, indent = 0.08, pitch = 0.02

private func line(_ text: String, x: Double = margin, y: Double, width: Double = 0.9,
                  height: Double = 0.017) -> TextLine
{
    TextLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

/// A page of body lines at regular pitch starting at `top`. Strings prefixed
/// with ">" are indented; an empty string leaves a blank line (a larger gap).
private func page(top: Double = 0.1, _ texts: [String]) -> RecognizedPage {
    var lines: [TextLine] = []
    for (index, text) in texts.enumerated() where !text.isEmpty {
        let y = top + Double(index) * pitch
        if text.hasPrefix(">") {
            lines.append(line(String(text.dropFirst()), x: indent, y: y, width: 0.87))
        } else {
            lines.append(line(text, y: y))
        }
    }
    return RecognizedPage(lines: lines)
}

private func paragraphs(_ blocks: [Block]) -> [String] {
    blocks.compactMap {
        if case let .paragraph(content) = $0 {
            content.plainText
        } else {
            nil
        }
    }
}

@Suite("LayoutAnalyzer")
struct LayoutAnalyzerTests {
    private let analyzer = LayoutAnalyzer()

    @Test("no pages or empty pages give no blocks")
    func empty() {
        #expect(analyzer.blocks(from: [RecognizedPage]()).isEmpty)
        #expect(analyzer.blocks(from: [RecognizedPage(lines: [])]).isEmpty)
    }

    @Test("joins consecutive lines into one paragraph with spaces")
    func joinsLines() {
        let blocks = analyzer.blocks(from: [page([">one two", "three four", "five."])])
        #expect(blocks == [.paragraph(["one two three four five."])])
    }

    @Test("an indented line starts a new paragraph")
    func indentStartsParagraph() {
        let blocks = analyzer.blocks(from: [page([">first a", "first b", ">second a", "second b", "second c"])])
        #expect(paragraphs(blocks) == ["first a first b", "second a second b second c"])
    }

    @Test("a blank line starts a new paragraph even without an indent")
    func gapStartsParagraph() {
        let blocks = analyzer.blocks(from: [page(["first a", "first b", "first c", "", "second a", "second b"])])
        #expect(paragraphs(blocks) == ["first a first b first c", "second a second b"])
    }

    @Test("sorts lines top to bottom before grouping")
    func sortsLines() {
        var shuffled = page([">a", "b", "c", "d"])
        shuffled.lines.reverse()
        #expect(paragraphs(analyzer.blocks(from: [shuffled])) == ["a b c d"])
    }

    @Test("a line much taller than body text is a level 1 heading")
    func heading() {
        var first = page(top: 0.2, [">body a", "body b", "body c", "body d"])
        first.lines.append(line("Big Title", y: 0.1, width: 0.3, height: 0.035))
        let blocks = analyzer.blocks(from: [first])
        #expect(blocks == [.heading(level: 1, content: ["Big Title"]), .paragraph(["body a body b body c body d"])])
    }

    @Test("a heading wrapped over two lines stays one heading")
    func wrappedHeading() {
        var first = page(top: 0.3, [">body a", "body b", "body c", "body d", "body e"])
        first.lines.append(line("A Very Long", y: 0.1, width: 0.5, height: 0.035))
        first.lines.append(line("Chapter Title", y: 0.145, width: 0.5, height: 0.035))
        #expect(analyzer.blocks(from: [first]).first == .heading(level: 1, content: ["A Very Long Chapter Title"]))
    }

    @Test("a tall box that overlaps the line below is a recognition glitch, not a heading")
    func overlappingTallLine() {
        var first = page([">body a", "body b", "", "body d", "body e"])
        // The engine sometimes reports one body line with a box two lines high.
        first.lines.append(line("body c", y: 0.1 + 2 * pitch - 0.008, height: 0.035))
        #expect(analyzer.blocks(from: [first]) == [.paragraph(["body a body b body c body d body e"])])
    }

    @Test("a heading reported as two boxes side by side is still a heading")
    func splitHeadingLine() {
        var first = page(top: 0.2, [">body a", "body b", "body c", "body d"])
        first.lines.append(line("Big", y: 0.1, width: 0.1, height: 0.035))
        first.lines.append(line("Title", x: 0.17, y: 0.101, width: 0.2, height: 0.035))
        #expect(analyzer.blocks(from: [first]).first == .heading(level: 1, content: ["Big Title"]))
    }

    @Test("a line reported as pieces side by side is read as one line, left to right")
    func lineInPieces() {
        var first = page([">first a", "", "first c", ">second a", "second b"])
        // The second line of the paragraph arrives as two boxes, right piece first.
        first.lines.append(line("right piece", x: 0.4, y: 0.1 + pitch + 0.001, width: 0.5))
        first.lines.append(line("left piece", y: 0.1 + pitch, width: 0.3))
        #expect(paragraphs(analyzer.blocks(from: [first])) == [
            "first a left piece right piece first c",
            "second a second b",
        ])
    }

    @Test("pieces of a line whose boxes overlap slightly are still one line")
    func lineInOverlappingPieces() {
        var first = page([">first a", "", "first c", ">second a", "second b"])
        // As on real pages: the engine breaks the line before a dash, and the
        // right piece's box starts a little before the left piece's box ends
        // and a little higher.
        first.lines.append(line("— right piece", x: 0.1627, y: 0.1 + pitch - 0.001, width: 0.8))
        first.lines.append(line("left piece", y: 0.1 + pitch, width: 0.1151, height: 0.015))
        #expect(paragraphs(analyzer.blocks(from: [first])) == [
            "first a left piece — right piece first c",
            "second a second b",
        ])
    }

    @Test("lines whose boxes overlap for most of their width are not joined side by side")
    func overlappingLinesStayApart() {
        // A box reported two lines high over an ordinary line: they share
        // height but lie on top of each other, not side by side.
        let first = RecognizedPage(lines: [
            line("first a", x: indent, y: 0.1, width: 0.87),
            line("tall b", y: 0.1 + pitch, width: 0.9, height: 0.037),
            line("first c", y: 0.1 + 2 * pitch, width: 0.85),
        ])
        #expect(paragraphs(analyzer.blocks(from: [first])) == ["first a tall b first c"])
    }

    @Test("drops a page number at the bottom but keeps numbers in the text")
    func pageNumber() {
        var first = page([">In the year", "1984", "something happened."])
        first.lines.append(line("47", x: 0.49, y: 0.93, width: 0.02, height: 0.01))
        #expect(analyzer.blocks(from: [first]) == [.paragraph(["In the year 1984 something happened."])])
    }

    @Test("a paragraph continues onto the next page when that page starts unindented")
    func continuesAcrossPages() {
        let pages = [
            page([">first a", "first b", "first c"]).with(pageNumber: "1"),
            page(["first d", "first e", ">second a"]).with(pageNumber: "2"),
        ]
        #expect(paragraphs(analyzer.blocks(from: pages)) == ["first a first b first c first d first e", "second a"])
    }

    @Test("an indented first line on a new page starts a new paragraph")
    func newParagraphOnNewPage() {
        let pages = [page([">first a", "first b", "first c"]), page([">second a", "second b", "second c"])]
        #expect(paragraphs(analyzer.blocks(from: pages)) == ["first a first b first c", "second a second b second c"])
    }

    @Test("text after a heading never merges into it, and a heading never continues a paragraph")
    func headingBoundaries() {
        var second = page(top: 0.2, ["body c", "body d", "body e"])
        second.lines.append(line("Next Part", y: 0.1, width: 0.3, height: 0.035))
        let blocks = analyzer.blocks(from: [page([">body a", "body b", "body bb"]), second])
        #expect(blocks == [
            .paragraph(["body a body b body bb"]),
            .heading(level: 1, content: ["Next Part"]),
            .paragraph(["body c body d body e"]),
        ])
    }

    @Test("a word broken after a hyphen at a line end is joined without a space")
    func hyphenAtLineEnd() {
        let blocks = analyzer.blocks(from: [page([">something half-", "baked and - ", "dashed", "end"])])
        #expect(paragraphs(blocks) == ["something half-baked and - dashed end"])
    }
}

private extension RecognizedPage {
    func with(pageNumber: String) -> RecognizedPage {
        var copy = self
        copy.lines.append(line(pageNumber, x: 0.49, y: 0.93, width: 0.02, height: 0.01))
        return copy
    }
}
