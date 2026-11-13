import DocumentModel
import Foundation
import LayoutAnalysis
import OCR
import Testing

/// Same page geometry as `LayoutAnalyzerTests`: body lines 0.017 tall, 0.02
/// apart, margin at x = 0.05, first-line indent at 0.08.
private let pitch = 0.02

/// Body lines at regular pitch starting at `top`. Strings prefixed with ">"
/// are indented; an empty string leaves a blank line.
private func lines(top: Double, _ texts: [String]) -> [TextLine] {
    texts.enumerated().compactMap { index, text in
        guard !text.isEmpty else { return nil }
        let indented = text.hasPrefix(">")
        return TextLine(
            text: indented ? String(text.dropFirst()) : text,
            box: CGRect(x: indented ? 0.08 : 0.05, y: top + Double(index) * pitch, width: 0.87, height: 0.017)
        )
    }
}

/// A picture occupying y 0.2...0.5 of the page.
private let picture = PagePicture(imageID: "pic", box: CGRect(x: 0.05, y: 0.2, width: 0.6, height: 0.3))
private let before = lines(top: 0.1, [">before a", "before b"])

private func figure(caption: [Inline] = []) -> Block {
    .figure(Figure(imageID: "pic", alternativeText: "", caption: caption))
}

@Suite("LayoutAnalyzer pictures")
struct LayoutAnalyzerPictureTests {
    private let analyzer = LayoutAnalyzer()

    @Test("a picture becomes a figure at its place in the text")
    func figureBetweenParagraphs() {
        let page = PageContent(
            lines: before + lines(top: 0.55, [">after a", "after b", "after c"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(),
            .paragraph(["after a after b after c"]),
        ])
    }

    @Test("text recognized inside a picture is dropped instead of becoming a heading")
    func textInsidePicture() {
        let lettering = TextLine(text: "POSTER", box: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.05))
        let page = PageContent(
            lines: before + [lettering] + lines(top: 0.55, [">after a", "after b", "after c"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(),
            .paragraph(["after a after b after c"]),
        ])
    }

    @Test("a block under a picture that starts with a figure label is its caption", arguments: [
        "Fig. 3. A tree in winter.",
        "Figure 12: a diagram",
        "Мал. 27-28. Two drawings",
        "Рис. 5. Schema",
        "Іл. 2. Portrait",
    ])
    func labelledCaption(text: String) {
        let page = PageContent(
            lines: before + lines(top: 0.52, [">" + text, "second caption line", "", ">body a", "body b"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(caption: [.text(text + " second caption line")]),
            .paragraph(["body a body b"]),
        ])
    }

    @Test("a block under a picture set apart by extra space is its caption")
    func isolatedCaption() {
        let page = PageContent(
            lines: before + lines(top: 0.55, [">A photo taken", "in 1998.", "", "", ">body a", "body b", "body c"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(caption: ["A photo taken in 1998."]),
            .paragraph(["body a body b body c"]),
        ])
    }

    @Test("an ordinary paragraph gap under a picture does not make a caption")
    func ordinaryParagraphUnderPicture() {
        let page = PageContent(
            lines: before + lines(top: 0.55, [">body a", "body b", "", ">body c", "body d", "body e"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(),
            .paragraph(["body a body b"]),
            .paragraph(["body c body d body e"]),
        ])
    }

    @Test("a heading under a picture is never a caption")
    func headingUnderPicture() {
        let heading = TextLine(text: "Fig Trees", box: CGRect(x: 0.05, y: 0.55, width: 0.3, height: 0.035))
        let page = PageContent(
            lines: before + [heading] + lines(top: 0.7, [">body a", "body b", "body c"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(),
            .heading(level: 1, content: ["Fig Trees"]),
            .paragraph(["body a body b body c"]),
        ])
    }

    @Test("a labelled caption at the end of a page does not swallow the next page")
    func captionAtPageEnd() {
        let first = PageContent(lines: before + lines(top: 0.52, [">Fig. 1. Last on the page"]), pictures: [picture])
        let second = PageContent(lines: lines(top: 0.1, ["carried a", "carried b", "carried c"]), pictures: [])
        #expect(analyzer.blocks(from: [first, second]) == [
            .paragraph(["before a before b"]),
            figure(caption: ["Fig. 1. Last on the page"]),
            .paragraph(["carried a carried b carried c"]),
        ])
    }

    @Test("an unlabelled paragraph under a picture still continues onto the next page")
    func paragraphUnderPictureContinues() {
        let first = PageContent(lines: before + lines(top: 0.55, [">para a", "para b"]), pictures: [picture])
        let second = PageContent(lines: lines(top: 0.1, ["para c", "para d", ">next"]), pictures: [])
        #expect(analyzer.blocks(from: [first, second]) == [
            .paragraph(["before a before b"]),
            figure(),
            .paragraph(["para a para b para c para d"]),
            .paragraph(["next"]),
        ])
    }

    @Test("a paragraph does not run on across a picture")
    func pictureBreaksParagraph() {
        let page = PageContent(
            lines: before + lines(top: 0.55, ["unindented a", "unindented b", "unindented c"]),
            pictures: [picture]
        )
        #expect(analyzer.blocks(from: [page]) == [
            .paragraph(["before a before b"]),
            figure(),
            .paragraph(["unindented a unindented b unindented c"]),
        ])
    }

    @Test("a page that is only a picture gives only a figure")
    func pictureOnly() {
        #expect(analyzer.blocks(from: [PageContent(lines: [], pictures: [picture])]) == [figure()])
    }

    @Test("every block records the page it starts on and the area it covers there")
    func blockSources() {
        let first = PageContent(lines: lines(top: 0.1, [">one a", "one b", ">two a", "two b"]))
        let second = PageContent(
            lines: lines(top: 0.1, ["two c", "two d"]) + lines(top: 0.55, [">three a", "three b"]),
            pictures: [picture]
        )

        let layout = analyzer.layout(of: [first, second])

        #expect(layout.blocks == [
            .paragraph(["one a one b"]), .paragraph(["two a two b two c two d"]), figure(),
            .paragraph(["three a three b"]),
        ])
        #expect(layout.sources.map(\.page) == [0, 0, 1, 1])
        // First line indented to 0.08, second at the margin: the union.
        #expect(layout.sources[0].box.isClose(to: CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.037)))
        // Only the part on the page where the block starts.
        #expect(layout.sources[1].box.isClose(to: CGRect(x: 0.05, y: 0.14, width: 0.9, height: 0.037)))
        #expect(layout.sources[2].box == picture.box)
    }

    @Test("a caption widens the area of its figure instead of adding a block")
    func captionSource() {
        let page = PageContent(
            lines: before + lines(top: 0.52, ["Fig. 1. A caption"]) + lines(top: 0.6, [">after a", "after b"]),
            pictures: [picture]
        )

        let layout = analyzer.layout(of: [page])

        #expect(layout.blocks.count == 3)
        #expect(layout.sources.count == 3)
        #expect(layout.sources[1].box.isClose(to: CGRect(x: 0.05, y: 0.2, width: 0.87, height: 0.337)))
    }
}

private extension CGRect {
    /// Equal within floating-point noise from adding up line positions.
    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 1e-9 && abs(minY - other.minY) < 1e-9
            && abs(width - other.width) < 1e-9 && abs(height - other.height) < 1e-9
    }
}
