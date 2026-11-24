import LayoutAnalysis
@testable import PDFToEPUB
import Styles
import Testing

/// The names and colours the sidebar gives a style (`StyleNames.swift`).
/// The strings are the English base of the String Catalog.
struct StyleNamesTests {
    private func style(
        _ type: StyleType, rule: DecidingRule, number: Int? = nil,
        look: BlockStyle? = nil
    ) -> Styles.Style {
        Styles.Style(
            type: type, rule: rule, number: number, members: [], pages: [0], paletteIndex: 0,
            typical: look ?? BlockStyle(rule: rule, ink: 1, width: 0.5)
        )
    }

    @Test func titleIsTheTypeNumberedOnlyWhenTheTypeHasOtherStyles() {
        #expect(style(.paragraph, rule: .paragraph).title == "Paragraph")
        #expect(style(.paragraph, rule: .paragraph, number: 2).title == "Paragraph (2)")
        #expect(style(.heading(level: 1), rule: .largerThanText, number: 3).title == "Heading 1 (3)")
        #expect(style(.pageFurniture, rule: .pageNumber).title == "Page furniture")
    }

    @Test func nameAddsTheRuleUnlessItRepeatsTheType() {
        #expect(style(.paragraph, rule: .paragraph, number: 2).name == "Paragraph (2)")
        #expect(style(.note, rule: .noteText).name == "Note text")
        #expect(
            style(.heading(level: 1), rule: .largerThanText).name == "Heading 1 · larger than the text"
        )
        #expect(style(.paragraph, rule: .bodySizeCentered).name == "Paragraph · body size, centred")
    }

    @Test func subtitleSaysWhatSetsTheStyleApart() {
        let body = BlockStyle(rule: .paragraph, ink: 1, alignment: .indented, lineCount: 5)
        #expect(style(.paragraph, rule: .paragraph, look: body).subtitle == "indented, full width, 5 lines")
        #expect(style(.paragraph, rule: .paragraph).subtitle == "Looks like the body text")
        let title = BlockStyle(rule: .largerThanText, lineHeight: 1.6, ink: 1, alignment: .centered, width: 0.4)
        let subtitle = style(.heading(level: 1), rule: .largerThanText, look: title).subtitle
        // The number follows the region's decimal separator.
        let height = 1.6.formatted(.number.precision(.fractionLength(1)))
        #expect(subtitle == "larger than the text · \(height) × taller than the text, centred")
    }

    @Test func stylesOfATypeShareItsHueInDifferentShades() {
        let shades = (1 ... 9).map { style(.paragraph, rule: .paragraph, number: $0).shade }
        #expect(Set(shades.map(\.hue)) == [StyleType.paragraph.hue])
        let distinct = Set(shades)
        #expect(distinct.count == 9)
        // The only style of its type takes the first shade.
        let only = style(.paragraph, rule: .paragraph).shade
        #expect(only == shades[0])
    }

    @Test func typesHaveDifferentHuesAndPageFurnitureIsGrey() {
        let types: [StyleType] = [
            .heading(level: 1),
            .heading(level: 2),
            .heading(level: 3),
            .paragraph,
            .figure,
            .note,
        ]
        let hues = types.map(\.hue)
        #expect(hues.allSatisfy { $0 != nil })
        #expect(Set(hues).count == types.count)
        #expect(style(.pageFurniture, rule: .pageNumber).shade.hue == nil)
        let greys = (1 ... 3).map { style(.pageFurniture, rule: .runningLine, number: $0).shade.brightness }
        #expect(Set(greys).count == 3)
    }
}
