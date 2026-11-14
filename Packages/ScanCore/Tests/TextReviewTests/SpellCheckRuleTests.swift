import Testing
import TextReview

/// A checker that knows a fixed vocabulary per language and records what it
/// was asked, so the tests need no system dictionary.
private final class FakeSpellChecker: SpellChecking, @unchecked Sendable {
    var known: [SpellLanguage: Set<String>] = [
        .ukrainian: ["слово", "документ", "читав", "він"],
        .english: ["word", "document", "the", "read", "and"],
    ]
    private(set) var asked: [(String, SpellLanguage)] = []

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
        #expect(detector.segments(of: "він читав the document слово") == [Segment(text: "він читав the document слово")])
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
}
