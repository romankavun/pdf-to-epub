@testable import AppModel
import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing
import TestSupport

/// What a user can see of a project after the corrections: enough to tell
/// whether two states are the same document. Sources are left out of the
/// comparison between runs because a re-run moves boxes by a few pixels.
private struct Outcome: Equatable {
    var blocks: [Block]
    var notes: [Note.ID: [Inline]]
    var ignored: [Block]
    var unapplied: [Correction]
}

@MainActor
private extension ProjectModel {
    var outcome: Outcome {
        Outcome(
            blocks: conversion.document.blocks,
            notes: Dictionary(uniqueKeysWithValues: conversion.document.notes.map { ($0.id, $0.content) }),
            ignored: ignored.map(\.block), unapplied: unapplied
        )
    }
}

private extension Block {
    var text: [Inline]? {
        switch self {
        case let .heading(_, content), let .paragraph(content): content
        case .figure: nil
        }
    }
}

/// One random change a user could make in the review, applied to `model`.
@MainActor
// swiftlint:disable:next cyclomatic_complexity
private func randomChange(
    _ model: ProjectModel, _ random: inout SeededGenerator, vocabulary: DocumentGenerator, navigatesHistory: Bool = true
) {
    let blocks = model.conversion.document.blocks
    let sources = model.conversion.blockSources
    guard !blocks.isEmpty, blocks.count == sources.count else { return }
    let index = random.int(0 ... blocks.count - 1)
    let anchor = BlockAnchor(sources[index])
    let text = blocks[index].text?.canonicalText
    switch random.int(0 ... 9) {
    case 0, 1:
        let types: [BlockType] = text == nil ? [.ignored] : [.paragraph, .heading(level: random.int(1 ... 4)), .ignored]
        model.setType(random.pick(types), for: anchor)
    case 2:
        if let ignored = model.ignored.randomElement(using: &random) {
            model.resetType(for: BlockAnchor(ignored.source))
        }
    case 3, 4:
        editText(model, anchor, text, &random, vocabulary)
    case 5:
        guard let word = text?.split(separator: " ").randomElement(using: &random) else { return }
        model.replaceWord(String(word), with: vocabulary.words(&random, count: 1 ... 1))
    case 6, 7:
        guard index + 1 < blocks.count else { return }
        model.merge(anchor, with: BlockAnchor(sources[index + 1]))
    case 8:
        guard let text, text.count >= 8 else { return }
        // Not within a quarter of either end: a sliver would be too small
        // for its area to be found again after a re-run moved it a little.
        model.split(anchor, at: random.int(text.count / 4 ... text.count * 3 / 4), of: text)
    default:
        guard navigatesHistory else { return }
        if model.canUndo, random.chance(0.5) {
            model.undo()
        } else if model.canRedo {
            model.redo()
        }
    }
}

/// Replaces a stretch of the text, as typing in the editor does.
@MainActor
private func editText(
    _ model: ProjectModel, _ anchor: BlockAnchor, _ text: String?, _ random: inout SeededGenerator,
    _ vocabulary: DocumentGenerator
) {
    guard let text, !text.isEmpty else { return }
    var characters = Array(text)
    let start = random.int(0 ... characters.count - 1)
    let end = min(characters.count, start + random.int(0 ... 6))
    characters.replaceSubrange(start ..< end, with: Array(vocabulary.words(&random, count: 1 ... 2)))
    model.setText(String(characters.filter { $0 != "\u{FFFC}" }), for: anchor)
}

/// The same recognized pages analysed again: the layout is the same but
/// boxes differ by a fraction of a line and note labels are counted again.
private func rerun(_ conversion: Conversion, _ random: inout SeededGenerator) -> Conversion {
    func moved(_ source: BlockSource, _ random: inout SeededGenerator) -> BlockSource {
        var source = source
        let shift = random.chance(0.5) ? 0 : random.double(-0.001 ... 0.001)
        source.start.box = source.start.box.offsetBy(dx: shift, dy: -shift)
        return source
    }
    var result = conversion
    result.blockSources = conversion.blockSources.map { moved($0, &random) }
    result.noteSources = conversion.noteSources.map { moved($0, &random) }
    result.document.notes = conversion.document.notes.map { note in
        var note = note
        note.label = "r\(random.int(0 ... 99))"
        return note
    }
    return result
}

@MainActor
@Suite("Corrections invariants")
struct CorrectionsInvariantTests {
    private let generator = DocumentGenerator(text: .tidy, layout: .tidy, maximumBlocks: 12)

    @Test("every correction survives converting again: the same document comes out and nothing is left unapplied")
    func survivesRerun() {
        Property.check("survives re-run", cases: 150) { random in
            let base = generator.conversion(&random)
            let model = ProjectModel(base: base)
            for _ in 0 ..< random.int(1 ... 14) {
                randomChange(model, &random, vocabulary: generator)
            }
            let before = model.outcome
            let corrections = model.corrections
            try Property.requireEqual(before.unapplied, [], "corrections not applied to the base they were made on")

            model.replaceBase(rerun(base, &random))
            try Property.requireEqual(model.corrections, corrections, "corrections after converting again")
            try Property.requireEqual(model.outcome.unapplied, [], "corrections lost by converting again")
            try Property.require(model.outcome == before, "the corrected document differs after converting again")
        }
    }

    @Test("undo after a change returns the exact earlier state, and redo the later one")
    func undoIsExact() {
        Property.check("undo exactness", cases: 150) { random in
            let model = ProjectModel(base: generator.conversion(&random))
            for step in 0 ..< random.int(1 ... 14) {
                let earlier = (model.corrections, model.conversion, model.ignored)
                randomChange(model, &random, vocabulary: generator, navigatesHistory: false)
                guard model.corrections != earlier.0 else { continue }
                let later = (model.corrections, model.conversion, model.ignored)
                model.undo()
                try Property.requireEqual(model.corrections, earlier.0, "corrections after undo at step \(step)")
                try Property.require(model.conversion == earlier.1, "conversion after undo at step \(step)")
                try Property.require(model.ignored == earlier.2, "ignored blocks after undo at step \(step)")
                model.redo()
                try Property.requireEqual(model.corrections, later.0, "corrections after redo at step \(step)")
                try Property.require(model.conversion == later.1, "conversion after redo at step \(step)")
            }
        }
    }

    @Test("applying a proposed type change to similar blocks twice changes nothing the second time")
    func propagationIsIdempotent() {
        Property.check("propagation idempotent", cases: 150) { random in
            let model = ProjectModel(base: generator.conversion(&random))
            let blocks = model.conversion.document.blocks
            let sources = model.conversion.blockSources
            let candidates = blocks.indices.filter { blocks[$0].text != nil }
            guard let index = candidates.randomElement(using: &random) else { return }
            let anchor = BlockAnchor(sources[index])
            let before: BlockType = if case let .heading(level, _) = blocks[index] {
                .heading(level: level)
            } else {
                .paragraph
            }
            let type: BlockType = before == .paragraph ? .heading(level: random.int(1 ... 3)) : .paragraph

            model.setType(type, for: anchor)
            let similar = model.similarBlocks(like: anchor, thatAre: before)
            let earlier = model.corrections
            model.setType(type, for: similar)
            let once = (model.corrections, model.outcome)
            model.setType(type, for: similar)
            try Property.requireEqual(model.corrections, once.0, "corrections after the second application")
            try Property.require(model.outcome == once.1, "the document after the second application")
            // One step of undo still takes the whole propagation back.
            if !similar.isEmpty {
                model.undo()
                try Property.requireEqual(model.corrections, earlier, "undo of a propagation")
            }
        }
    }
}
