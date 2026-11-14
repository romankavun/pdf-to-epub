import DocumentModel
import Foundation
@testable import LayoutAnalysis
import OCR
import Testing

/// Body lines are 0.017 tall at a pitch of 0.02 and span 0.05 ... 0.95.
private func body(_ text: String, y: Double, ink: Double = 0.2) -> (TextLine, LineInk) {
    let box = CGRect(x: 0.05, y: y, width: 0.9, height: 0.017)
    return (TextLine(text: text, box: box), LineInk(box: box, density: ink))
}

private func short(_ text: String, x: Double = 0.35, y: Double, width: Double = 0.3,
                   height: Double = 0.017, ink: Double = 0.2) -> (TextLine, LineInk)
{
    let box = CGRect(x: x, y: y, width: width, height: height)
    return (TextLine(text: text, box: box), LineInk(box: box, density: ink))
}

private func content(_ lines: [(TextLine, LineInk)], pictures: [PagePicture] = []) -> PageContent {
    PageContent(lines: lines.map(\.0), pictures: pictures, markers: [], lineInk: lines.map(\.1))
}

/// Three body lines, a blank line, `middle`, a blank line, three more.
private func page(around middle: (TextLine, LineInk), top: Double = 0.1) -> PageContent {
    content([
        body("one a", y: top), body("one b", y: top + 0.02), body("one c", y: top + 0.04),
        (middle.0, middle.1),
        body("two a", y: top + 0.12), body("two b", y: top + 0.14), body("two c", y: top + 0.16),
    ])
}

@Suite("Headings at body size")
struct BodyHeadingTests {
    private let analyzer = LayoutAnalyzer()

    @Test("a short centered line set apart by blank lines is a heading")
    func centered() {
        let blocks = analyzer.blocks(from: [page(around: short("The Garden", y: 0.18))])
        #expect(blocks == [
            .paragraph(["one a one b one c"]),
            .heading(level: 1, content: ["The Garden"]),
            .paragraph(["two a two b two c"]),
        ])
    }

    @Test("the same line at the margin and in the body weight stays a paragraph")
    func leftAlignedPlain() {
        let blocks = analyzer.blocks(from: [page(around: short("The Garden", x: 0.05, y: 0.18))])
        #expect(blocks.count == 3)
        #expect(blocks[1] == .paragraph(["The Garden"]))
    }

    @Test("a short bold line at the margin, set apart, is a heading")
    func bold() {
        let blocks = analyzer.blocks(from: [page(around: short("The Garden", x: 0.05, y: 0.18, ink: 0.4))])
        #expect(blocks[1] == .heading(level: 1, content: ["The Garden"]))
    }

    @Test("a bold line that is not set apart is not a heading")
    func boldInsideParagraph() {
        let lines = [
            body("one a", y: 0.1), short("bold words", x: 0.05, y: 0.12, ink: 0.4), body("one c", y: 0.14),
            body("one d", y: 0.16),
        ]
        #expect(analyzer.blocks(from: [content(lines)]) == [.paragraph(["one a bold words one c one d"])])
    }

    @Test("a bold line as wide as the text is not a heading")
    func boldFullWidth() {
        let blocks = analyzer.blocks(from: [page(around: body("A whole bold sentence", y: 0.18, ink: 0.4))])
        #expect(blocks.count == 3)
        #expect(blocks[1] == .paragraph(["A whole bold sentence"]))
    }

    @Test("a centered line that ends a sentence is not a heading")
    func centeredSentence() {
        let blocks = analyzer.blocks(from: [page(around: short("It was over.", y: 0.18))])
        #expect(blocks[1] == .paragraph(["It was over."]))
    }

    @Test("a centered line right under a picture is a caption, not a heading")
    func belowPicture() {
        let picture = PagePicture(imageID: "figure-001", box: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.3))
        let page = content(
            [short("A sketch", y: 0.41), body("two a", y: 0.5), body("two b", y: 0.52)],
            pictures: [picture]
        )
        let blocks = analyzer.blocks(from: [page])
        #expect(!blocks.contains(.heading(level: 1, content: ["A sketch"])))
    }

    @Test("a heading at the top of a page does not continue the paragraph of the page before")
    func topOfPage() {
        let first = content([body("one a", y: 0.1), body("one b", y: 0.12), body("one c", y: 0.14)])
        let second = content([
            short("Next Chapter", y: 0.1, ink: 0.4), body("two a", y: 0.18), body("two b", y: 0.2),
        ])
        #expect(analyzer.blocks(from: [first, second]) == [
            .paragraph(["one a one b one c"]),
            .heading(level: 1, content: ["Next Chapter"]),
            .paragraph(["two a two b"]),
        ])
    }

    @Test("body-size headings rank below headings set larger")
    func levels() {
        let large = short("Part One", y: 0.1, height: 0.035)
        let first = content([
            large, body("one a", y: 0.2), body("one b", y: 0.22), body("one c", y: 0.24),
            short("The Garden", y: 0.3), body("two a", y: 0.38), body("two b", y: 0.4),
        ])
        let headings = analyzer.blocks(from: [first]).compactMap { block -> Int? in
            if case let .heading(level, _) = block {
                level
            } else {
                nil
            }
        }
        #expect(headings == [1, 2])
    }

    @Test("without ink data, geometry alone decides")
    func noInk() {
        var page = page(around: short("The Garden", y: 0.18))
        page.lineInk = []
        #expect(analyzer.blocks(from: [page])[1] == .heading(level: 1, content: ["The Garden"]))
    }
}
