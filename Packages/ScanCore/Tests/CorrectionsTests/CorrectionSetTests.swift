import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing

func box(_ y: Double, height: Double = 0.1) -> CGRect {
    CGRect(x: 0.05, y: y, width: 0.9, height: height)
}

/// Page 0: a heading and a paragraph with a note; page 1: a paragraph with
/// a misread word, a figure, and a paragraph that repeats the misread word.
func sampleConversion() -> Conversion {
    let blocks: [Block] = [
        .heading(level: 1, content: ["Chapter"]),
        .paragraph(["Clean text", .noteReference("note-1"), " goes on."]),
        .paragraph(["He read ", .emphasis("Журавeль"), " aloud."]),
        .figure(Figure(imageID: "figure-001", alternativeText: "", caption: ["Fig. 1"])),
        .paragraph(["Журавeль again, and Журавeльем too."]),
    ]
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "Chapter", blocks: blocks)],
        notes: [Note(id: "note-1", label: "7", content: ["Note about Журавeль."])]
    )
    return Conversion(
        document: document,
        pageURLs: [URL(fileURLWithPath: "/p/0.png"), URL(fileURLWithPath: "/p/1.png")],
        blockSources: [
            BlockSource(page: 0, box: box(0.1)), BlockSource(page: 0, box: box(0.3)),
            BlockSource(page: 1, box: box(0.1)), BlockSource(page: 1, box: box(0.3)),
            BlockSource(page: 1, box: box(0.5)),
        ],
        noteSources: [BlockSource(page: 1, box: box(0.8))]
    )
}

func anchor(_ page: Int, _ y: Double) -> BlockAnchor {
    BlockAnchor(page: page, box: box(y))
}

@Suite("CorrectionSet")
struct CorrectionSetTests {
    private let base = sampleConversion()

    @Test("without corrections the conversion comes back unchanged")
    func identity() {
        let result = CorrectionSet().applying(to: base)
        #expect(result.conversion == base)
        #expect(result.ignored.isEmpty)
        #expect(result.unapplied.isEmpty)
    }

    @Test("a paragraph made a level 1 heading starts a new chapter")
    func retypeToHeading() {
        var set = CorrectionSet()
        set.setType(.heading(level: 1), for: anchor(1, 0.1))
        let result = set.applying(to: base).conversion
        #expect(result.document.blocks[2] == .heading(level: 1, content: ["He read ", .emphasis("Журавeль"), " aloud."]))
        #expect(result.document.chapters.map(\.title) == ["Chapter", "He read Журавeль aloud."])
        #expect(result.blockSources == base.blockSources)
    }

    @Test("a heading made a paragraph keeps its text")
    func retypeToParagraph() {
        var set = CorrectionSet()
        set.setType(.paragraph, for: anchor(0, 0.1))
        let result = set.applying(to: base).conversion
        #expect(result.document.blocks[0] == .paragraph(["Chapter"]))
        #expect(result.document.chapters.map(\.title) == ["T"])
    }

    @Test("an ignored block leaves the document and is reported with its source")
    func ignore() {
        var set = CorrectionSet()
        set.setType(.ignored, for: anchor(1, 0.3))
        let result = set.applying(to: base)
        #expect(result.conversion.document.blocks.count == 4)
        #expect(result.conversion.blockSources.count == 4)
        #expect(result.ignored.map(\.source) == [base.blockSources[3]])
        #expect(result.ignored.map(\.block) == [base.document.blocks[3]])
    }

    @Test("ignoring the only block that refers to a note drops the note and its source")
    func ignoreDropsNote() {
        var set = CorrectionSet()
        set.setType(.ignored, for: anchor(0, 0.3))
        let result = set.applying(to: base).conversion
        #expect(result.document.notes.isEmpty)
        #expect(result.noteSources.isEmpty)
    }

    @Test("a figure can be ignored but not turned into a paragraph")
    func figureRetype() {
        var set = CorrectionSet()
        set.setType(.paragraph, for: anchor(1, 0.3))
        let result = set.applying(to: base)
        #expect(result.conversion.document.blocks[3] == base.document.blocks[3])
        #expect(result.unapplied == [.retype(anchor(1, 0.3), to: .paragraph)])
    }

    @Test("an edit replaces text and keeps emphasis and references")
    func edit() {
        var set = CorrectionSet()
        set.setText(from: "He read Журавeль aloud.", to: "He read Журавель aloud.", for: anchor(1, 0.1))
        set.setText(
            from: "Clean text\u{FFFC} goes on.", to: "Clean text\u{FFFC} continues.", for: anchor(0, 0.3)
        )
        let blocks = set.applying(to: base).conversion.document.blocks
        #expect(blocks[2] == .paragraph(["He read ", .emphasis("Журавель"), " aloud."]))
        #expect(blocks[1] == .paragraph(["Clean text", .noteReference("note-1"), " continues."]))
    }

    @Test("an edit of a figure changes its caption")
    func editCaption() {
        var set = CorrectionSet()
        set.setText(from: "Fig. 1", to: "Figure 1", for: anchor(1, 0.3))
        let blocks = set.applying(to: base).conversion.document.blocks
        #expect(blocks[3] == .figure(Figure(imageID: "figure-001", alternativeText: "", caption: ["Figure 1"])))
    }

    @Test("an edit of a note text found by the note's source")
    func editNote() {
        var set = CorrectionSet()
        set.setText(from: "Note about Журавeль.", to: "Note about Журавель.", for: anchor(1, 0.8))
        let notes = set.applying(to: base).conversion.document.notes
        #expect(notes[0].content == ["Note about Журавель."])
    }

    @Test("an edit whose original text no longer matches is left unapplied")
    func staleEdit() {
        var set = CorrectionSet()
        set.setText(from: "Something else", to: "Changed", for: anchor(1, 0.1))
        let result = set.applying(to: base)
        #expect(result.conversion == base)
        #expect(result.unapplied.count == 1)
    }

    @Test("a correction for a place where no block lies is left unapplied")
    func orphan() {
        var set = CorrectionSet()
        set.setType(.ignored, for: anchor(1, 0.9))
        #expect(set.applying(to: base).unapplied.count == 1)
    }

    @Test("a replaced word changes whole words everywhere, notes included, and nothing longer")
    func replaceWord() {
        var set = CorrectionSet()
        set.replaceWord("Журавeль", with: "Журавель")
        let result = set.applying(to: base).conversion
        #expect(result.document.blocks[2] == .paragraph(["He read ", .emphasis("Журавель"), " aloud."]))
        #expect(result.document.blocks[4] == .paragraph(["Журавель again, and Журавeльем too."]))
        #expect(result.document.notes[0].content == ["Note about Журавель."])
    }

    @Test("corrections still find their blocks when the boxes shift a little")
    func shiftedBoxes() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(1, 0.1))
        var moved = base
        moved.blockSources[2] = BlockSource(page: 1, box: box(0.11, height: 0.09))
        let result = set.applying(to: moved)
        #expect(result.unapplied.isEmpty)
        #expect(result.conversion.document.blocks[2].isHeading)
    }

    @Test("a correction does not move to a block on another page")
    func differentPage() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(0, 0.3))
        var moved = base
        moved.blockSources[1] = BlockSource(page: 1, box: box(0.3))
        #expect(set.applying(to: moved).unapplied.count == 1)
    }

    @Test("a new type for the same block replaces the earlier one, and resetting removes it")
    func setAndReset() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(1, 0.1))
        set.setType(.ignored, for: anchor(1, 0.1))
        #expect(set.corrections == [.retype(anchor(1, 0.1), to: .ignored)])
        #expect(set.type(for: anchor(1, 0.1)) == .ignored)
        set.resetType(for: anchor(1, 0.1))
        #expect(set.isEmpty)
        #expect(set.type(for: anchor(1, 0.1)) == nil)
    }

    @Test("editing a block again keeps the first original text, and restoring it drops the edit")
    func editTwice() {
        var set = CorrectionSet()
        set.setText(from: "a", to: "b", for: anchor(1, 0.1))
        set.setText(from: "b", to: "c", for: anchor(1, 0.1))
        #expect(set.corrections == [.edit(anchor(1, 0.1), from: "a", to: "c")])
        set.setText(from: "c", to: "a", for: anchor(1, 0.1))
        #expect(set.isEmpty)
    }

    @Test("replacing a word again for the same word replaces the rule")
    func replaceWordTwice() {
        var set = CorrectionSet()
        set.replaceWord("a", with: "b")
        set.replaceWord("a", with: "c")
        #expect(set.corrections == [.replaceWord("a", with: "c")])
    }

    @Test("survives a JSON round trip")
    func codable() throws {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(1, 0.1))
        set.setText(from: "a", to: "b", for: anchor(0, 0.3))
        set.replaceWord("x", with: "y")
        let decoded = try JSONDecoder().decode(CorrectionSet.self, from: JSONEncoder().encode(set))
        #expect(decoded == set)
    }
}

private extension Block {
    var isHeading: Bool {
        if case .heading = self {
            true
        } else {
            false
        }
    }
}
