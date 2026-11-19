import CoreGraphics
import DocumentModel
import Foundation
import LayoutAnalysis
import OCR
import Testing
import TestSupport

/// A page of prose: paragraphs of one to six lines whose first line is
/// indented by 0.03 and whose last line is often short, with a blank line
/// now and then. Returns the lines as (text, left edge, top, width) at
/// margin 0, and the text of each paragraph.
private func prose(
    _ generator: DocumentGenerator, _ random: inout SeededGenerator
) -> (lines: [(String, Double, Double, Double)], paragraphs: [String]) {
    var lines: [(String, Double, Double, Double)] = []
    var paragraphs: [String] = []
    var top = 0.1
    var counter = 0
    let target = random.int(8 ... 30)
    while lines.count < target {
        let count = random.int(1 ... 6)
        var paragraph: [String] = []
        for index in 0 ..< count {
            counter += 1
            let text = generator.words(&random, count: 2 ... 6) + " n\(counter)"
            let first = index == 0
            let last = index == count - 1
            let width = last && random.chance(0.6) ? random.double(0.15 ... 0.45) : 0.8 - (first ? 0.03 : 0)
            lines.append((text, first ? 0.03 : 0, top, width))
            paragraph.append(text)
            top += 0.02
        }
        paragraphs.append(paragraph.joined(separator: " "))
        if random.chance(0.2) {
            top += 0.02
        }
    }
    return (lines, paragraphs)
}

private func texts(_ blocks: [Block]) -> [String] {
    blocks.map {
        switch $0 {
        case let .heading(_, content), let .paragraph(content): content.plainText
        case let .figure(figure): figure.caption.plainText
        }
    }
}

@Suite("Page geometry invariants")
struct PageGeometryInvariantTests {
    private let generator = DocumentGenerator(text: .tidy)

    @Test("where a page lies on the scanner, shifted sideways or at a slant, does not change its paragraphs")
    func shiftAndSlant() {
        let analyzer = LayoutAnalyzer(options: .paperScan)
        Property.check("shift and slant", cases: 200) { random in
            let (lines, paragraphs) = prose(generator, &random)
            func page(margin: Double, slope: Double) -> RecognizedPage {
                RecognizedPage(lines: lines.map { text, indent, top, width in
                    TextLine(
                        text: text,
                        box: CGRect(x: margin + slope * top + indent, y: top, width: width, height: 0.017)
                    )
                })
            }
            let straight = texts(analyzer.blocks(from: [page(margin: 0.1, slope: 0)]))
            try Property.requireEqual(straight, paragraphs, "a straight page")
            let margin = random.double(0.04 ... 0.2)
            // A leaf at a slant moves its lines by up to 0.1 of the width
            // from top to bottom: several indents.
            let slope = random.double(-0.15 ... 0.15)
            let placed = texts(analyzer.blocks(from: [page(margin: margin, slope: slope)]))
            try Property.requireEqual(placed, paragraphs, "margin \(margin), slope \(slope)")
        }
    }
}
