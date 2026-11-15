import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import OCR
import Testing
import TestSupport

extension Tag {
    /// Real Vision OCR: slow, and skipped by `scripts/check.sh`.
    @Tag static var realOCR: Self
}

/// A generated tidy document: pages drawn by code and the text that was drawn.
private struct DrawnDocument {
    var pages: [SyntheticPage]
    /// Every paragraph and heading as drawn, in reading order.
    var texts: [String]
}

private let vocabulary = [
    "river", "stone", "lantern", "winter", "orchard", "bridge", "morning", "harbour", "meadow", "violin",
    "garden", "candle", "silver", "forest", "window", "market",
]

/// Pages of plain English: a page of paragraphs, then a page that opens with a
/// heading. Lines are a fixed number of words so they fit the page width, and
/// every paragraph starts with an indent, which is how layout analysis tells
/// paragraphs apart.
private func drawDocument(_ random: inout SeededGenerator) -> DrawnDocument {
    func words(_ count: Int, _ random: inout SeededGenerator) -> String {
        (0 ..< count).map { _ in random.pick(vocabulary) }.joined(separator: " ")
    }
    func paragraph(_ random: inout SeededGenerator) -> (elements: [SyntheticPage.Element], text: String) {
        var lines: [String] = []
        for index in 0 ..< random.int(2 ... 3) {
            lines.append(words(index == 0 ? 9 : 8, &random))
        }
        var elements = [SyntheticPage.Element.line("> " + lines[0])]
        elements += lines.dropFirst().map { .line($0) }
        return (elements, lines.joined(separator: " "))
    }
    var texts: [String] = []
    var first: [SyntheticPage.Element] = []
    for _ in 0 ..< random.int(3 ... 5) {
        let made = paragraph(&random)
        first += made.elements
        texts.append(made.text)
    }
    first.append(.pageNumber("1"))
    let title = words(2, &random).capitalized
    var second: [SyntheticPage.Element] = [.heading(title), .gap(1)]
    texts.append(title)
    for _ in 0 ..< random.int(2 ... 3) {
        let made = paragraph(&random)
        second += made.elements
        texts.append(made.text)
    }
    second.append(.pageNumber("2"))
    return DrawnDocument(pages: [SyntheticPage(first), SyntheticPage(second)], texts: texts)
}

private extension Block {
    var canonicalText: String {
        switch self {
        case let .heading(_, content), let .paragraph(content): content.canonicalText
        case .figure: ""
        }
    }

    var type: BlockType? {
        switch self {
        case let .heading(level, _): .heading(level: level)
        case .paragraph: .paragraph
        case .figure: nil
        }
    }
}

/// What the user did in this case; kept to check it against the second run.
private struct Plan {
    var corrections = CorrectionSet()
    var retypes: [(anchor: BlockAnchor, type: BlockType)] = []
    var edits: [(anchor: BlockAnchor, text: String)] = []
}

/// Random corrections on distinct blocks of the first run: a retype, an
/// ignore, or a text edit, as a user makes them in the review.
private func randomPlan(for conversion: Conversion, _ random: inout SeededGenerator) -> Plan {
    var plan = Plan()
    let blocks = conversion.document.blocks
    guard blocks.count == conversion.blockSources.count else { return plan }
    for index in Array(blocks.indices).shuffled(using: &random).prefix(random.int(1 ... 3)) {
        let anchor = BlockAnchor(conversion.blockSources[index])
        let text = blocks[index].canonicalText
        switch random.int(0 ... 2) {
        case 0:
            let type: BlockType = switch blocks[index] {
            case .heading: .paragraph
            default: .heading(level: random.int(1 ... 3))
            }
            plan.corrections.setType(type, for: anchor)
            plan.retypes.append((anchor, type))
        case 1:
            plan.corrections.setType(.ignored, for: anchor)
            plan.retypes.append((anchor, .ignored))
        default:
            // A made-up word: the edited text cannot be mistaken for a
            // recognition result.
            let edited = text.isEmpty ? "zzedited" : "zzedited " + text
            plan.corrections.setText(from: text, to: edited, for: anchor)
            plan.edits.append((anchor, edited))
        }
    }
    return plan
}

@Suite("Invariants with real OCR", .tags(.realOCR), .serialized)
struct RealOCRInvariantTests {
    private func convert(_ urls: [URL]) async throws -> Conversion {
        let metadata = DocumentMetadata(identifier: "urn:uuid:property", title: "Property", author: nil, language: "en")
        return try await DocumentConverter(engine: VisionOCREngine()).analyze(pageURLs: urls, metadata: metadata)
    }

    /// The properties of the corrected document after the second run.
    private func verify(_ plan: Plan, before: CorrectedConversion, after: CorrectedConversion) throws {
        // Nothing is silently lost: every correction found its block again.
        try Property.require(
            after.unapplied.isEmpty,
            "\(after.unapplied.count) of \(plan.corrections.corrections.count) corrections not applied after the re-run"
        )
        // Retypes and ignores are in force.
        let blocks = after.conversion.document.blocks
        let sources = after.conversion.blockSources
        for (anchor, type) in plan.retypes {
            if type == .ignored {
                try Property.require(
                    after.ignored.contains { anchor.matches($0.source) },
                    "block ignored on the first run is not ignored after the re-run"
                )
            } else {
                let index = sources.firstIndex { anchor.matches($0) }
                try Property.require(
                    index.flatMap { blocks[$0].type } == type,
                    "retype to \(type) lost after the re-run"
                )
            }
        }
        // Text edits are in force.
        for (_, text) in plan.edits {
            try Property.require(
                blocks.contains { $0.canonicalText == text },
                "text edit '\(text)' lost after the re-run"
            )
        }
        // The corrected document is the same document after the re-run.
        try Property.requireEqual(
            blocks.map(\.canonicalText), before.conversion.document.blocks.map(\.canonicalText),
            "texts of the corrected document after the re-run"
        )
        try Property.requireEqual(
            blocks.map(\.type), before.conversion.document.blocks.map(\.type), "types of the corrected document"
        )
        try Property.requireEqual(after.ignored.count, before.ignored.count, "ignored blocks")
    }

    @Test(
        "corrections made on one real conversion survive a second real conversion",
        .timeLimit(.minutes(20))
    )
    func correctionsSurviveRerun() async {
        await Property.checkAsync("corrections survive a real re-run", cases: 3) { random in
            let drawn = drawDocument(&random)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let urls = try drawn.pages.enumerated().map { index, page in
                let url = folder.appendingPathComponent(String(format: "page_%03d.png", index + 1))
                try page.writePNG(to: url)
                return url
            }

            let first = try await convert(urls)
            let drawnText = drawn.texts.joined(separator: " ")
            let recognized = first.document.blocks.map(\.canonicalText).joined(separator: " ")
            try Property.require(
                TextSimilarity.matches(recognized, drawnText, threshold: 0.9),
                "recognized text is only \(TextSimilarity.ratio(recognized, drawnText)) like the drawn text"
            )

            let plan = randomPlan(for: first, &random)
            try Property.require(
                !plan.corrections.isEmpty,
                "no corrections were generated: \(first.document.blocks.count) blocks, \(first.blockSources.count) sources"
            )
            let before = plan.corrections.applying(to: first)
            let second = try await convert(urls)
            let secondText = second.document.blocks.map(\.canonicalText).joined(separator: " ")
            try Property.require(
                TextSimilarity.matches(secondText, drawnText, threshold: 0.9),
                "second run text is only \(TextSimilarity.ratio(secondText, drawnText)) like the drawn text"
            )
            let after = plan.corrections.applying(to: second)

            try verify(plan, before: before, after: after)
        }
    }
}
