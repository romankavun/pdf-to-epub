import Testing
import TextReview

/// A checker that knows a fixed vocabulary per language and records what it
/// was asked, so the tests need no system dictionary.
private final class FakeSpellChecker: SpellChecking, @unchecked Sendable {
    var known: [SpellLanguage: Set<String>] = [
        .ukrainian: ["слово", "документ", "читав", "він"],
        .english: ["word", "document", "the", "read", "and"],
    ]
    var guesses: [String: [String]] = ["докмент": ["документ", "докумет"], "wrod": ["word"]]
    private(set) var asked: [(String, SpellLanguage)] = []

    func suggestions(for word: String, language _: SpellLanguage) -> [String] {
        guesses[word] ?? []
    }

    func isMisspelled(_ word: String, language: SpellLanguage) -> Bool {
        asked.append((word, language))
        return !(known[language]?.contains(word.lowercased()) ?? false)
    }
}

private typealias Segment = SuspiciousWordDetector.Segment

@Suite("Spell-check rule")
struct SpellCheckRuleTests {
    private let checker = FakeSpellChecker()
    private var detector: SuspiciousWordDetector {
        SuspiciousWordDetector(spellChecker: checker)
    }

    @Test("a Cyrillic word is checked as Ukrainian and a Latin one as English")
    func languagePerWord() {
        #expect(detector
            .segments(of: "він читав the document слово") == [Segment(text: "він читав the document слово")])
        #expect(checker.asked.contains { $0 == ("він", .ukrainian) })
        #expect(checker.asked.contains { $0 == ("document", .english) })
    }

    @Test("an unknown word is flagged as misspelled, in either language")
    func flagsUnknown() {
        #expect(detector.segments(of: "Він читав докмент and wrod.") == [
            Segment(text: "Він читав "),
            Segment(text: "докмент", reason: .misspelled),
            Segment(text: " and "),
            Segment(text: "wrod", reason: .misspelled),
            Segment(text: "."),
        ])
    }

    @Test("a capitalized word inside a sentence is taken for a name")
    func namesAreSkipped() {
        #expect(detector.segments(of: "він читав Коваленка і Kafka") == [
            Segment(text: "він читав Коваленка і Kafka"),
        ])
        // At the start of a sentence a capital means nothing, so it is checked.
        #expect(detector.segments(of: "Докмент. Wrod")
            == [
                Segment(text: "Докмент", reason: .misspelled),
                Segment(text: ". "),
                Segment(text: "Wrod", reason: .misspelled),
            ])
    }

    @Test("all-capital words, one- and two-letter words are not checked")
    func shortAndAcronyms() {
        #expect(detector.segments(of: "він NASA хв xy") == [Segment(text: "він NASA хв xy")])
    }

    @Test("a word the other rules flag is not asked about again")
    func otherRulesFirst() {
        let segments = detector.segments(of: "сл0во Журавeль")
        #expect(segments.compactMap(\.reason) == [.digitInsideWord, .mixedScript])
        #expect(checker.asked.isEmpty)
    }

    @Test("without a checker the rule is off")
    func noChecker() {
        #expect(SuspiciousWordDetector().segments(of: "він докмент") == [Segment(text: "він докмент")])
    }

    @Test("an apostrophe stays inside the checked word")
    func apostrophe() {
        _ = detector.segments(of: "він п'ять")
        #expect(checker.asked.contains { $0 == ("п'ять", .ukrainian) })
    }

    @Test("only the dictionary-free reasons are OCR suspects")
    func ocrSuspects() {
        #expect(SuspiciousWordDetector.Reason.mixedScript.isOCRSuspect)
        #expect(SuspiciousWordDetector.Reason.digitInsideWord.isOCRSuspect)
        #expect(!SuspiciousWordDetector.Reason.misspelled.isOCRSuspect)
    }

    @Test("counts OCR suspects and misspellings apart")
    func countsApart() {
        let text = "він докмент сл0во"
        #expect(detector.suspiciousWordCount(in: text) == 1)
        #expect(detector.misspelledWordCount(in: text) == 1)
    }

    @Test("a misspelled word gets the dictionary's guesses")
    func misspelledSuggestions() {
        #expect(detector.suggestions(for: "докмент", reason: .misspelled) == ["документ", "докумет"])
        #expect(detector.suggestions(for: "wrod", reason: .misspelled) == ["word"])
        #expect(detector.suggestions(for: "xyzzy", reason: .misspelled).isEmpty)
    }

    @Test("a look-alike letter from the wrong alphabet is turned into the word's own")
    func mixedScriptSuggestion() {
        // Latin "o" in a Cyrillic word, and Cyrillic "о" in a Latin one.
        #expect(detector.suggestions(for: "Журавeль", reason: .mixedScript) == ["Журавель"])
        #expect(detector.suggestions(for: "dоcuments", reason: .mixedScript) == ["documents"])
    }

    @Test("a digit that looks like a letter is turned into it")
    func digitSuggestion() {
        #expect(detector.suggestions(for: "сл0во", reason: .digitInsideWord) == ["слово"])
        #expect(detector.suggestions(for: "d0cument", reason: .digitInsideWord) == ["document"])
        // A digit with no look-alike letter offers nothing.
        #expect(detector.suggestions(for: "сл7во", reason: .digitInsideWord).isEmpty)
    }

    @Test("without a checker the look-alike fixes still work")
    func suggestionsWithoutChecker() {
        #expect(SuspiciousWordDetector().suggestions(for: "сл0во", reason: .digitInsideWord) == ["слово"])
        #expect(SuspiciousWordDetector().suggestions(for: "докмент", reason: .misspelled).isEmpty)
    }
}
