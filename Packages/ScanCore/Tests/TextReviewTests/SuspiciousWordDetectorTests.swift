import Testing
import TextReview

private typealias Segment = SuspiciousWordDetector.Segment

@Suite("SuspiciousWordDetector")
struct SuspiciousWordDetectorTests {
    private let detector = SuspiciousWordDetector()

    @Test("ordinary text in either language is one unmarked segment")
    func cleanText() {
        let text = "Звичайний текст, plain text — 1990."
        #expect(detector.segments(of: text) == [Segment(text: text)])
        #expect(detector.segments(of: "").isEmpty)
    }

    @Test("a word mixing Latin and Cyrillic letters is suspicious")
    func mixedScript() {
        // The "o" is Latin: a classic look-alike substitution.
        #expect(detector.segments(of: "Він читав Журавeль уголос.") == [
            Segment(text: "Він читав "),
            Segment(text: "Журавeль", reason: .mixedScript),
            Segment(text: " уголос."),
        ])
    }

    @Test("a digit between letters is suspicious")
    func digitInsideWord() {
        #expect(detector.segments(of: "сл0во and b1ue") == [
            Segment(text: "сл0во", reason: .digitInsideWord),
            Segment(text: " and "),
            Segment(text: "b1ue", reason: .digitInsideWord),
        ])
    }

    @Test("digits at the edge of a word or beside a hyphen are normal")
    func legitimateDigits() {
        let text = "У 1990-х, 3D, 2nd, Т-34 і A4."
        #expect(detector.segments(of: text) == [Segment(text: text)])
    }

    @Test("an apostrophe inside a word does not split it")
    func apostrophes() {
        let text = "п'ять об’єктів, don't"
        #expect(detector.segments(of: text) == [Segment(text: text)])
        #expect(detector.segments(of: "об’єkт") == [Segment(text: "об’єkт", reason: .mixedScript)])
    }

    @Test("mixed script wins when a word breaks both rules")
    func precedence() {
        #expect(detector.segments(of: "сл0вo") == [Segment(text: "сл0вo", reason: .mixedScript)])
    }

    @Test("counts the suspicious words of a text")
    func count() {
        #expect(detector.suspiciousWordCount(in: "Журавeль, сл0во і слово") == 2)
    }
}
