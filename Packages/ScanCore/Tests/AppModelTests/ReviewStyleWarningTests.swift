@testable import AppModel
import Conversion
import DocumentModel
import Styles
import Testing
import TextReview

/// Knows only these words, so the tests need no system dictionary.
private struct VocabularyChecker: SpellChecking {
    static let known: Set<String> = ["the", "crew", "was", "ready", "and", "ship", "kept", "moving", "into", "night"]

    func isMisspelled(_ word: String, language _: SpellLanguage) -> Bool {
        !Self.known.contains(word.lowercased())
    }
}

private let detector = SuspiciousWordDetector(spellChecker: VocabularyChecker())

/// A word the vocabulary does not know, different for every `index`.
private func misread(_ index: Int, _ word: Int) -> String {
    let letters = Array("bcdfghjklmnpqrstvwxz")
    return "zq" + String(letters[index % letters.count]) + String(letters[(index / letters.count + word) % 20])
}

/// Four unknown words of thirteen judged, misread differently in each
/// paragraph: text probably misrecognized.
private func garbled(_ index: Int) -> String {
    "The crew was ready \((0 ..< 4).map { misread(index, $0) }.joined(separator: " ")) and the ship kept moving."
}

/// The same four unknown words in every paragraph, as an abbreviation or a
/// word in another language recurs: the dictionary lacks them, OCR read them right.
private func abbreviated(_: Int) -> String {
    "The crew was ready arkx sprx oppx fndx and the ship kept moving."
}

/// The styled conversion with each paragraph's text replaced by `text` of its index.
private func conversion(paragraphs text: (Int) -> String) -> Conversion {
    var conversion = styledConversion()
    let chapter = conversion.document.chapters[0]
    conversion.document.chapters[0].blocks = chapter.blocks.enumerated().map { index, block in
        if case .paragraph = block {
            return .paragraph([.text(text(index))])
        }
        return block
    }
    return conversion
}

@MainActor
@Suite("ReviewModel style warnings")
struct ReviewStyleWarningTests {
    private let storage = FakeStorage()

    private func paragraphs(in model: ReviewModel) throws -> Style {
        try #require(model.styles?.first { $0.type == .paragraph })
    }

    @Test("styles that look as expected have no warning")
    func ordinary() throws {
        let model = ReviewModel(project: ProjectModel(base: styledConversion(), storage: storage), detector: detector)
        #expect(try model.styles?.compactMap { model.warning(of: $0) } == [])
        #expect(try model.warning(of: paragraphs(in: model)) == nil)
    }

    @Test("a style whose recognized text is mostly misread is marked, with the dictionary the review uses")
    func misread() throws {
        let model = ReviewModel(
            project: ProjectModel(base: conversion(paragraphs: garbled), storage: storage), detector: detector
        )
        let style = try paragraphs(in: model)
        #expect(model.warning(of: style) == .mostlyMisrecognized(count: style.members.count))
    }

    @Test("unknown words that recur across the style's blocks are taken for real words the dictionary lacks")
    func recurringWords() throws {
        let model = ReviewModel(
            project: ProjectModel(base: conversion(paragraphs: abbreviated), storage: storage), detector: detector
        )
        #expect(try model.warning(of: paragraphs(in: model)) == nil)
    }

    @Test("without a dictionary nothing counts as misread")
    func noDictionary() throws {
        let model = ReviewModel(project: ProjectModel(base: conversion(paragraphs: garbled), storage: storage))
        #expect(try model.warning(of: paragraphs(in: model)) == nil)
    }
}
