@testable import EPUBExport
import Testing

@Suite("XML escaping")
struct XMLEscapingTests {
    @Test("escapes markup characters")
    func markup() {
        #expect("a < b & \"c\" > d".xmlEscaped == "a &lt; b &amp; &quot;c&quot; &gt; d")
    }

    @Test("drops characters that XML 1.0 does not allow, which OCR occasionally produces")
    func invalidCharacters() {
        #expect("a\u{FFFE}b\u{FFFF}c\u{0}d\u{1B}e".xmlEscaped == "abcde")
    }

    @Test("keeps tabs, line breaks and characters outside the basic plane")
    func validCharacters() {
        #expect("a\tb\nc\u{1F600}ї".xmlEscaped == "a\tb\nc\u{1F600}ї")
    }
}
