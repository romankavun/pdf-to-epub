import DocumentModel
import Foundation
import LayoutAnalysis
import OCR
import Testing

/// Page geometry as in `LayoutAnalyzerTests`: body lines 0.017 tall, 0.02
/// apart, margin at x = 0.05, first-line indent at 0.08. A character is
/// 0.008 wide and a marker 0.012.
private let pitch = 0.02, characterWidth = 0.008, markerWidth = 0.012

/// Builds the lines and markers of a page from a compact description.
///
/// A string prefixed with ">" is indented; an empty string leaves a blank
/// line. `{label}` stands for a note marker at that place: it is not part of
/// the line's text, as when the marker was erased before recognition, and
/// the text after it in the same token becomes a word of its own.
private func page(top: Double = 0.1, _ texts: [String]) -> PageContent {
    var lines: [TextLine] = []
    var markers: [NoteMarker] = []
    for (index, text) in texts.enumerated() where !text.isEmpty {
        let indented = text.hasPrefix(">")
        let y = top + Double(index) * pitch
        var x = indented ? 0.08 : 0.05
        var words: [TextWord] = []
        func addWord(_ word: Substring) {
            guard !word.isEmpty else { return }
            let width = Double(word.count) * characterWidth
            words.append(TextWord(text: String(word), box: CGRect(x: x, y: y, width: width, height: 0.017)))
            x += width
        }
        for token in (indented ? text.dropFirst() : Substring(text)).split(separator: " ") {
            if let open = token.firstIndex(of: "{"), let close = token.firstIndex(of: "}") {
                addWord(token[..<open])
                markers.append(NoteMarker(
                    box: CGRect(x: x, y: y, width: markerWidth, height: 0.012),
                    label: String(token[token.index(after: open) ..< close])
                ))
                x += markerWidth
                addWord(token[token.index(after: close)...])
            } else {
                addWord(token)
            }
            x += characterWidth
        }
        guard let first = words.first, let last = words.last else { continue }
        lines.append(TextLine(
            text: words.map(\.text).joined(separator: " "),
            box: CGRect(x: first.box.minX, y: y, width: last.box.maxX - first.box.minX, height: 0.017),
            words: words
        ))
    }
    return PageContent(lines: lines, markers: markers)
}

/// A page of plain prose placed before the pages under test. The body
/// margin is the most common left edge in the document, so the short pages of
/// these tests need some ordinary unindented lines beside them.
private let prose = page([
    ">Prose that sets the margin", "of the document with enough", "unindented lines for the", "margin to be measured",
    "from them and not from", "the indented first lines", "of the short paragraphs", "used in these tests,",
    "however many of those", "a single test may hold", "on its pages of notes", "that are one line each",
    "and all start indented", "like new paragraphs do", "in the sample sets", "this was written for.",
])

/// The layout of `pages` preceded by ``prose``, without the prose paragraph.
private func layout(_ pages: [PageContent]) -> DocumentLayout {
    var layout = LayoutAnalyzer().layout(of: [prose] + pages)
    layout.blocks.removeFirst()
    return layout
}

private func note(_ number: Int, label: String, _ content: [Inline]) -> Note {
    Note(id: "note-\(number)", label: label, content: content)
}

@Suite("LayoutAnalyzer notes")
struct LayoutAnalyzerNoteTests {
    @Test("a marker inside a paragraph is a reference to the note that starts with the same marker")
    func referenceAndBody() {
        let layout = layout([page([
            ">Some text with a note{1} inside", "and a second line.", "",
            ">{1} The text of the note", "on two lines.",
        ])])
        #expect(layout.blocks == [
            .paragraph(["Some text with a note", .noteReference("note-1"), " inside and a second line."]),
        ])
        #expect(layout.notes == [note(1, label: "1", ["The text of the note on two lines."])])
        #expect(layout.unlinkedReferences == 0 && layout.unlinkedNotes == 0)
    }

    @Test("punctuation after a reference stays attached to it")
    func punctuationAfterReference() {
        let layout = layout([page([
            ">First claim{1}. Second claim{2}• Third{3}, and the end{4}", "", ">{1} One", ">{2} Two", ">{3} Three",
            ">{4} Four",
        ])])
        #expect(layout.blocks == [.paragraph([
            "First claim", .noteReference("note-1"), ". Second claim", .noteReference("note-2"),
            // A full stop left alone by the erased marker is read as a bullet.
            ". Third", .noteReference("note-3"), ", and the end", .noteReference("note-4"),
        ])])
    }

    @Test("text continues after a reference at the end or the start of a line")
    func referenceAtLineEdge() {
        let layout = layout([page([
            ">A line that ends with a note{1}", "goes on and breaks before another", "{2} which opens this line.", "",
            ">{1} One", ">{2} Two",
        ])])
        #expect(layout.blocks == [.paragraph([
            "A line that ends with a note", .noteReference("note-1"), " goes on and breaks before another",
            .noteReference("note-2"), " which opens this line.",
        ])])
        #expect(layout.notes.map(\.label) == ["1", "2"])
    }

    @Test("notes at the end of each section are linked section by section")
    func sectionNotes() {
        let layout = layout([
            page([">First section{I} text{II} here.", "", ">{I} Note one.", ">{II} Note two."]),
            page([">Second section{III} text.", "", ">{} Note three."]),
        ])
        #expect(layout.blocks == [
            .paragraph(["First section", .noteReference("note-1"), " text", .noteReference("note-2"), " here."]),
            .paragraph(["Second section", .noteReference("note-3"), " text."]),
        ])
        // The unread label of the last note continues the numbering.
        #expect(layout.notes.map(\.label) == ["I", "II", "III"])
        #expect(layout.notes.map(\.content) == [["Note one."], ["Note two."], ["Note three."]])
    }

    @Test("notes collected at the end of the document are linked across pages")
    func endnotes() {
        let layout = layout([
            page([">Chapter one{1} text{2} here."]),
            page([">Chapter two{3} text."]),
            page([">{1} Note one.", ">{2} Note two starts", "and continues on the next page"]),
            page(["where it ends.", ">{3} Note three."]),
        ])
        #expect(layout.blocks.count == 2)
        #expect(layout.notes == [
            note(1, label: "1", ["Note one."]),
            note(2, label: "2", ["Note two starts and continues on the next page where it ends."]),
            note(3, label: "3", ["Note three."]),
        ])
        #expect(layout.blocks[1] == .paragraph(["Chapter two", .noteReference("note-3"), " text."]))
    }

    @Test("notes set as a numbered list with a hanging indent are read whole, without the list number")
    func hangingList() {
        let layout = layout([
            page([">Body text{7} with two{8} notes."]),
            page([
                "1. {7} The first note starts at the margin", ">and continues with an indent", ">over three lines.",
                "2. {8} The second note follows directly", ">and runs on to the next page",
            ]),
            page([">where it ends.", "", "Plain text after the notes", "is not part of them."]),
        ])
        #expect(layout.notes == [
            Note(id: "note-1", label: "7", content: [
                "The first note starts at the margin and continues with an indent over three lines.",
            ]),
            Note(id: "note-2", label: "8", content: [
                "The second note follows directly and runs on to the next page where it ends.",
            ]),
        ])
        #expect(layout.blocks == [
            .paragraph(["Body text", .noteReference("note-1"), " with two", .noteReference("note-2"), " notes."]),
            .paragraph(["Plain text after the notes is not part of them."]),
        ])
    }

    @Test("a misread list number before a note label is still a list number", arguments: ["IO.", "39-", "І6.", "7)"])
    func misreadListNumber(number: String) {
        let layout = layout([
            page([">Body text{5} with a note."]),
            page(["\(number) {5} The note starts at the margin", ">and continues with an indent."]),
        ])
        #expect(layout.notes == [
            Note(id: "note-1", label: "5", content: ["The note starts at the margin and continues with an indent."]),
        ])
        #expect(layout.blocks == [.paragraph(["Body text", .noteReference("note-1"), " with a note."])])
    }

    @Test("a number before a reference in running text is not a list number")
    func numberBeforeReference() {
        let layout = layout([page([
            ">It happened in the year", "1984. {1} is a reference here.", "", ">{1} The note.",
        ])])
        #expect(layout.blocks == [
            .paragraph(["It happened in the year 1984.", .noteReference("note-1"), " is a reference here."]),
        ])
    }

    @Test("a second reference to an earlier note links to that note")
    func backReference() {
        let layout = layout([page([
            ">One{1} two{2} again one{1} three{3}.", "", ">{1} First.", ">{2} Second.", ">{3} Third.",
        ])])
        #expect(layout.blocks == [.paragraph([
            "One", .noteReference("note-1"), " two", .noteReference("note-2"), " again one", .noteReference("note-1"),
            " three", .noteReference("note-3"), ".",
        ])])
        #expect(layout.unlinkedReferences == 0)
    }

    @Test("references that cite notes out of order are linked by their labels")
    func citations() {
        let layout = layout([
            page([">One{2} two{7} three{1} four{7} five{4}."]),
            page([
                ">{1} First.", ">{2} Second.", ">{3} Third.", ">{4} Fourth.", ">{5} Fifth.", ">{6} Sixth.",
                ">{7} Seventh.",
            ]),
        ])
        #expect(layout.blocks.first == .paragraph([
            "One", .noteReference("note-2"), " two", .noteReference("note-7"), " three", .noteReference("note-1"),
            " four", .noteReference("note-7"), " five", .noteReference("note-4"), ".",
        ]))
        #expect(layout.notes.map(\.label) == ["1", "2", "4", "7"])
        #expect(layout.unlinkedReferences == 0 && layout.unlinkedNotes == 3)
    }

    @Test("when numbering restarts, a label links to the nearest note that carries it")
    func restartingNumbers() {
        let layout = layout([
            page([">First part{1} text{2}.", "", ">{1} Note A.", ">{2} Note B."]),
            page([">Second part{1} text{2}.", "", ">{1} Note C.", ">{2} Note D."]),
        ])
        #expect(layout.blocks == [
            .paragraph(["First part", .noteReference("note-1"), " text", .noteReference("note-2"), "."]),
            .paragraph(["Second part", .noteReference("note-3"), " text", .noteReference("note-4"), "."]),
        ])
        #expect(layout.notes.map(\.content) == [["Note A."], ["Note B."], ["Note C."], ["Note D."]])
    }

    @Test("a reference whose label could not be read takes the next note in order")
    func unreadReference() {
        let layout = layout([page([
            ">One{1} two{} three{I3}.", "", ">{1} First.", ">{2} Second.", ">{3} Third.",
        ])])
        #expect(layout.blocks == [.paragraph([
            "One", .noteReference("note-1"), " two", .noteReference("note-2"), " three", .noteReference("note-3"), ".",
        ])])
    }

    @Test("a missed reference does not shift the ones after it")
    func missedReference() {
        // The reference to note 2 was not detected.
        let layout = layout([page([
            ">One{1} two three{3}.", "", ">{1} First.", ">{2} Second.", ">{3} Third.",
        ])])
        #expect(layout.blocks == [
            .paragraph(["One", .noteReference("note-1"), " two three", .noteReference("note-3"), "."]),
            // Nobody refers to note 2, so its text stays in the document.
            .paragraph(["2 Second."]),
        ])
        #expect(layout.notes.map(\.label) == ["1", "3"])
        #expect(layout.unlinkedNotes == 1)
    }

    @Test("a reference with no note left to link to stays in the text as its label")
    func referenceWithoutNote() {
        let layout = layout([page([">One{1} two{2}.", "", ">{1} First."])])
        #expect(layout.blocks == [.paragraph(["One", .noteReference("note-1"), " two2."])])
        #expect(layout.unlinkedReferences == 1)
    }

    @Test("markers inside a picture are ignored")
    func markerInPicture() {
        var content = page([">Plain text here.", "and more of it."])
        content.pictures = [PagePicture(imageID: "pic", box: CGRect(x: 0.05, y: 0.3, width: 0.6, height: 0.3))]
        content.markers = [NoteMarker(box: CGRect(x: 0.2, y: 0.4, width: 0.012, height: 0.012), label: "7")]
        let layout = layout([content])
        #expect(layout.blocks == [
            .paragraph(["Plain text here. and more of it."]),
            .figure(Figure(imageID: "pic", alternativeText: "")),
        ])
        #expect(layout.notes.isEmpty && layout.unlinkedReferences == 0)
    }

    @Test("a reference is placed by estimated positions when the engine reports no words")
    func withoutWords() {
        var content = page([">Some text with a note{1} inside.", "", ">{1} The note."])
        content.lines = content.lines.map { TextLine(text: $0.text, box: $0.box) }
        let layout = layout([content])
        #expect(layout.blocks == [.paragraph(["Some text with a note", .noteReference("note-1"), " inside."])])
        #expect(layout.notes == [note(1, label: "1", ["The note."])])
    }

    @Test("blocks(from:) gives the same blocks as the layout")
    func blocksOnly() {
        let pages = [page([">Text{1} here.", "", ">{1} Note."])]
        #expect(LayoutAnalyzer().blocks(from: pages) == LayoutAnalyzer().layout(of: pages).blocks)
    }

    @Test("a linked note leaves no source behind; an unlinked one keeps its own")
    func noteSources() {
        let layout = LayoutAnalyzer().layout(of: [prose, page([
            ">Text{1} here.", "", ">{1} Linked note.", ">{7} Orphan note.",
        ])])

        #expect(layout.blocks.count == 3)
        #expect(layout.sources.map(\.page) == [0, 1, 1])
        #expect(abs(layout.sources[2].box.minY - 0.16) < 1e-9)
    }

    @Test("every linked note records where its text lies")
    func linkedNoteSources() {
        let layout = LayoutAnalyzer().layout(of: [prose, page([
            ">Text{1} here{2} and{3}.", "", ">{1} First note.", ">{7} Orphan note.", ">{2} Second note,",
        ]), page(["running on.", ">{3} Third note."])])

        #expect(layout.notes.map(\.label) == ["1", "2", "3"])
        #expect(layout.noteSources.map(\.areas.count) == [1, 2, 1])
        #expect(layout.noteSources.map(\.page) == [1, 1, 2])
        #expect(abs(layout.noteSources[0].box.minY - 0.14) < 1e-9)
        #expect(abs(layout.noteSources[1].box.minY - 0.18) < 1e-9)
        #expect(abs(layout.noteSources[2].box.minY - 0.12) < 1e-9)
    }
}
