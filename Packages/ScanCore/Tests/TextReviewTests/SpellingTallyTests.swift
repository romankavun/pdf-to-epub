import Testing
import TextReview

/// Knows a fixed vocabulary per language, so the tests need no system
/// dictionary.
private struct VocabularyChecker: SpellChecking {
    var known: [SpellLanguage: Set<String>] = [
        .english: ["the", "document", "was", "read", "and", "kept", "word"],
        .ukrainian: ["документ", "слово", "тут", "була"],
    ]

    func isMisspelled(_ word: String, language: SpellLanguage) -> Bool {
        !(known[language]?.contains(word.lowercased()) ?? false)
    }
}

private typealias Tally = SuspiciousWordDetector.SpellingTally

@Suite("Spelling tally and the misrecognized-text rule")
struct SpellingTallyTests {
    private let detector = SuspiciousWordDetector(spellChecker: VocabularyChecker())

    @Test("counts the words the spelling rule judges and the ones it flags")
    func countsJudgedWords() {
        // "a" is too short and "Mark" is taken for a name: neither is judged.
        let tally = detector.spellingTally(of: "The document was rcad by Mark and kcpt.")
        #expect(tally == Tally(checked: 6, misspelled: 2))
    }

    @Test("counts only the words of the given language")
    func onlyOneLanguage() {
        let text = "Документ тут була, the bok"
        #expect(detector.spellingTally(of: text, in: .ukrainian) == Tally(checked: 3, misspelled: 0))
        #expect(detector.spellingTally(of: text, in: .english) == Tally(checked: 2, misspelled: 1))
        #expect(detector.spellingTally(of: text) == Tally(checked: 5, misspelled: 1))
    }

    @Test("an ignored word is judged but not counted as misspelled")
    func ignoredWords() {
        let tally = detector.spellingTally(of: "the bok and the Bok", ignoring: ["bok"])
        #expect(tally == Tally(checked: 4, misspelled: 0))
    }

    @Test("without a dictionary nothing is judged")
    func noDictionary() {
        #expect(SuspiciousWordDetector().spellingTally(of: "the bok was rcad") == Tally(checked: 0, misspelled: 0))
    }

    @Test("tallies add up")
    func adding() {
        #expect(Tally(checked: 3, misspelled: 1) + Tally(checked: 5, misspelled: 2) == Tally(checked: 8, misspelled: 3))
    }

    @Test(
        "text is probably misrecognized above a fifth of unknown words among at least eight judged",
        arguments: [
            (Tally(checked: 10, misspelled: 3), true),
            (Tally(checked: 10, misspelled: 2), false), // exactly a fifth
            (Tally(checked: 8, misspelled: 2), true),
            (Tally(checked: 7, misspelled: 7), false), // too few words to judge
            (Tally(checked: 0, misspelled: 0), false),
        ]
    )
    func misrecognizedRule(tally: SuspiciousWordDetector.SpellingTally, expected: Bool) {
        #expect(tally.isProbablyMisrecognized == expected)
    }

    @Test("a language code names the dictionary the document is checked with")
    func languageCodes() {
        #expect(SpellLanguage(languageCode: "en") == .english)
        #expect(SpellLanguage(languageCode: "en-GB") == .english)
        #expect(SpellLanguage(languageCode: "uk") == .ukrainian)
        #expect(SpellLanguage(languageCode: "uk_UA") == .ukrainian)
        #expect(SpellLanguage(languageCode: "de") == nil)
    }
}
