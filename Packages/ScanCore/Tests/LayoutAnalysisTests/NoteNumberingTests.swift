@testable import LayoutAnalysis
import Testing

@Suite("NoteNumbering")
struct NoteNumberingTests {
    private func labels(_ raw: [String], after previous: NoteNumbering.Position? = nil) -> [String] {
        NoteNumbering.labels(for: raw, after: previous).labels
    }

    @Test("keeps a clean run of numbers")
    func clean() {
        #expect(labels(["1", "2", "3"]) == ["1", "2", "3"])
        #expect(labels(["228", "229", "230"]) == ["228", "229", "230"])
    }

    @Test("repairs look-alike characters and fills unread labels from the sequence")
    func repairsNumbers() {
        #expect(labels(["9", "I0", "", "I2"]) == ["9", "10", "11", "12"])
        #expect(labels(["I3", "14", "15", "16", "", "18", "19", "20", "2I"])
            == ["13", "14", "15", "16", "17", "18", "19", "20", "21"])
    }

    @Test("a label that breaks the sequence without a majority against it is kept as read")
    func outOfSequence() {
        #expect(labels(["27", "28", "29", "9", "30", "ЗІ", "32"]) == ["27", "28", "29", "9", "30", "31", "32"])
    }

    @Test("gives the value of a single label in a known kind of numbering")
    func singleValue() {
        #expect(NoteNumbering.value(of: "I4", as: .arabic) == 14)
        #expect(NoteNumbering.value(of: "II", as: .arabic) == 11)
        #expect(NoteNumbering.value(of: "П", as: .roman) == 2)
        #expect(NoteNumbering.value(of: "c", as: .letter) == 3)
        #expect(NoteNumbering.value(of: "", as: .arabic) == nil)
        #expect(NoteNumbering.value(of: "IV", as: .letter) == nil)
    }

    @Test("reports the kind and values behind the labels")
    func kindAndValues() {
        let run = NoteNumbering.labels(for: ["b", ""], after: nil)
        #expect(run.kind == .letter)
        #expect(run.values == [2, 3])
    }

    @Test("a number misread as a roman numeral follows its neighbours")
    func romanLookingNumber() {
        #expect(labels(["8", "9", "10", "II", "12"]) == ["8", "9", "10", "11", "12"])
    }

    @Test("recognizes roman numerals, also in Cyrillic look-alikes")
    func roman() {
        #expect(labels(["I", "II", "III", "IV", "V"]) == ["I", "II", "III", "IV", "V"])
        #expect(labels(["", "II", "III", "IV", "V"]) == ["I", "II", "III", "IV", "V"])
        #expect(labels(["І", "П"]) == ["I", "II"])
        #expect(labels(["XIX", "", "XXI"]) == ["XIX", "XX", "XXI"])
    }

    @Test("recognizes letters")
    func letters() {
        #expect(labels(["a", "b", "c"]) == ["a", "b", "c"])
        #expect(labels(["b", ""]) == ["b", "c"])
    }

    @Test("an unreadable run continues the numbering of the run before it")
    func continues() {
        let roman = NoteNumbering.Position(kind: .roman, value: 5)
        #expect(labels([""], after: roman) == ["VI"])
        #expect(labels(["", ""], after: NoteNumbering.Position(kind: .letter, value: 1)) == ["b", "c"])
        #expect(labels(["", "", ""], after: NoteNumbering.Position(kind: .arabic, value: 41)) == ["42", "43", "44"])
    }

    @Test("with nothing to go by, numbering starts at 1")
    func nothingKnown() {
        #expect(labels(["", ""]) == ["1", "2"])
        #expect(labels([]).isEmpty)
    }

    @Test("reports where the run ended, for the next run to continue from")
    func lastPosition() {
        #expect(NoteNumbering.labels(for: ["I", "II"], after: nil).last == .init(kind: .roman, value: 2))
        #expect(NoteNumbering.labels(for: [], after: .init(kind: .arabic, value: 7)).last
            == .init(kind: .arabic, value: 7))
    }

    @Test("numbering that restarts inside a run is kept as read, with gaps filled")
    func restarts() {
        #expect(labels(["29", "30", "1", "", "3"]) == ["29", "30", "1", "2", "3"])
    }

    @Test("punctuation and spaces around a label are ignored")
    func punctuation() {
        #expect(labels(["1.", " 2 ", "3)"]) == ["1", "2", "3"])
    }
}
