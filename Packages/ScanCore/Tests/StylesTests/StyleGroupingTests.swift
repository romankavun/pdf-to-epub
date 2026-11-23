import CoreGraphics
import DocumentModel
import LayoutAnalysis
import Styles
import Testing

/// A block's source: one line high at `top` of `page`.
private func source(page: Int, top: Double = 0.2) -> BlockSource {
    BlockSource(page: page, box: CGRect(x: 0.1, y: top, width: 0.8, height: 0.02))
}

private let paragraph = Block.paragraph(["Text."])
private let heading = Block.heading(level: 1, content: ["Title"])

private func body(lineHeight: Double = 1, width: Double = 1, alignment: BlockStyle.Alignment = .indented)
    -> BlockStyle
{
    BlockStyle(rule: .paragraph, lineHeight: lineHeight, ink: 1, alignment: alignment, width: width, lineCount: 5)
}

private let title = BlockStyle(
    rule: .largerThanText, lineHeight: 1.8, ink: 1.1, alignment: .centered, width: 0.4, spaceBelow: 3
)

/// The styles of blocks given with their style and source.
private func styles(_ blocks: [(Block, BlockStyle, BlockSource)], notes: [(BlockStyle, BlockSource)] = [],
                    furniture: [PageFurniture] = []) -> [Style]
{
    StyleGrouping.styles(
        blocks: blocks.map(\.0), blockSources: blocks.map(\.2), noteSources: notes.map(\.1),
        styles: BlockStyles(blocks: blocks.map(\.1), notes: notes.map(\.0), pageFurniture: furniture)
    )
}

@Suite("Style grouping")
struct StyleGroupingTests {
    @Test("blocks of one type, rule and look form one style, with their pages")
    func oneStyle() throws {
        let found = styles([
            (paragraph, body(), source(page: 0)), (paragraph, body(), source(page: 0, top: 0.5)),
            (paragraph, body(), source(page: 3)),
        ])
        let style = try #require(found.first)
        #expect(found.count == 1)
        #expect(style.type == .paragraph)
        #expect(style.rule == .paragraph)
        #expect(style.members == [.block(0), .block(1), .block(2)])
        #expect(style.pages == [0, 3])
        #expect(style.number == nil)
        #expect(style.paletteIndex == 0)
    }

    @Test("a different type, rule or heading level makes a style of its own")
    func typeAndRule() {
        let found = styles([
            (heading, title, source(page: 0)),
            (.heading(level: 2, content: ["Sub"]), title, source(page: 1)),
            (paragraph, title, source(page: 2)),
            (heading, BlockStyle(rule: .bodySizeBold, lineHeight: 1.8, ink: 1.1, alignment: .centered, width: 0.4),
             source(page: 3)),
        ])
        #expect(found.map(\.type) == [.heading(level: 1), .heading(level: 2), .paragraph, .heading(level: 1)])
        #expect(found.map(\.rule) == [.largerThanText, .largerThanText, .largerThanText, .bodySizeBold])
    }

    @Test("small differences in measurement stay in one style; a clear one splits it")
    func closeFeatures() {
        let noisy = styles([
            (paragraph, body(lineHeight: 1), source(page: 0)),
            (paragraph, body(lineHeight: 1.05, width: 0.97), source(page: 1)),
            (paragraph, body(lineHeight: 0.96, width: 0.99), source(page: 2)),
        ])
        #expect(noisy.count == 1)

        let distinct = styles([
            (paragraph, body(lineHeight: 1), source(page: 0)),
            (paragraph, body(lineHeight: 0.6), source(page: 1)),
            (paragraph, body(alignment: .centered), source(page: 2)),
            (paragraph, body(width: 0.4), source(page: 3)),
        ])
        #expect(distinct.count == 4)
    }

    @Test("body text measured a little short or long, light or heavy, stays one style")
    func bodyNoise() {
        let found = styles([
            (paragraph, body(lineHeight: 0.9), source(page: 0)),
            (paragraph, body(lineHeight: 1.0), source(page: 1)),
            (paragraph, body(lineHeight: 1.3), source(page: 2)),
            (paragraph, BlockStyle(rule: .paragraph, ink: 0.85, alignment: .indented, lineCount: 5), source(page: 3)),
            (paragraph, BlockStyle(rule: .paragraph, ink: 1.25, alignment: .indented, lineCount: 5), source(page: 4)),
        ])
        #expect(found.count == 1)
    }

    @Test("a single line measured short or light, as digits are, is body text; several such lines are small print")
    func shortSingleLines() {
        let number = { (height: Double, ink: Double) in
            BlockStyle(
                rule: .pageNumber,
                lineHeight: height,
                ink: ink,
                alignment: .centered,
                width: 0.05,
                zone: .bottom
            )
        }
        let furniture = [(0.55, 0.6), (0.7, 1.0), (0.85, 1.1)].enumerated().map { page, measured in
            PageFurniture(
                area: PageArea(page: page, box: CGRect(x: 0.45, y: 0.95, width: 0.05, height: 0.02)), text: "\(page)",
                style: number(measured.0, measured.1)
            )
        }
        #expect(styles([], furniture: furniture).count == 1)

        let small = styles([
            (paragraph, body(lineHeight: 1.0), source(page: 0)), (paragraph, body(lineHeight: 0.7), source(page: 1)),
        ])
        #expect(small.count == 2)
    }

    @Test("bold headings are not split by how heavy their ink is; other blocks are, when clearly heavier")
    func boldInk() {
        let bold = { (ink: Double) in
            BlockStyle(rule: .bodySizeBold, ink: ink, alignment: .margin, width: 0.3)
        }
        #expect(styles([(heading, bold(1.2), source(page: 0)), (heading, bold(1.6), source(page: 1))]).count == 1)
        let line = { (ink: Double) in BlockStyle(rule: .paragraph, ink: ink, alignment: .indented, width: 0.3) }
        #expect(styles([(paragraph, line(1.0), source(page: 0)), (paragraph, line(1.6), source(page: 1))]).count == 2)
    }

    @Test("styles that share a type and rule are numbered in order of first appearance")
    func numbering() {
        let found = styles([
            (heading, title, source(page: 0)),
            (paragraph, body(alignment: .margin), source(page: 1)),
            (paragraph, body(), source(page: 0, top: 0.5)),
        ])
        #expect(found.map(\.type) == [.heading(level: 1), .paragraph, .paragraph])
        #expect(found.map(\.number) == [nil, 1, 2])
        #expect(found.map(\.members) == [[.block(0)], [.block(2)], [.block(1)]])
    }

    @Test("note texts and page furniture are styles too, coloured by where they first appear")
    func notesAndFurniture() {
        let number = PageFurniture(
            area: PageArea(page: 0, box: CGRect(x: 0.45, y: 0.95, width: 0.05, height: 0.02)), text: "1",
            style: BlockStyle(rule: .pageNumber, width: 0.05, zone: .bottom)
        )
        let header = PageFurniture(
            area: PageArea(page: 0, box: CGRect(x: 0.3, y: 0.03, width: 0.4, height: 0.02)), text: "TITLE",
            style: BlockStyle(rule: .runningLine, alignment: .centered, width: 0.4, zone: .top)
        )
        let found = styles(
            [(paragraph, body(), source(page: 0))],
            notes: [(
                BlockStyle(rule: .noteText, lineHeight: 0.8, opensWithNoteLabel: true),
                source(page: 0, top: 0.7)
            )],
            furniture: [header, number]
        )
        #expect(found.map(\.type) == [.pageFurniture, .paragraph, .note, .pageFurniture])
        #expect(found.map(\.rule) == [.runningLine, .paragraph, .noteText, .pageNumber])
        #expect(found.map(\.members) == [[.pageFurniture(0)], [.block(0)], [.note(0)], [.pageFurniture(1)]])
        #expect(found.map(\.paletteIndex) == [0, 1, 2, 3])
    }

    @Test("a style's typical look is the median of its blocks")
    func typical() {
        let found = styles([
            (paragraph, body(lineHeight: 1.0), source(page: 0)),
            (paragraph, body(lineHeight: 1.04), source(page: 1)),
            (paragraph, body(lineHeight: 0.98), source(page: 2)),
        ])
        #expect(found.first?.typical.lineHeight == 1.0)
        #expect(found.first?.typical.rule == .paragraph)
    }

    @Test("types sort as the overview groups them: headings by level, then paragraphs, figures, notes, furniture")
    func typeOrder() {
        let types: [StyleType] = [.pageFurniture, .note, .figure, .paragraph, .heading(level: 2), .heading(level: 1)]
        #expect(types.sorted() == [.heading(level: 1), .heading(level: 2), .paragraph, .figure, .note, .pageFurniture])
    }
}
