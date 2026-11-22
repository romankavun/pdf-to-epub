import CoreGraphics
import DocumentModel
import Foundation
@testable import LayoutAnalysis
import OCR
import Testing
import TestSupport

/// How many times each letter occurs. Hyphens, spaces and digits are left
/// out: joining may add a space or keep a hyphen, and a page number is
/// removed on purpose, but no letter may appear or disappear.
private func letters(_ text: String) -> [Character: Int] {
    text.filter(\.isLetter).reduce(into: [:]) { counts, character in counts[character, default: 0] += 1 }
}

private func text(of block: Block) -> String {
    switch block {
    case let .heading(_, content), let .paragraph(content): content.plainText
    case let .figure(figure): figure.caption.plainText
    }
}

private func lineTexts(_ generator: DocumentGenerator, _ random: inout SeededGenerator) -> [String] {
    (0 ..< random.int(1 ... 12)).map { _ in
        var line = generator.words(&random, count: 1 ... 6)
        if random.chance(0.3) {
            line += random.pick(["-", "‐", "—", "- "])
        }
        if random.chance(0.15) {
            line = "-" + line
        }
        return line
    }
}

@Suite("Joining invariants")
struct JoiningInvariantTests {
    private let generator = DocumentGenerator(text: .tidy)

    @Test("appending lines to a draft never loses or invents a letter")
    func draftKeepsLetters() {
        Property.check("draft letters", cases: 300) { random in
            var draft = Draft(headingStyle: nil)
            let lines = lineTexts(generator, &random)
            for (index, line) in lines.enumerated() {
                draft.append(
                    [.text(line)],
                    page: 0,
                    box: CGRect(x: 0.05, y: 0.1 + Double(index) * 0.02, width: 0.9, height: 0.017)
                )
            }
            try Property.requireEqual(letters(draft.text), letters(lines.joined()), "letters of \(lines)")
        }
    }

    @Test("on scanned pages a line-end hyphen before a lowercase letter goes and every letter stays")
    func softHyphenBreaks() {
        Property.check("soft hyphen breaks", cases: 300) { random in
            var draft = Draft(headingStyle: nil)
            let first = generator.words(&random, count: 1 ... 3) + "-"
            let second = generator.words(&random, count: 1 ... 3)
            draft.append([.text(first)], page: 0, box: CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.017))
            draft.append(
                [.text(second)], page: 0, box: CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.017),
                removesSoftHyphens: true
            )
            let joined = draft.text
            let expected = first.dropLast().last?.isLetter == true
                ? (second.first?.isLowercase == true ? first.dropLast() + second : first + second)
                : first + " " + second
            try Property.requireEqual(
                joined, expected, "joining of \(first.debugDescription) and \(second.debugDescription)"
            )
        }
    }

    @Test("a hyphen kept at a line break is only a hyphen: joining never glues in or drops a letter next to it")
    func hyphenBreaks() {
        Property.check("hyphen breaks", cases: 300) { random in
            var draft = Draft(headingStyle: nil)
            let first = generator.words(&random, count: 1 ... 3) + "-"
            let second = generator.words(&random, count: 1 ... 3)
            draft.append([.text(first)], page: 0, box: CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.017))
            draft.append([.text(second)], page: 0, box: CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.017))
            let joined = draft.text
            try Property.require(
                joined == first + second || joined == first + " " + second,
                "unexpected joining of \(first.debugDescription) and \(second.debugDescription): \(joined.debugDescription)"
            )
        }
    }

    @Test(
        "a whole page of generated lines comes out with exactly the letters it went in with",
        arguments: [("clean pages", LayoutAnalyzer.Options()), ("scanned pages", .scannedPage)]
    )
    func analyzerKeepsLetters(kind: String, options: LayoutAnalyzer.Options) {
        let analyzer = LayoutAnalyzer(options: options)
        Property.check("analyzer letters (\(kind))", cases: 150) { random in
            var input = ""
            var pages: [RecognizedPage] = []
            for _ in 0 ..< random.int(1 ... 4) {
                var lines: [TextLine] = []
                var top = 0.15
                for line in lineTexts(generator, &random) {
                    // Words are drawn from a fixed vocabulary, so a line may
                    // repeat on several pages; running header removal then
                    // legitimately drops it. A counter keeps lines distinct.
                    let unique = line + " " + String(UnicodeScalar(UInt8(97 + (input.count % 26))))
                    input += unique
                    let indented = random.chance(0.3)
                    lines.append(TextLine(
                        text: unique,
                        box: CGRect(
                            x: indented ? 0.08 : 0.05,
                            y: top,
                            width: 0.8,
                            height: random.chance(0.1) ? 0.03 : 0.017
                        )
                    ))
                    top += random.chance(0.15) ? 0.05 : 0.02
                }
                pages.append(RecognizedPage(lines: lines))
            }
            let output = analyzer.blocks(from: pages).map(text(of:)).joined()
            try Property.requireEqual(letters(output), letters(input), "letters of the document")
        }
    }
}
