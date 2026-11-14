import Conversion
import Corrections
import DocumentModel
import Testing

@Suite("Word replacement")
struct WordReplacementTests {
    @Test("finds the one word that an edit changed")
    func singleChange() {
        let change = WordReplacement.singleWordChange(from: "He read Журавeль, aloud.", to: "He read Журавель, aloud.")
        #expect(change?.old == "Журавeль")
        #expect(change?.new == "Журавель")
    }

    @Test("an edit that changes more than one word, or the words around them, is not a word replacement")
    func notSingle() {
        #expect(WordReplacement.singleWordChange(from: "a b c", to: "a x y") == nil)
        #expect(WordReplacement.singleWordChange(from: "a b", to: "a b c") == nil)
        #expect(WordReplacement.singleWordChange(from: "a, b", to: "a; b") == nil)
        #expect(WordReplacement.singleWordChange(from: "same", to: "same") == nil)
        #expect(WordReplacement.singleWordChange(from: "a b", to: "a  b") == nil)
    }

    @Test("a note reference between words stays out of the way")
    func withReference() {
        let change = WordReplacement.singleWordChange(from: "teh\u{FFFC} end", to: "the\u{FFFC} end")
        #expect(change?.old == "teh" && change?.new == "the")
    }

    @Test("counts whole-word occurrences in blocks and notes")
    func occurrences() {
        let document = Document(
            metadata: DocumentMetadata(identifier: "x", title: "T", author: nil, language: "uk"),
            chapters: [Chapter(title: "T", blocks: [
                .paragraph(["teh cat and teh dog, ", .emphasis("teh"), " tehran"]),
                .figure(Figure(imageID: "f", alternativeText: "", caption: ["teh end"])),
            ])],
            notes: [Note(id: "n", label: "1", content: ["no teh"])]
        )
        #expect(WordReplacement.occurrences(of: "teh", in: Conversion(document: document)) == 5)
        #expect(WordReplacement.occurrences(of: "", in: Conversion(document: document)) == 0)
    }
}
