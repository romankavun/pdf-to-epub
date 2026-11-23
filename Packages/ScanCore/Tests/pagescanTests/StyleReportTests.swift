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
}
