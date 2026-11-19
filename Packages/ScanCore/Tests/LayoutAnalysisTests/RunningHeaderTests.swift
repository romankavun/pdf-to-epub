import DocumentModel
import Foundation
@testable import LayoutAnalysis
import OCR
import Testing

private func line(_ text: String, x: Double = 0.05, y: Double, width: Double = 0.9,
                  height: Double = 0.017) -> TextLine
{
    TextLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

/// A page of three body lines whose text is unique to `index`, plus `extra`.
private func page(_ index: Int, extra: [TextLine] = []) -> RecognizedPage {
    RecognizedPage(lines: [
        line("body \(index) a", x: 0.08, y: 0.2, width: 0.87),
        line("body \(index) b", y: 0.22),
        line("body \(index) c", y: 0.24),
    ] + extra)
}

private func texts(_ blocks: [Block]) -> [String] {
    blocks.compactMap {
        switch $0 {
        case let .paragraph(content), let .heading(_, content): content.plainText
        default: nil
        }
    }
}

@Suite("Running headers, footers and page numbers")
struct RunningHeaderTests {
    private let analyzer = LayoutAnalyzer()

    @Test("a line repeated at the top of the pages is dropped")
    func repeatedHeader() {
        let pages = (1 ... 6).map { page($0, extra: [line("THE DOCUMENT TITLE", x: 0.3, y: 0.04, width: 0.4)]) }
        let found = texts(analyzer.blocks(from: pages))
        #expect(found.count == 6)
        #expect(!found.contains { $0.contains("TITLE") })
    }

    @Test("a header that alternates between two texts, with the page number beside it, is dropped")
    func alternatingHeaders() {
        let pages = (1 ... 8).map { index in
            let header = index.isMultiple(of: 2) ? "\(index) THE DOCUMENT TITLE" : "A CHAPTER NAME \(index)"
            return page(index, extra: [line(header, y: 0.04, width: 0.5)])
        }
        let found = texts(analyzer.blocks(from: pages))
        #expect(found.count == 8)
        #expect(!found.contains { $0.contains("TITLE") || $0.contains("CHAPTER") })
    }

    @Test("a repeated footer is dropped")
    func repeatedFooter() {
        let pages = (1 ... 5).map { page($0, extra: [line("www.example.org", x: 0.3, y: 0.95, width: 0.4)]) }
        #expect(!texts(analyzer.blocks(from: pages)).contains { $0.contains("example") })
    }

    @Test("a page number at the top, and one in Roman numerals at the bottom, are dropped")
    func numbersAtEitherEdge() {
        let top = (1 ... 5).map { page($0, extra: [line("\($0 + 10)", x: 0.48, y: 0.03, width: 0.04)]) }
        #expect(texts(analyzer.blocks(from: top)).count == 5)
        #expect(!texts(analyzer.blocks(from: top)).contains { $0.contains("1") && !$0.contains("body") })

        let numerals = ["iv", "v", "vi", "vii", "viii"]
        let bottom = numerals.enumerated().map { page(
            $0.offset,
            extra: [line($0.element, x: 0.48, y: 0.93, width: 0.04)]
        ) }
        #expect(texts(analyzer.blocks(from: bottom)).allSatisfy { $0.hasPrefix("body") })
    }

    @Test("text that appears once at the top, such as a chapter title, is kept")
    func uniqueTopLineIsKept() {
        var pages = (1 ... 5).map { page($0) }
        pages[2].lines.append(line("Chapter Three", x: 0.3, y: 0.05, width: 0.4, height: 0.035))
        #expect(texts(analyzer.blocks(from: pages)).contains("Chapter Three"))
    }

    @Test("a line repeated in the middle of the pages is kept")
    func repeatedBodyLineIsKept() {
        let pages = (1 ... 5).map { page($0, extra: [line("Yes.", y: 0.3, width: 0.1)]) }
        #expect(texts(analyzer.blocks(from: pages)).count(where: { $0.contains("Yes.") }) >= 1)
    }

    @Test("two pages are too few to tell a running header from text")
    func tooFewPages() {
        let pages = (1 ... 2).map { page($0, extra: [line("THE DOCUMENT TITLE", x: 0.3, y: 0.04, width: 0.4)]) }
        #expect(texts(analyzer.blocks(from: pages)).contains { $0.contains("TITLE") })
    }

    @Test("a repeated ornament without letters is kept")
    func ornamentIsKept() {
        let pages = (1 ... 5).map { page($0, extra: [line("* * *", x: 0.45, y: 0.05, width: 0.1)]) }
        #expect(texts(analyzer.blocks(from: pages)).contains { $0.contains("* * *") })
    }

    @Test("a footer is recognized whether the engine reads the spaces in it or not")
    func footerWithoutSpaces() {
        let pages = (1 ... 6).map { index in
            page(index, extra: [line(index == 3 ? "ANDYWEIR" : "ANDY WEIR", x: 0.4, y: 0.95, width: 0.2)])
        }
        #expect(!texts(analyzer.blocks(from: pages)).contains { $0.contains("ANDY") })
    }

    @Test("a footer at the bottom of scanned pages is dropped although its height and spacing vary")
    func scannedFooter() {
        // Each scanned leaf is cropped differently, so the footer drifts
        // up and down by more than the height tolerance, and the engine
        // reads the author's name with or without the space.
        let pages = (1 ... 8).map { index in
            let name = index == 4 ? "ANDYWEIR" : "ANDY WEIR"
            let footer = index.isMultiple(of: 2)
                ? line("\(index) \(name)", x: 0.13, y: 0.91 + 0.007 * Double(index), width: 0.2)
                : line("THE DOCUMENT \(index)", x: 0.68, y: 0.95, width: 0.2)
            return page(index, extra: [footer])
        }
        let found = texts(LayoutAnalyzer(options: .paperScan).blocks(from: pages))
        #expect(!found.contains { $0.contains("ANDY") || $0.contains("THE DOCUMENT") })
        #expect(found.count == 8)
    }

    @Test("a header at a different height on one page is kept there")
    func differentHeight() {
        var pages = (1 ... 6).map { page($0, extra: [line("THE DOCUMENT TITLE", x: 0.3, y: 0.04, width: 0.4)]) }
        pages[3].lines[3].box.origin.y = 0.08
        #expect(texts(analyzer.blocks(from: pages)).count(where: { $0.contains("TITLE") }) == 1)
    }
}
