import DocumentModel
import Foundation
import LayoutAnalysis
import OCR
import Testing

/// Page geometry as in `LayoutAnalyzerTests`: body lines 0.017 tall, 0.02
/// apart, from the margin at x = 0.05 to 0.95; a first line is indented to 0.08.
private let pitch = 0.02

private func line(_ text: String, x: Double = 0.05, y: Double, width: Double = 0.9,
                  height: Double = 0.017) -> TextLine
{
    TextLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

/// Body lines at regular pitch starting at `top`. Strings prefixed with ">"
/// are indented; an empty string leaves a blank line.
private func body(top: Double, _ texts: [String]) -> [TextLine] {
    texts.enumerated().compactMap { index, text in
        guard !text.isEmpty else { return nil }
        let y = top + Double(index) * pitch
        return text.hasPrefix(">")
            ? line(String(text.dropFirst()), x: 0.08, y: y, width: 0.87)
            : line(text, y: y)
    }
}

/// Lines with an ink density each: `heavy` ones at `heavyInk`, the rest at 0.2.
private func measured(_ lines: [TextLine], heavy: Set<String> = [], heavyInk: Double = 0.3) -> PageContent {
    PageContent(lines: lines, lineInk: lines.map {
        LineInk(box: $0.box, density: heavy.contains($0.text) ? heavyInk : 0.2)
    })
}

private func isClose(_ value: Double?, _ expected: Double, tolerance: Double = 0.01) -> Bool {
    value.map { abs($0 - expected) <= tolerance } ?? false
}

@Suite("Block styles")
struct BlockStyleTests {
    private let analyzer = LayoutAnalyzer()

    @Test("a larger heading and a paragraph carry their rules and measurements")
    func largerHeading() throws {
        let lines = [line("Big Title", x: 0.35, y: 0.1, width: 0.3, height: 0.035)]
            + body(top: 0.2, [">body a", "body b", "body c", "body d"])
        let layout = analyzer.layout(of: [PageContent(lines: lines)])
        let styles = layout.styles.blocks
        try #require(styles.count == layout.blocks.count)
        #expect(styles.map(\.rule) == [.largerThanText, .paragraph])

        let heading = styles[0]
        #expect(isClose(heading.lineHeight, 0.035 / 0.017))
        #expect(heading.alignment == .centered)
        #expect(heading.lineCount == 1)
        #expect(heading.spaceAbove == nil)
        #expect(isClose(heading.spaceBelow, 5))
        #expect(isClose(heading.width, 0.3 / 0.9))
        #expect(heading.ink == nil)

        let paragraph = styles[1]
        #expect(isClose(paragraph.lineHeight, 1))
        #expect(paragraph.alignment == .indented)
        #expect(paragraph.lineCount == 4)
        #expect(isClose(paragraph.spaceAbove, 5))
        #expect(paragraph.spaceBelow == nil)
        #expect(isClose(paragraph.width, 1))
        #expect(paragraph.zone == .body)
    }

    @Test("headings at body size are styled by what set them apart")
    func bodySizeHeadings() {
        let around = { (middle: TextLine) in
            body(top: 0.1, ["one a", "one b", "one c"]) + [middle] + body(top: 0.22, ["two a", "two b", "two c"])
        }
        let centered = analyzer.layout(of: [measured(around(line("The Garden", x: 0.35, y: 0.18, width: 0.3)))])
        #expect(centered.styles.blocks.map(\.rule) == [.paragraph, .bodySizeCentered, .paragraph])
        #expect(centered.styles.blocks[1].alignment == .centered)
        #expect(isClose(centered.styles.blocks[1].ink, 1))

        let bold = analyzer.layout(of: [measured(
            around(line("The Garden", y: 0.18, width: 0.3)), heavy: ["The Garden"]
        )])
        #expect(bold.styles.blocks.map(\.rule) == [.paragraph, .bodySizeBold, .paragraph])
        #expect(bold.styles.blocks[1].alignment == .margin)
        #expect(isClose(bold.styles.blocks[1].ink, 1.5))
    }

    @Test("a figure is styled by how its caption was found, or as a picture without one")
    func figures() {
        let picture = PagePicture(imageID: "pic", box: CGRect(x: 0.05, y: 0.2, width: 0.6, height: 0.3))
        let before = body(top: 0.1, [">before a", "before b"])
        let byLabel = analyzer.layout(of: [PageContent(
            lines: before + [line("Fig. 3 The bridge", x: 0.2, y: 0.52, width: 0.3)]
                + body(top: 0.56, [">after a", "after b"]),
            pictures: [picture]
        )])
        #expect(byLabel.styles.blocks.map(\.rule) == [.paragraph, .captionByLabel, .paragraph])
        #expect(byLabel.styles.blocks[1].isUnderPicture)
        #expect(byLabel.styles.blocks[1].lineCount == 1)

        let byGap = analyzer.layout(of: [PageContent(
            lines: before + [line("The bridge", x: 0.2, y: 0.52, width: 0.3)]
                + body(top: 0.58, [">after a", "after b"]),
            pictures: [picture]
        )])
        #expect(byGap.styles.blocks.map(\.rule) == [.paragraph, .captionByGap, .paragraph])

        let bare = analyzer.layout(of: [PageContent(
            lines: before + body(top: 0.52, [">after a", "after b"]), pictures: [picture]
        )])
        #expect(bare.styles.blocks.map(\.rule) == [.paragraph, .picture, .paragraph])
        #expect(bare.styles.blocks[1].lineCount == 0)
        #expect(bare.styles.blocks[2].isUnderPicture)
        #expect(!bare.styles.blocks[0].isUnderPicture)
    }

    @Test("running lines and page numbers are kept as page furniture with their boxes")
    func pageFurniture() throws {
        let pages = (1 ... 6).map { index in
            PageContent(lines: body(top: 0.2, [">body \(index) a", "body \(index) b", "body \(index) c"]) + [
                line("THE DOCUMENT TITLE", x: 0.3, y: 0.04, width: 0.4),
                line("\(index)", x: 0.48, y: 0.95, width: 0.04),
            ])
        }
        let layout = analyzer.layout(of: pages)
        #expect(layout.blocks.count == 6)
        let furniture = layout.styles.pageFurniture
        try #require(furniture.count == 12)
        #expect(furniture.map(\.area.page) == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
        let header = furniture[0]
        #expect(header.text == "THE DOCUMENT TITLE")
        #expect(header.style.rule == .runningLine)
        #expect(header.style.zone == .top)
        #expect(header.style.alignment == .centered)
        #expect(header.area.box == CGRect(x: 0.3, y: 0.04, width: 0.4, height: 0.017))
        let number = furniture[1]
        #expect(number.text == "1")
        #expect(number.style.rule == .pageNumber)
        #expect(number.style.zone == .bottom)
    }

    @Test("the edge zones lie outside where the text of a page usually starts and ends")
    func zones() {
        let full = { (index: Int) in
            body(top: 0.1, [">page \(index) a", "b", "c", "d", ">e", "f", "g", "h", "i", "j"])
        }
        let pages = (0 ..< 4).map { PageContent(lines: full($0)) } + [PageContent(
            lines: [line("Stray", x: 0.6, y: 0.04, width: 0.2)] + body(top: 0.1, [">one", "two", "", ">last"])
                + [line("Below", x: 0.05, y: 0.33, width: 0.2)]
        )]
        let styles = analyzer.layout(of: pages).styles.blocks
        // The last block of the full pages ends where the text usually ends.
        #expect(styles.dropLast(4).allSatisfy { $0.zone == .body })
        #expect(styles.suffix(4).map(\.zone) == [.top, .body, .body, .bottom])
    }

    @Test("a lone page number at the bottom of one page is page furniture too")
    func singlePageNumber() {
        let layout = analyzer.layout(of: [PageContent(
            lines: body(top: 0.2, [">body a", "body b", "body c"]) + [line("17", x: 0.48, y: 0.95, width: 0.04)]
        )])
        #expect(layout.styles.pageFurniture.map(\.text) == ["17"])
        #expect(layout.styles.pageFurniture.map(\.style.rule) == [.pageNumber])
    }

    @Test("a full-width line just short of both edges is not centred")
    func fullWidthLine() {
        let single = analyzer.layout(of: [PageContent(
            lines: body(top: 0.1, [">one a", "one b", "one c", ""]) + [line("alone", x: 0.08, y: 0.18, width: 0.85)]
                + body(top: 0.2, [">two a", "two b", "two c"])
        )])
        #expect(single.styles.blocks.map(\.alignment) == [.indented, .indented, .indented])
    }

    @Test("a paragraph that runs onto the next page counts the lines of both and lies in the body")
    func acrossPages() {
        let layout = analyzer.layout(of: [
            PageContent(lines: body(top: 0.8, [">one a", "one b", "one c", "", ">two a"])),
            PageContent(lines: body(top: 0.1, ["two b", "two c", ">three a", "three b"])),
        ])
        #expect(layout.styles.blocks.map(\.lineCount) == [3, 3, 2])
        #expect(layout.styles.blocks[1].zone == .body)
        #expect(layout.styles.blocks[2].spaceAbove.map { abs($0 - 1) < 0.01 } == true)
    }
}
