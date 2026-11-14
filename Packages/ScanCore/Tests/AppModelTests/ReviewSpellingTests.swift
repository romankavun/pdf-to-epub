import AppModel
import Conversion
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing
import TextReview

/// Knows only the words listed, so the tests need no system dictionary.
private struct FakeSpellChecker: SpellChecking {
    var known: Set<String>

    func isMisspelled(_ word: String, language _: SpellLanguage) -> Bool {
        !known.contains(word.lowercased())
    }
}

private let known: Set<String> = ["слово", "тут", "є", "and", "the", "text", "ось"]
private let detector = SuspiciousWordDetector(spellChecker: FakeSpellChecker(known: known))

private func conversion() -> Conversion {
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "C", blocks: [
            .paragraph(["Ось слово тут."]),
            .paragraph(["Ось докмент тут і wrod."]),
            .figure(Figure(imageID: "f", alternativeText: "", caption: ["the текст"])),
        ])],
        notes: [Note(id: "n", label: "1", content: ["Ось зламаноо слово."])]
    )
    let area = CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.1)
    return Conversion(
        document: document,
        pageURLs: [URL(fileURLWithPath: "/pages/1.png"), URL(fileURLWithPath: "/pages/2.png")],
        blockSources: [
            BlockSource(page: 0, box: area), BlockSource(page: 0, box: area.offsetBy(dx: 0, dy: 0.3)),
            BlockSource(page: 1, box: area),
        ],
        noteSources: [BlockSource(page: 1, box: area.offsetBy(dx: 0, dy: 0.3))]
    )
}

@MainActor
@Suite("Review with spell checking")
struct ReviewSpellingTests {
    @Test("misspelled words are flagged and counted with the other issues")
    func countsMisspellings() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        // "докмент", "wrod", the caption's "текст" and the note's "зламаноо".
        #expect(model.issueCount == 4)
        let second = model.pages[0].items[1]
        #expect(second.issueCount == 2)
        #expect(second.runs.compactMap(\.reason) == [.misspelled, .misspelled])
    }

    @Test("Next Issue walks through the misspelled words' blocks")
    func navigation() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        model.goToNextIssue()
        #expect(model.pageIndex == 0 && model.selectedItemID == .block(1))
        model.goToNextIssue()
        #expect(model.pageIndex == 1 && model.selectedItemID == .block(2))
        model.goToNextIssue()
        #expect(model.selectedItemID == .note("n"))
    }

    @Test("the summary counts suspicious words with the same detector")
    func summary() {
        let summary = ConversionSummary(conversion(), detector: detector)

        #expect(summary.suspiciousWords == 4)
        #expect(ConversionSummary(conversion()).suspiciousWords == 0)
    }
}
