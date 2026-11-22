import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing

@Suite("Merging and splitting blocks")
struct StructureCorrectionTests {
    private let base = sampleConversion()

    // MARK: - Merging

    @Test("merging joins two neighbouring paragraphs into one block")
    func merge() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("", ""))
        let result = set.applying(to: base)
        let conversion = result.conversion
        #expect(conversion.document.blocks.count == 4)
        #expect(conversion.document.blocks[1] == .paragraph([
            "Clean text", .noteReference("note-1"), " goes on.", " ", "He read ", .emphasis("Журавeль"), " aloud.",
        ]))
        #expect(conversion.blockSources.count == 4)
        let source = conversion.blockSources[1]
        #expect(source.start == base.blockSources[1].start)
        #expect(source.areas.map(\.page) == [0, 1])
        #expect(result.unapplied.isEmpty)
    }

    @Test("a merged block keeps the type of the first one")
    func mergeKeepsFirstType() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.1), with: anchor(0, 0.3), texts: ("", ""))
        let blocks = set.applying(to: base).conversion.document.blocks
        #expect(blocks[0] == .heading(level: 1, content: [
            "Chapter", " ", "Clean text", .noteReference("note-1"), " goes on.",
        ]))
    }

    @Test("blocks merge in a chain")
    func mergeChain() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("", ""))
        set.merge(anchor(0, 0.3), with: anchor(1, 0.3), texts: ("", ""))
        // The figure cannot be merged: the second merge finds nothing to do.
        #expect(set.applying(to: base).unapplied == [set.corrections[1]])
    }

    @Test("a figure is not merged, and the correction is reported")
    func mergeFigureRejected() {
        var set = CorrectionSet()
        set.merge(anchor(1, 0.1), with: anchor(1, 0.3), texts: ("", ""))
        let result = set.applying(to: base)
        #expect(result.conversion == base)
        #expect(result.unapplied == set.corrections)
    }

    @Test("blocks that are not neighbours are not merged")
    func mergeNotAdjacent() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.1), with: anchor(1, 0.1), texts: ("", ""))
        let result = set.applying(to: base)
        #expect(result.conversion == base)
        #expect(result.unapplied.count == 1)
    }

    @Test("the type of the absorbed block is dropped, the edits of both are joined")
    func mergeMigratesEdits() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(1, 0.1))
        set.setText(from: "He read \u{FFFC}", to: "x", for: anchor(1, 0.1))
        set.setText(from: "Clean text", to: "Clear text", for: anchor(0, 0.3))
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("Clean text", "He read \u{FFFC}"))
        #expect(!set.corrections.contains {
            if case .retype = $0 {
                true
            } else {
                false
            }
        })
        let edits = set.corrections.compactMap { correction -> (String, String)? in
            if case let .edit(_, from, to) = correction {
                (from, to)
            } else {
                nil
            }
        }
        #expect(edits.count == 1)
        #expect(edits.first?.0 == "Clean text He read \u{FFFC}")
        #expect(edits.first?.1 == "Clear text x")
    }

    // MARK: - Splitting

    private let text = "Clean text\u{FFFC} goes on."

    @Test("splitting cuts a paragraph in two at the offset, trimming the space")
    func split() {
        var set = CorrectionSet()
        set.split(anchor(0, 0.3), at: 11, of: text)
        let result = set.applying(to: base)
        let conversion = result.conversion
        #expect(conversion.document.blocks.count == 6)
        #expect(conversion.document.blocks[1] == .paragraph(["Clean text", .noteReference("note-1")]))
        #expect(conversion.document.blocks[2] == .paragraph(["goes on."]))
        #expect(conversion.blockSources.count == 6)
        let (first, second) = (conversion.blockSources[1], conversion.blockSources[2])
        #expect(first.box.minY == 0.3)
        #expect(abs(first.box.maxY - second.box.minY) < 1e-9)
        #expect(abs(second.box.maxY - base.blockSources[1].box.maxY) < 1e-9)
        #expect(first.page == 0 && second.page == 0)
        #expect(result.unapplied.isEmpty)
    }

    @Test("each part of a split block can get a type of its own")
    func splitParts() {
        var set = CorrectionSet()
        set.split(anchor(0, 0.3), at: 11, of: text)
        let parts = set.applying(to: base).conversion.blockSources
        set.setType(.heading(level: 2), for: BlockAnchor(parts[2]))
        let result = set.applying(to: base)
        #expect(result.conversion.document.blocks[1] == .paragraph(["Clean text", .noteReference("note-1")]))
        #expect(result.conversion.document.blocks[2] == .heading(level: 2, content: ["goes on."]))
    }

    @Test("a split block spread over two pages is cut where the text falls")
    func splitAcrossPages() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("", ""))
        let merged = set.applying(to: base).conversion
        let mergedText = "Clean text\u{FFFC} goes on. He read Журавeль aloud."
        let cut = "Clean text\u{FFFC} goes on.".count
        set.split(anchor(0, 0.3), at: cut + 1, of: mergedText)
        let result = set.applying(to: base)
        #expect(merged.blockSources[1].areas.count == 2)
        #expect(result.unapplied.isEmpty)
        #expect(result.conversion.document.blocks[1] == .paragraph([
            "Clean text",
            .noteReference("note-1"),
            " goes on.",
        ]))
        #expect(result.conversion.document.blocks[2] == .paragraph(["He read ", .emphasis("Журавeль"), " aloud."]))
        let sources = result.conversion.blockSources
        #expect(sources[1].areas.map(\.page) == [0])
        #expect(sources[2].areas.map(\.page) == [1])
    }

    @Test("splitting keeps the emphasis of both parts")
    func splitKeepsEmphasis() {
        var set = CorrectionSet()
        set.split(anchor(1, 0.1), at: 8, of: "He read Журавeль aloud.")
        let blocks = set.applying(to: base).conversion.document.blocks
        #expect(blocks[2] == .paragraph(["He read"]))
        #expect(blocks[3] == .paragraph([.emphasis("Журавeль"), " aloud."]))
    }

    @Test("a split whose text no longer matches is not applied")
    func splitStale() {
        var set = CorrectionSet()
        set.split(anchor(0, 0.3), at: 11, of: "Other text here.")
        let result = set.applying(to: base)
        #expect(result.conversion == base)
        #expect(result.unapplied == set.corrections)
    }

    @Test("a split at either end, or of a figure, is not applied")
    func splitRejected() {
        var set = CorrectionSet()
        set.split(anchor(0, 0.3), at: 0, of: text)
        set.split(anchor(1, 0.3), at: 2, of: "Fig. 1")
        let result = set.applying(to: base)
        #expect(result.conversion == base)
        #expect(result.unapplied.count == 2)
    }

    @Test("a split drops the type and the edit made to the block before")
    func splitDropsEarlier() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: anchor(0, 0.3))
        set.setText(from: "Clean text\u{FFFC} goes on.", to: "Clean", for: anchor(0, 0.3))
        set.split(anchor(0, 0.3), at: 11, of: text)
        #expect(set.corrections.count == 1)
    }

    @Test("a note text split in two keeps the first part as the note, the rest becomes a paragraph in reading order")
    func splitNote() {
        var set = CorrectionSet()
        set.split(BlockAnchor(base.noteSources[0]), at: 11, of: "Note about Журавeль.")
        let result = set.applying(to: base)
        let conversion = result.conversion
        #expect(conversion.document.notes[0].content == ["Note about"])
        #expect(conversion.noteSources.count == 1)
        #expect(conversion.document.blocks.count == 6)
        #expect(conversion.document.blocks[5] == .paragraph(["Журавeль."]))
        #expect(conversion.blockSources.count == 6)
        #expect(conversion.blockSources[5].page == 1)
        #expect(result.unapplied.isEmpty)
    }

    @Test("the rest of a split note goes among the blocks by its place on the page")
    func splitNoteOrder() {
        var moved = base
        moved.noteSources[0] = BlockSource(page: 0, box: box(0.2, height: 0.05))
        var set = CorrectionSet()
        set.split(BlockAnchor(moved.noteSources[0]), at: 11, of: "Note about Журавeль.")
        let blocks = set.applying(to: moved).conversion.document.blocks
        #expect(blocks[1] == .paragraph(["Журавeль."]))
    }

    @Test("a note running over three pages is cut at the page where its tail starts, not inside a heading line")
    func splitNoteAcrossPages() {
        let head = String(repeating: "слово ", count: 100)
        let tail = "ЯЛИНКА Слов'янські традиційні уявлення"
        let text = head + tail
        var conversion = base
        conversion.document.notes[0].content = [.text(text)]
        var source = BlockSource(page: 0, box: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.12))
        source.continuations = [
            PageArea(page: 1, box: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.03)),
            PageArea(page: 1, box: CGRect(x: 0.1, y: 0.16, width: 0.3, height: 0.03)),
        ]
        conversion.noteSources = [source]
        var set = CorrectionSet()
        set.split(BlockAnchor(source), at: head.count, of: text)
        let result = set.applying(to: conversion).conversion
        #expect(result.noteSources[0].areas.count == 1)
        #expect(result.noteSources[0].page == 0)
        let rest = result.blockSources.first { $0.box.width < 0.2 }
        #expect(rest?.areas.count == 2)
    }

    @Test("a cut near a long block's far end keeps the short tail small")
    func splitTailOnly() {
        let text = String(repeating: "слово ", count: 40)
        var conversion = base
        conversion.document.chapters[0].blocks[1] = .paragraph([.text(text)])
        var set = CorrectionSet()
        set.split(anchor(0, 0.3), at: 6 * 39, of: text)
        let sources = set.applying(to: conversion).conversion.blockSources
        #expect(sources[1].box.height > 0.09 * 0.85)
        #expect(sources[2].box.height < 0.02)
    }

    // MARK: - Surviving a new conversion

    @Test("merge and split find their blocks again when the boxes shift a little")
    func survivesRerun() {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("", ""))
        set.split(anchor(1, 0.5), at: 6, of: "Журавeль again, and Журавeльем too.")
        var rerun = base
        rerun.blockSources = rerun.blockSources.map { source in
            var moved = source
            moved.start.box = moved.start.box.offsetBy(dx: 0.004, dy: -0.006)
            return moved
        }
        let result = set.applying(to: rerun)
        #expect(result.unapplied.isEmpty)
        #expect(result.conversion.document.blocks.count == 5)
    }

    @Test("structure corrections are stored as JSON and read back")
    func codable() throws {
        var set = CorrectionSet()
        set.merge(anchor(0, 0.3), with: anchor(1, 0.1), texts: ("", ""))
        set.split(anchor(1, 0.5), at: 6, of: "Журавeль again, and Журавeльем too.")
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(CorrectionSet.self, from: data) == set)
    }

    @Test("structured(from:) gives the blocks before edits and types")
    func structured() {
        var set = CorrectionSet()
        set.setType(.ignored, for: anchor(0, 0.3))
        set.split(anchor(0, 0.3), at: 11, of: text)
        let structured = set.structured(from: base)
        #expect(structured.document.blocks.count == 6)
        #expect(structured.document.blocks[1] == .paragraph(["Clean text", .noteReference("note-1")]))
    }
}
