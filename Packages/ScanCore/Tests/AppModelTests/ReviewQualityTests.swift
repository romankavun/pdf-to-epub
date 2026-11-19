@testable import AppModel
import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing
import TextReview

/// Knows only the words listed, in either language, so the tests need no
/// system dictionary.
private struct VocabularyChecker: SpellChecking {
    static let known: Set<String> = [
        "the", "crew", "was", "ready", "and", "ship", "kept", "moving", "into", "night", "part", "one",
        "тут", "була", "документ",
    ]

    func isMisspelled(_ word: String, language _: SpellLanguage) -> Bool {
        !Self.known.contains(word.lowercased())
    }
}

private let detector = SuspiciousWordDetector(spellChecker: VocabularyChecker())

/// Four unknown words of twelve judged: a third, well above the rule's fifth.
private let garbled = "The crcw was rcady and the shlp kept moving into thc night."
private let clean = "The crew was ready and the ship kept moving into the night."

private func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

/// Text in the middle of each scan, as on a paper scan with wide margins:
/// the text area is x 0.3 to 0.7, y 0.3 to about 0.65.
///
/// - page 0: a heading and a garbled paragraph;
/// - page 1: a clean paragraph;
/// - page 2: nothing but an uncaptioned figure over the text area;
/// - page 3: a paragraph with an OCR suspect, and a captioned figure;
/// - page 4: nothing but a small uncaptioned figure.
private func conversion(language: String = "en", paragraph: String = garbled) -> Conversion {
    let blocks: [Block] = [
        .heading(level: 1, content: ["Part one"]),
        .paragraph([.text(paragraph)]),
        .paragraph([.text(clean)]),
        .figure(Figure(imageID: "lost", alternativeText: "", caption: [])),
        .paragraph(["The B6y was ready."]),
        .figure(Figure(imageID: "plate", alternativeText: "", caption: ["Figure one"])),
        .figure(Figure(imageID: "small", alternativeText: "", caption: [])),
    ]
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: language),
        chapters: [Chapter(title: "C", blocks: blocks)]
    )
    return Conversion(
        document: document,
        pageURLs: (1 ... 5).map { URL(fileURLWithPath: "/pages/\($0).png") },
        blockSources: [
            BlockSource(page: 0, box: box(0.3, 0.3, 0.4, 0.02)),
            BlockSource(page: 0, box: box(0.3, 0.35, 0.4, 0.3)),
            BlockSource(page: 1, box: box(0.3, 0.3, 0.4, 0.4)),
            BlockSource(page: 2, box: box(0.32, 0.32, 0.36, 0.32)),
            BlockSource(page: 3, box: box(0.3, 0.3, 0.4, 0.2)),
            BlockSource(page: 3, box: box(0.3, 0.52, 0.4, 0.15)),
            BlockSource(page: 4, box: box(0.4, 0.4, 0.15, 0.15)),
        ]
    )
}

@MainActor
@Suite("Review of OCR quality")
struct ReviewQualityTests {
    @Test("the issue counter counts the page being viewed, garbled text and lost text included")
    func counterFollowsThePage() {
        // Reproduces a paper scan whose text came out garbled: the toolbar
        // showed the document's one OCR-suspect word on every page and nothing
        // about the garbled blocks or the pages that lost their text.
        let model = ReviewModel(conversion: conversion(), detector: detector)

        #expect(model.issueCount == 1)
        #expect(model.flaggedItemCount == 3)
        var counts: [Int] = []
        for index in model.pages.indices {
            model.goToPage(index)
            counts.append(model.issueCountOnPage)
        }
        #expect(counts == [1, 0, 1, 1, 0])
    }

    @Test("a block with a large share of unknown words is probably misrecognized")
    func garbledBlock() throws {
        let model = ReviewModel(conversion: conversion(), detector: detector)
        let page = model.pages[0]
        let heading = try #require(page.items.first { $0.id == .block(0) })
        let paragraph = try #require(page.items.first { $0.id == .block(1) })

        #expect(paragraph.spelling == SuspiciousWordDetector.SpellingTally(checked: 12, misspelled: 4))
        #expect(paragraph.isProbablyMisrecognized)
        #expect(paragraph.outline == .unreliable)
        #expect(!heading.isProbablyMisrecognized)
        #expect(heading.outline == .plain)
        #expect(model.pages[1].items.allSatisfy { !$0.isProbablyMisrecognized })
    }

    @Test("Next Issue stops at garbled text and at a page that lost its text, in page order")
    func navigation() {
        let model = ReviewModel(conversion: conversion(), detector: detector)
        var visited: [ReviewModel.ItemID?] = []
        for _ in 0 ..< 4 {
            model.goToNextIssue()
            visited.append(model.selectedItemID)
        }
        #expect(visited == [.block(1), .block(3), .block(4), .block(1)])
    }

    @Test("a page with nothing but an uncaptioned figure over the text area may hide text")
    func lostText() throws {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        #expect(model.pages.map(\.mayHideText) == [false, false, true, false, false])
        let lost = try #require(model.pages[2].items.first)
        #expect(lost.mayHideText)
        #expect(lost.outline == .unreliable)
        #expect(model.pages[3].items.allSatisfy { !$0.mayHideText })
        #expect(model.pages[4].items.allSatisfy { !$0.mayHideText })
    }

    @Test("only words in the document's language count: foreign fragments are unknown by nature")
    func documentLanguage() throws {
        let model = ReviewModel(conversion: conversion(language: "uk"), detector: detector)
        let paragraph = try #require(model.pages[0].items.first { $0.id == .block(1) })

        #expect(!paragraph.isProbablyMisrecognized)
        #expect(model.flaggedItemCount == 2)
    }

    @Test("ignoring unknown words can bring a block under the threshold")
    func ignoredWords() throws {
        let model = ReviewModel(conversion: conversion(), detector: detector)
        let paragraph = try #require(model.pages[0].items.first { $0.id == .block(1) })
        let unknown = paragraph.runs.indices.filter { paragraph.runs[$0].reason == .misspelled }
        model.ignoreWord(inRunAt: unknown[0], of: .block(1))
        model.ignoreWord(inRunAt: unknown[1], of: .block(1))

        let after = try #require(model.pages[0].items.first { $0.id == .block(1) })
        #expect(after.spelling == SuspiciousWordDetector.SpellingTally(checked: 12, misspelled: 2))
        #expect(!after.isProbablyMisrecognized)
    }

    @Test("without a dictionary no text is taken for misrecognized")
    func noDictionary() {
        let model = ReviewModel(conversion: conversion())

        #expect(model.pages.allSatisfy { $0.items.allSatisfy { !$0.isProbablyMisrecognized } })
        #expect(model.flaggedItemCount == 2)
    }

    @Test("an ignored figure is no longer a lost-text stop")
    func ignoredFigure() {
        let model = ReviewModel(conversion: conversion(), detector: detector)
        model.select(itemID: .block(3))
        model.setSelectedType(.ignored)

        #expect(!model.pages[2].mayHideText)
        #expect(model.flaggedItemCount == 2)
    }

    @Test("the summary counts misrecognized blocks and pages that may hide text")
    func summary() {
        let summary = ConversionSummary(conversion(), detector: detector)

        #expect(summary.suspiciousWords == 1)
        #expect(summary.misrecognizedBlocks == 1)
        #expect(summary.pagesThatMayHideText == 1)
        #expect(ConversionSummary(conversion(paragraph: clean), detector: detector).misrecognizedBlocks == 0)
    }

    @Test("the lost-text check needs no detector")
    func summaryWithoutDetector() {
        #expect(ConversionSummary(conversion()).pagesThatMayHideText == 1)
    }
}
