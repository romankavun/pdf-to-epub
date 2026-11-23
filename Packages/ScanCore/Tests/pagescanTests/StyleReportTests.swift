import DocumentModel
import LayoutAnalysis
@testable import pagescan
import Styles
import Testing

@Suite("Style report")
struct StyleReportTests {
    @Test("prints each style with its type, deciding rule, number of blocks and pages, grouped by type")
    func report() {
        let styles = [
            Style(
                type: .paragraph, rule: .paragraph, number: 1, members: [.block(1), .block(2), .block(3)],
                pages: [0, 1, 2, 3, 7], paletteIndex: 0, typical: BlockStyle(rule: .paragraph)
            ),
            Style(
                type: .heading(level: 1), rule: .largerThanText, number: nil, members: [.block(0)], pages: [0],
                paletteIndex: 1,
                typical: BlockStyle(rule: .largerThanText, lineHeight: 1.62, ink: 1.04, alignment: .centered)
            ),
            Style(
                type: .pageFurniture, rule: .pageNumber, number: nil, members: [.pageFurniture(0)], pages: [4],
                paletteIndex: 2, typical: BlockStyle(rule: .pageNumber, zone: .bottom)
            ),
        ]
        #expect(StyleReport.lines(for: styles) == [
            "Styles: 3",
            "  Heading 1 · larger than the text: 1 block, page 1 (height 1.62, ink 1.04, centered, 1 line)",
            "  Paragraph 1 · paragraph: 3 blocks, pages 1-4, 8 (height 1.00, margin, 1 line)",
            "  Page furniture · page number: 1 block, page 5 (height 1.00, margin, bottom, 1 line)",
        ])
    }

    @Test("prints a probably-wrong style's warning under it, and how many there are")
    func warnings() {
        let heading = Style(
            type: .heading(level: 2), rule: .bodySizeBold, number: nil, members: [.block(0), .block(1), .block(2)],
            pages: [0, 1, 2], paletteIndex: 0, typical: BlockStyle(rule: .bodySizeBold, zone: .top)
        )
        let lines = Style(
            type: .paragraph, rule: .paragraph, number: nil, members: [.block(3)], pages: [3], paletteIndex: 1,
            typical: BlockStyle(rule: .paragraph)
        )
        let furniture = Style(
            type: .pageFurniture, rule: .runningLine, number: nil, members: [.pageFurniture(0)], pages: [4],
            paletteIndex: 2, typical: BlockStyle(rule: .runningLine, zone: .top)
        )
        let warnings: [Style.ID: StyleWarning] = [
            0: .headingAtPageEdge(pages: 3), 1: .unjoinedLines(count: 12), 2: .furnitureLooksLikeText,
        ]
        #expect(StyleReport.lines(for: [heading, lines, furniture], warnings: warnings) == [
            "Styles: 3, probably wrong: 3",
            "  Heading 2 · body size and bold: 3 blocks, pages 1-3 (height 1.00, margin, top, 1 line)",
            "    probably wrong: at the page edge on 3 pages, a running header?",
            "  Paragraph · paragraph: 1 block, page 4 (height 1.00, margin, 1 line)",
            "    probably wrong: 12 full-width one-line paragraphs stop mid-sentence, lines not joined?",
            "  Page furniture · repeats at the page edge: 1 block, page 5 (height 1.00, margin, top, 1 line)",
            "    probably wrong: long lines or text that varies from page to page, body text removed?",
        ])
        let misread = StyleReport.lines(for: [lines], warnings: [1: .mostlyMisrecognized(count: 4)])
        #expect(misread.last == "    probably wrong: 4 blocks are text probably misrecognized")
    }
}
