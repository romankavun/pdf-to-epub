import DocumentModel
import Foundation
@testable import LayoutAnalysis
import OCR
import Testing

/// Body lines 0.017 tall at a pitch of 0.02; an indented first line starts
/// 0.03 right of the margin.
private let pitch = 0.02, indentDepth = 0.03

/// A page whose left margin is `margin(y)` at height `y`: a scanned leaf
/// lies on the glass at a slant, or curves towards the gutter, so the lines
/// start further left the lower they are. Strings prefixed with ">" are
/// indented first lines.
private func page(top: Double = 0.1, margin: (Double) -> Double, _ texts: [String]) -> RecognizedPage {
    RecognizedPage(lines: texts.enumerated().map { index, text in
        let y = top + Double(index) * pitch
        let indented = text.hasPrefix(">")
        let x = margin(y) + (indented ? indentDepth : 0)
        return TextLine(
            text: indented ? String(text.dropFirst()) : text,
            box: CGRect(x: x, y: y, width: 0.75 - (indented ? indentDepth : 0), height: 0.017)
        )
    })
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

/// Twenty lines of prose: four paragraphs of five lines.
private let prose = (0 ..< 20).map { index in
    (index.isMultiple(of: 5) ? ">" : "") + "p\(index / 5) l\(index % 5)"
}

private let expected = (0 ..< 4).map { paragraph in
    (0 ..< 5).map { "p\(paragraph) l\($0)" }.joined(separator: " ")
}

@Suite("Paragraphs on scanned pages")
struct ScannedParagraphTests {
    private let analyzer = LayoutAnalyzer(options: .paperScan)

    @Test("a margin that drifts down the page does not make every line a paragraph")
    func driftingMargin() {
        // From 0.20 at the top to 0.13 at the bottom: more than twice the
        // indent, as on a leaf lying at a slant.
        let slanted = page(margin: { 0.22 - 0.14 * $0 }, prose)
        #expect(paragraphs(analyzer.blocks(from: [slanted])) == expected)
    }

    @Test("pages cropped differently each keep their own margin")
    func marginPerPage() {
        let pages = [
            page(margin: { _ in 0.10 }, prose),
            page(margin: { _ in 0.14 }, prose),
            page(margin: { _ in 0.14 }, prose),
        ]
        #expect(paragraphs(analyzer.blocks(from: pages)) == expected + expected + expected)
    }

    @Test("clean pages keep the document's margin on every page, even a page whose lines are all indented")
    func cleanPagesShareTheMargin() {
        let notes = page(margin: { _ in 0.10 }, (1 ... 7).map { ">note \($0)" })
        let blocks = LayoutAnalyzer().blocks(from: [page(margin: { _ in 0.10 }, prose), notes])
        #expect(paragraphs(blocks).suffix(7) == (1 ... 7).map { "note \($0)" })
    }

    @Test("a page with only a few lines uses the margin of the document")
    func fewLines() {
        let full = page(margin: { _ in 0.10 }, prose)
        // Two continuation lines alone would be taken for the margin and the
        // indented line would look like one; the document's margin decides.
        let short = page(margin: { _ in 0.10 }, [">a", "b", ">c"])
        #expect(paragraphs(analyzer.blocks(from: [full, short])).suffix(2) == ["a b", "c"])
    }
}

@Suite("Soft hyphens on paper scans")
struct SoftHyphenTests {
    private func joined(_ first: String, _ second: String, softHyphens: Bool) -> String? {
        var options = LayoutAnalyzer.Options()
        options.removesSoftHyphens = softHyphens
        let lines = page(margin: { _ in 0.1 }, [">" + first, second])
        return paragraphs(LayoutAnalyzer(options: options).blocks(from: [lines])).first
    }

    @Test("a word broken by the typesetter is joined without the hyphen")
    func softHyphenRemoved() {
        #expect(joined("small con-", "tainers here", softHyphens: true) == "small containers here")
    }

    @Test("a hyphen before a capital letter belongs to the word and is kept")
    func hyphenBeforeCapitalKept() {
        #expect(joined("the Anglo-", "Saxon king", softHyphens: true) == "the Anglo-Saxon king")
    }

    @Test("clean-page source text keeps the hyphen, as clean-page sources add none of their own")
    func cleanPageKeepsHyphen() {
        #expect(joined("small half-", "baked idea", softHyphens: false) == "small half-baked idea")
    }
}
