import CoreGraphics
import DocumentModel
import LayoutAnalysis
import Styles
import Testing

/// A style of `count` members of `type`, one per page from 0, looking like `typical`.
private func style(
    _ type: StyleType, rule: DecidingRule, count: Int, typical: BlockStyle,
    member: (Int) -> StyleMember = StyleMember.block
) -> Style {
    Style(
        type: type, rule: rule, number: nil, members: (0 ..< count).map(member), pages: Array(0 ..< count),
        paletteIndex: 0, typical: typical
    )
}

/// The block styles for `count` blocks that all look like `look`.
private func blocks(_ count: Int, _ look: BlockStyle) -> BlockStyles {
    BlockStyles(blocks: Array(repeating: look, count: count))
}

/// One-line paragraphs: `open` that stop mid-sentence, then `closed` that end one.
private func lines(open: Int, closed: Int) -> [Block] {
    Array(repeating: .paragraph(["the first line of a paragraph, which goes on"]), count: open)
        + Array(repeating: .paragraph(["— A whole line of dialogue."]), count: closed)
}

/// Lines of page furniture, one per page, with these texts and widths.
private func furniture(_ lines: [(text: String, width: Double)], rule: DecidingRule = .runningLine) -> BlockStyles {
    BlockStyles(pageFurniture: lines.enumerated().map { page, line in
        PageFurniture(
            area: PageArea(page: page, box: CGRect(x: 0.1, y: 0.03, width: 0.8 * line.width, height: 0.02)),
            text: line.text,
            style: BlockStyle(rule: rule, width: line.width, zone: .top)
        )
    })
}

private func furnitureStyle(_ styles: BlockStyles, rule: DecidingRule = .runningLine) -> Style {
    let widths = styles.pageFurniture.map(\.style.width).sorted()
    return style(
        .pageFurniture, rule: rule, count: styles.pageFurniture.count,
        typical: BlockStyle(rule: rule, width: widths[(widths.count - 1) / 2], zone: .top),
        member: StyleMember.pageFurniture
    )
}

@Suite("Style warnings")
struct StyleWarningTests {
    // MARK: - Heading at the page edge

    @Test("a heading style at the top edge of several pages is probably a running header")
    func headingAtTopEdge() {
        let look = BlockStyle(rule: .largerThanText, lineHeight: 1.6, alignment: .centered, width: 0.4, zone: .top)
        let found = style(.heading(level: 2), rule: .largerThanText, count: 4, typical: look)
        #expect(StyleWarning(for: found, in: blocks(4, look)) == .headingAtPageEdge(pages: 4))
    }

    @Test("at the bottom edge too")
    func headingAtBottomEdge() {
        let look = BlockStyle(rule: .bodySizeBold, width: 0.3, zone: .bottom)
        let found = style(.heading(level: 3), rule: .bodySizeBold, count: 5, typical: look)
        #expect(StyleWarning(for: found, in: blocks(5, look)) == .headingAtPageEdge(pages: 5))
    }

    @Test("a heading at the edge of a page or two is a chapter title, not a running header")
    func headingAtEdgeOfFewPages() {
        let look = BlockStyle(rule: .largerThanText, lineHeight: 1.6, width: 0.4, zone: .top)
        let found = style(.heading(level: 1), rule: .largerThanText, count: StyleWarning.edgeHeadingPages - 1,
                          typical: look)
        #expect(StyleWarning(for: found, in: blocks(found.members.count, look)) == nil)
    }

    @Test("headings in the body of the page are not marked")
    func headingInBody() {
        let look = BlockStyle(rule: .largerThanText, lineHeight: 1.6, width: 0.4)
        let found = style(.heading(level: 1), rule: .largerThanText, count: 20, typical: look)
        #expect(StyleWarning(for: found, in: blocks(20, look)) == nil)
    }

    // MARK: - Lines not joined

    @Test("one-line paragraphs across the full width that stop mid-sentence are lines that were not joined")
    func unjoinedLines() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .margin, width: 0.99)
        let count = StyleWarning.unjoinedLineMinimum
        let found = style(.paragraph, rule: .paragraph, count: count, typical: look)
        let lines = lines(open: count, closed: 0)
        #expect(StyleWarning(for: found, in: blocks(count, look), blocks: lines) == .unjoinedLines(count: count))
    }

    @Test("a quarter of the lines stopping mid-sentence is enough: the last line of each paragraph ends one")
    func someLinesEndSentences() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .margin, width: 0.99)
        let found = style(.paragraph, rule: .paragraph, count: 30, typical: look)
        #expect(StyleWarning(for: found, in: blocks(30, look), blocks: lines(open: 12, closed: 18))
            == .unjoinedLines(count: 12))
    }

    @Test("full lines that end their sentence are one-line paragraphs, such as dialogue")
    func dialogue() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, width: 0.95)
        let found = style(.paragraph, rule: .paragraph, count: 300, typical: look)
        #expect(StyleWarning(for: found, in: blocks(300, look), blocks: lines(open: 20, closed: 280)) == nil)
    }

    @Test("a few lines that stop mid-sentence are left to the block list")
    func fewOpenLines() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .margin, width: 0.99)
        let count = StyleWarning.unjoinedLineMinimum - 1
        let found = style(.paragraph, rule: .paragraph, count: count, typical: look)
        #expect(StyleWarning(for: found, in: blocks(count, look), blocks: lines(open: count, closed: 0)) == nil)
    }

    @Test("short one-line paragraphs and paragraphs of several lines are not marked")
    func shortOrLong() {
        let short = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, width: 0.5)
        #expect(StyleWarning(for: style(.paragraph, rule: .paragraph, count: 40, typical: short),
                             in: blocks(40, short), blocks: lines(open: 40, closed: 0)) == nil)
        let long = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, width: 1, lineCount: 6)
        #expect(StyleWarning(for: style(.paragraph, rule: .paragraph, count: 40, typical: long),
                             in: blocks(40, long), blocks: lines(open: 40, closed: 0)) == nil)
    }

    @Test("a line ends its sentence with a stop, a closing quote or bracket, before trailing spaces")
    func sentenceEnds() {
        for ending in ["Done.", "Really?", "Go!", "Wait…", "As follows:", "one; two;", "«Так»", "\"So\"", "(1990)",
                       "Done. "]
        {
            #expect(StyleWarning.endsSentence(.paragraph([.text(ending)])), "\(ending)")
        }
        for ending in ["and then the", "Ф. Р-119, оп. 17,", "word-", "— сказав він"] {
            #expect(!StyleWarning.endsSentence(.paragraph([.text(ending)])), "\(ending)")
        }
        #expect(StyleWarning.endsSentence(.paragraph([.text("A note."), .noteReference("n1")])))
    }

    // MARK: - Text probably misrecognized

    @Test("a style whose blocks are mostly text probably misrecognized is marked")
    func mostlyMisrecognized() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
        let found = style(.paragraph, rule: .paragraph, count: 5, typical: look)
        let misread: Set<StyleMember> = [.block(0), .block(2), .block(4)]
        #expect(StyleWarning(for: found, in: blocks(5, look), misrecognized: misread) == .mostlyMisrecognized(
            count: 3
        ))
    }

    @Test("half of the blocks or fewer is not most of them")
    func halfMisrecognized() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
        let found = style(.paragraph, rule: .paragraph, count: 6, typical: look)
        let misread: Set<StyleMember> = [.block(0), .block(2), .block(4)]
        #expect(StyleWarning(for: found, in: blocks(6, look), misrecognized: misread) == nil)
    }

    @Test("one or two misread blocks are left to the block list")
    func fewMisrecognized() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
        let count = StyleWarning.misrecognizedMinimum - 1
        let found = style(.paragraph, rule: .paragraph, count: count, typical: look)
        let misread = Set(found.members)
        #expect(StyleWarning(for: found, in: blocks(count, look), misrecognized: misread) == nil)
    }

    @Test("misread members of other styles do not count")
    func otherMembers() {
        let look = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
        let found = style(.paragraph, rule: .paragraph, count: 3, typical: look)
        let misread: Set<StyleMember> = [.block(7), .block(8), .block(9), .note(0)]
        #expect(StyleWarning(for: found, in: blocks(10, look), misrecognized: misread) == nil)
    }

    // MARK: - Page furniture that looks like text

    @Test("page furniture with long lines is probably body text removed by mistake")
    func longFurniture() {
        let lines = furniture(Array(repeating: (text: "a line of the text", width: 0.9), count: 20))
        #expect(StyleWarning(for: furnitureStyle(lines), in: lines) == .furnitureLooksLikeText)
    }

    @Test("page furniture whose text varies from page to page is probably body text")
    func varyingFurniture() {
        let texts = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa"]
        let lines = furniture(texts.map { (text: $0, width: 0.3) })
        #expect(StyleWarning(for: furnitureStyle(lines), in: lines) == .furnitureLooksLikeText)
    }

    @Test("a short running header, the same on every page bar its page number, is not marked")
    func runningHeader() {
        let lines = furniture((1 ... 30).map { (text: "\($0) THE TITLE", width: 0.35) })
        #expect(StyleWarning(for: furnitureStyle(lines), in: lines) == nil)
    }

    @Test("left and right running headers, two texts in turn, are not marked")
    func alternatingHeaders() {
        let lines = furniture((1 ... 30).map { (text: $0.isMultiple(of: 2) ? "AUTHOR" : "Book Title", width: 0.3) })
        #expect(StyleWarning(for: furnitureStyle(lines), in: lines) == nil)
    }

    @Test("page numbers are not marked")
    func pageNumbers() {
        let lines = furniture((1 ... 30).map { (text: "\($0)", width: 0.03) }, rule: .pageNumber)
        #expect(StyleWarning(for: furnitureStyle(lines, rule: .pageNumber), in: lines) == nil)
    }

    // MARK: - Ordinary styles

    @Test("body paragraphs, a figure and note texts are not marked")
    func ordinaryStyles() {
        let body = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 8)
        #expect(StyleWarning(for: style(.paragraph, rule: .paragraph, count: 300, typical: body),
                             in: blocks(300, body)) == nil)
        let caption = BlockStyle(rule: .captionByLabel, alignment: .centered, width: 0.5, isUnderPicture: true)
        #expect(StyleWarning(for: style(.figure, rule: .captionByLabel, count: 12, typical: caption),
                             in: blocks(12, caption)) == nil)
    }
}
