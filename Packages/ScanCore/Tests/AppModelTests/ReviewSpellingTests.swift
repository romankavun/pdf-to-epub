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

    func suggestions(for word: String, language _: SpellLanguage) -> [String] {
        word == "докмент" ? ["документ"] : []
    }
}

private let known: Set<String> = ["слово", "тут", "є", "and", "the", "text", "ось", "документ"]
private let detector = SuspiciousWordDetector(spellChecker: FakeSpellChecker(known: known))

private func conversion() -> Conversion {
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "C", blocks: [
            .paragraph(["Ось слово тут."]),
            .paragraph(["Ось докмент тут і wrod."]),
            .figure(Figure(imageID: "f", alternativeText: "", caption: ["the текст"])),
            .paragraph(["Ось сл0во тут."]),
        ])],
        notes: [Note(id: "n", label: "1", content: ["Ось зламаноо слово."])]
    )
    let area = CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.1)
    return Conversion(
        document: document,
        pageURLs: [URL(fileURLWithPath: "/pages/1.png"), URL(fileURLWithPath: "/pages/2.png")],
        blockSources: [
            BlockSource(page: 0, box: area), BlockSource(page: 0, box: area.offsetBy(dx: 0, dy: 0.3)),
            BlockSource(page: 1, box: area), BlockSource(page: 1, box: area.offsetBy(dx: 0, dy: 0.5)),
        ],
        noteSources: [BlockSource(page: 1, box: area.offsetBy(dx: 0, dy: 0.3))]
    )
}

@MainActor
@Suite("Review with spell checking")
struct ReviewSpellingTests {
    @Test("misspelled words are counted apart from OCR suspects")
    func countsApart() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        // Only the digit in "сл0во" is an OCR suspect; the other four are spelling.
        #expect(model.issueCount == 1)
        #expect(model.misspellingCount == 4)
        let second = model.pages[0].items[1]
        #expect(second.issueCount == 0)
        #expect(second.misspellingCount == 2)
        #expect(second.runs.compactMap(\.reason) == [.misspelled, .misspelled])
    }

    @Test("Next Issue visits only OCR suspects")
    func issueNavigationIgnoresSpelling() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        #expect(model.flaggedItemCount == 1)
        model.goToNextIssue()
        #expect(model.selectedItemID == .block(3))
        model.goToNextIssue()
        #expect(model.selectedItemID == .block(3))
    }

    @Test("Next Misspelling walks through the misspelled blocks and wraps")
    func spellingNavigation() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        #expect(model.misspelledItemCount == 3)
        model.goToNextMisspelling()
        #expect(model.pageIndex == 0 && model.selectedItemID == .block(1))
        #expect(model.misspellingPosition == 1)
        model.goToNextMisspelling()
        #expect(model.selectedItemID == .block(2))
        model.goToNextMisspelling()
        #expect(model.selectedItemID == .note("n"))
        model.goToNextMisspelling()
        #expect(model.selectedItemID == .block(1))
        model.goToPreviousMisspelling()
        #expect(model.selectedItemID == .note("n"))
    }

    @Test("the summary counts the two kinds apart")
    func summary() {
        let summary = ConversionSummary(conversion(), detector: detector)

        #expect(summary.suspiciousWords == 1)
        #expect(summary.misspelledWords == 4)
        #expect(ConversionSummary(conversion()).misspelledWords == 0)
    }

    @Test("a flagged word offers suggestions and is replaced through a correction")
    func quickFix() throws {
        let model = ReviewModel(conversion: conversion(), detector: detector)
        let item = try #require(model.pages[0].items.first { $0.id == .block(1) })
        let index = try #require(item.runs.firstIndex { $0.text == "докмент" })

        #expect(model.suggestions(forRunAt: index, in: .block(1)) == ["документ"])
        model.replaceRun(at: index, in: .block(1), with: "документ")

        let fixed = try #require(model.pages[0].items.first { $0.id == .block(1) })
        #expect(fixed.runs.map(\.text).joined() == "Ось документ тут і wrod.")
        #expect(fixed.misspellingCount == 1)
        #expect(model.misspellingCount == 3)
        #expect(model.project.corrections.corrections.count == 1)
    }

    @Test("an OCR suspect is fixed the same way, and the fix is offered for the whole document")
    func quickFixOfSuspect() throws {
        var conversion = conversion()
        conversion.document.chapters[0].blocks.append(.paragraph(["Знову сл0во."]))
        conversion.blockSources.append(BlockSource(page: 1, box: CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.1)))
        let model = ReviewModel(conversion: conversion, detector: detector)
        let item = try #require(model.pages[1].items.first { $0.id == .block(3) })
        let index = try #require(item.runs.firstIndex { $0.reason == .digitInsideWord })

        #expect(model.suggestions(forRunAt: index, in: .block(3)) == ["слово"])
        model.replaceRun(at: index, in: .block(3), with: "слово")

        #expect(model.issueCount == 1)
        #expect(model.proposal != nil)
    }

    @Test("a run that is not flagged has no suggestions and is left alone")
    func unflaggedRun() {
        let model = ReviewModel(conversion: conversion(), detector: detector)

        #expect(model.suggestions(forRunAt: 0, in: .block(0)).isEmpty)
        model.replaceRun(at: 0, in: .block(0), with: "x")
        #expect(model.project.corrections.corrections.isEmpty)
    }

    @Test("ignoring a flagged word unflags it everywhere, in any case")
    func ignoreWord() throws {
        var conversion = conversion()
        conversion.document.chapters[0].blocks.append(.paragraph(["Докмент знову."]))
        conversion.blockSources.append(BlockSource(page: 1, box: CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.1)))
        let model = ReviewModel(conversion: conversion, detector: detector)
        let item = try #require(model.pages[0].items.first { $0.id == .block(1) })
        let index = try #require(item.runs.firstIndex { $0.text == "докмент" })
        #expect(model.misspellingCount == 6)

        model.ignoreWord(inRunAt: index, of: .block(1))

        // Both "докмент" and "Докмент" are gone; "wrod" and the others stay.
        #expect(model.misspellingCount == 4)
        #expect(model.pages[0].items.first { $0.id == .block(1) }?.misspellingCount == 1)
        #expect(model.project.corrections.corrections.isEmpty)
    }
}
