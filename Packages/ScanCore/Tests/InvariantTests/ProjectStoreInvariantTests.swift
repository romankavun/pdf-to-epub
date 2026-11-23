import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import ProjectStore
import Testing
import TestSupport

private func randomAnchor(_ generator: inout SeededGenerator) -> BlockAnchor {
    BlockAnchor(page: generator.int(0 ... 5), box: CGRect(
        x: generator.double(0 ... 0.5), y: generator.double(0 ... 0.9),
        width: generator.double(0.001 ... 0.5), height: generator.double(0.001 ... 0.1)
    ))
}

/// Any corrections the type allows, not only ones a user could make: the
/// store must write back exactly what it was given.
private func randomCorrections(_ generator: inout SeededGenerator) -> CorrectionSet {
    let texts = DocumentGenerator(text: .wild)
    var corrections: [Correction] = []
    for _ in 0 ..< generator.int(0 ... 8) {
        switch generator.int(0 ... 5) {
        case 0: corrections.append(.retype(
                randomAnchor(&generator),
                to: generator.pick([.paragraph, .ignored, .heading(level: generator.int(1 ... 6))])
            ))
        case 1: corrections.append(.edit(
                randomAnchor(&generator), from: texts.words(&generator), to: texts.words(&generator)
            ))
        case 2: corrections.append(.replaceWord(texts.words(&generator, count: 1 ... 1), with: texts.words(&generator)))
        case 3: corrections.append(.merge(randomAnchor(&generator), with: randomAnchor(&generator)))
        default: corrections.append(.split(
                randomAnchor(&generator), at: generator.int(1 ... 40), of: texts.words(&generator)
            ))
        }
    }
    return CorrectionSet(corrections: corrections)
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("invariant-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Suite("ProjectStore invariants")
struct ProjectStoreInvariantTests {
    private let store = ProjectStore()

    @Test("save then load returns the same document, corrections, ignored words and page references")
    func roundTrip() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let generator = DocumentGenerator(text: .wild, layout: .wild, maximumBlocks: 12)
        Property.check("project round trip", cases: 60) { random in
            let conversion = generator.conversion(&random)
            let corrections = randomCorrections(&random)
            let words = Set((0 ..< random.int(0 ... 4)).map { _ in
                generator.words(&random, count: 1 ... 1).lowercased()
            })
            let url = folder.appendingPathComponent("\(UUID().uuidString).scanproject")
            try store.create(conversion, at: url)
            try store.save(corrections, to: url)
            try store.save(ignoredWords: words, to: url)

            let loaded = try store.load(from: url)
            try Property.require(loaded.conversion.document == conversion.document, "the document changed")
            try Property.requireEqual(loaded.conversion.blockSources, conversion.blockSources, "block sources")
            try Property.requireEqual(loaded.conversion.noteSources, conversion.noteSources, "note sources")
            try Property.requireEqual(loaded.conversion.pageURLs, conversion.pageURLs, "page URLs")
            try Property.requireEqual(
                loaded.conversion.unlinkedReferences,
                conversion.unlinkedReferences,
                "unlinked references"
            )
            try Property.requireEqual(loaded.conversion.unlinkedNotes, conversion.unlinkedNotes, "unlinked notes")
            try Property.requireEqual(loaded.corrections, corrections, "corrections")
            try Property.requireEqual(loaded.ignoredWords, words, "ignored words")
        }
    }

    @Test("pages moved into the bundle are found again after loading")
    func movedPages() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let generator = DocumentGenerator(text: .tidy, layout: .tidy, maximumBlocks: 6)
        Property.check("moved pages", cases: 20) { random in
            var conversion = generator.conversion(&random)
            let scans = folder.appendingPathComponent("scans-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
            conversion.pageURLs = try conversion.pageURLs.indices.map { index in
                let file = scans.appendingPathComponent("page-\(index).png")
                try Data([UInt8(index)]).write(to: file)
                return file
            }
            let url = folder.appendingPathComponent("\(UUID().uuidString).scanproject")
            let stored = try store.create(conversion, at: url, movingPages: true)
            let loaded = try store.load(from: url)
            try Property.requireEqual(loaded.conversion.pageURLs, stored.pageURLs, "page URLs")
            for (index, page) in loaded.conversion.pageURLs.enumerated() {
                try Property.require(
                    (try? Data(contentsOf: page)) == Data([UInt8(index)]),
                    "page \(index) is not readable at \(page.path)"
                )
            }
        }
    }
}
