@testable import AppModel
import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import ProjectStore
import Testing

private let location = URL(fileURLWithPath: "/projects/Document.scanproject")

func projectBox(_ y: Double, height: Double = 0.1) -> CGRect {
    CGRect(x: 0.05, y: y, width: 0.9, height: height)
}

func projectAnchor(_ page: Int, _ y: Double) -> BlockAnchor {
    BlockAnchor(page: page, box: projectBox(y))
}

/// Page 0: a paragraph and a heading-like one; page 1: two more paragraphs
/// of the same shape as the first, one with a misread word.
func projectConversion() -> Conversion {
    let blocks: [Block] = [
        .paragraph(["Title one"]),
        .paragraph(["Body ", .noteReference("note-1"), " text."]),
        .paragraph(["Журавeль is here."]),
        .paragraph(["Title two"]),
        .paragraph(["Журавeль again."]),
    ]
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "T", blocks: blocks)],
        notes: [Note(id: "note-1", label: "7", content: ["Note text."])]
    )
    func line(_ page: Int, _ y: Double) -> BlockSource {
        BlockSource(page: page, box: CGRect(x: 0.1, y: y, width: 0.3, height: 0.04))
    }
    return Conversion(
        document: document,
        pageURLs: ["0", "1"].map { URL(fileURLWithPath: "/p/\($0).png") },
        blockSources: [
            line(0, 0.1),
            BlockSource(page: 0, box: projectBox(0.3, height: 0.2)),
            BlockSource(page: 1, box: projectBox(0.1, height: 0.2)),
            line(1, 0.5),
            BlockSource(page: 1, box: projectBox(0.7, height: 0.2)),
        ],
        noteSources: [BlockSource(page: 1, box: projectBox(0.95, height: 0.03))]
    )
}

final class FakeStorage: ProjectPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var savedStorage: [CorrectionSet] = []
    private var replacedStorage: [Conversion] = []
    private var ignoredStorage: [Set<String>] = []
    private var createdStorage: [Conversion] = []
    private var createdDetails: [(name: String, parent: URL, movingPages: Bool)] = []
    var saveFailure: (any Error)?
    var replaceFailure: (any Error)?
    var createFailure: (any Error)?
    /// Projects that "exist on disk", by location.
    var projects: [URL: Project] = [:]

    var saved: [CorrectionSet] {
        lock.withLock { savedStorage }
    }

    var savedIgnored: [Set<String>] {
        lock.withLock { ignoredStorage }
    }

    var replaced: [Conversion] {
        lock.withLock { replacedStorage }
    }

    var created: [Conversion] {
        lock.withLock { createdStorage }
    }

    var createdDetail: [(name: String, parent: URL, movingPages: Bool)] {
        lock.withLock { createdDetails }
    }

    func isProject(at url: URL) -> Bool {
        projects[url] != nil
    }

    func createProject(
        for conversion: Conversion, named name: String, in parent: URL, movingPages: Bool
    ) throws -> (location: URL, conversion: Conversion) {
        if let createFailure {
            throw createFailure
        }
        lock.withLock {
            createdStorage.append(conversion)
            createdDetails.append((name, parent, movingPages))
        }
        let location = parent.appendingPathComponent(name + ".scanproject")
        var stored = conversion
        if movingPages {
            stored.pageURLs = conversion.pageURLs.map {
                location.appendingPathComponent("pages").appendingPathComponent($0.lastPathComponent)
            }
        }
        return (location, stored)
    }

    func load(from url: URL) throws -> Project {
        guard let project = projects[url] else { throw StorageFailure() }
        return project
    }

    func save(_ corrections: CorrectionSet, to _: URL) throws {
        if let saveFailure {
            throw saveFailure
        }
        lock.withLock { savedStorage.append(corrections) }
    }

    func save(ignoredWords: Set<String>, to _: URL) throws {
        lock.withLock { ignoredStorage.append(ignoredWords) }
    }

    func replaceConversion(in _: URL, with conversion: Conversion) throws {
        if let replaceFailure {
            throw replaceFailure
        }
        lock.withLock { replacedStorage.append(conversion) }
    }
}

struct StorageFailure: Error, CustomStringConvertible {
    var description: String {
        "disk full"
    }
}

@MainActor
@Suite("ProjectModel")
struct ProjectModelTests {
    private let storage = FakeStorage()

    private func model(corrections: CorrectionSet = CorrectionSet(), at place: URL? = location) -> ProjectModel {
        ProjectModel(base: projectConversion(), corrections: corrections, location: place, storage: storage)
    }

    @Test("starts with the saved corrections already applied")
    func appliesSavedCorrections() {
        var set = CorrectionSet()
        set.setType(.heading(level: 2), for: BlockAnchor(projectConversion().blockSources[0]))
        let model = model(corrections: set)
        #expect(model.conversion.document.blocks[0] == .heading(level: 2, content: ["Title one"]))
        #expect(model.base == projectConversion())
    }

    @Test("a change is applied and saved at once")
    func changeIsSaved() {
        let model = model()
        let anchor = BlockAnchor(projectConversion().blockSources[0])
        model.setType(.heading(level: 1), for: anchor)
        #expect(model.conversion.document.blocks[0] == .heading(level: 1, content: ["Title one"]))
        #expect(storage.saved.last?.type(for: anchor) == .heading(level: 1))
        #expect(model.saveError == nil)
    }

    @Test("a project with no place on disk keeps its corrections in memory only")
    func unsaved() {
        let model = model(at: nil)
        model.setType(.ignored, for: BlockAnchor(projectConversion().blockSources[0]))
        #expect(model.conversion.document.blocks.count == 4)
        #expect(storage.saved.isEmpty)
    }

    @Test("a failed save is reported and the change still stands")
    func saveFailure() {
        storage.saveFailure = StorageFailure()
        let model = model()
        model.setType(.ignored, for: BlockAnchor(projectConversion().blockSources[0]))
        #expect(model.saveError == "disk full")
        #expect(model.conversion.document.blocks.count == 4)
        storage.saveFailure = nil
        model.setType(.ignored, for: BlockAnchor(projectConversion().blockSources[3]))
        #expect(model.saveError == nil)
    }

    @Test("undo takes back the last change, step by step, and saves")
    func undo() {
        let model = model()
        #expect(!model.canUndo)
        let first = BlockAnchor(projectConversion().blockSources[0])
        let second = BlockAnchor(projectConversion().blockSources[3])
        model.setType(.heading(level: 1), for: first)
        model.setType(.heading(level: 1), for: second)
        model.undo()
        #expect(model.corrections.type(for: second) == nil)
        #expect(model.corrections.type(for: first) == .heading(level: 1))
        #expect(storage.saved.last == model.corrections)
        model.undo()
        #expect(model.corrections.isEmpty && !model.canUndo)
        model.undo()
        #expect(model.corrections.isEmpty)
    }

    @Test("redo brings back an undone change, saves, and a new change drops what could be redone")
    func redo() {
        let model = model()
        #expect(!model.canRedo)
        let first = BlockAnchor(projectConversion().blockSources[0])
        let second = BlockAnchor(projectConversion().blockSources[3])
        model.setType(.heading(level: 1), for: first)
        model.setType(.heading(level: 1), for: second)
        model.undo()
        model.undo()
        #expect(model.canRedo)
        model.redo()
        #expect(model.corrections.type(for: first) == .heading(level: 1))
        #expect(model.corrections.type(for: second) == nil)
        #expect(storage.saved.last == model.corrections)
        model.redo()
        #expect(model.corrections.type(for: second) == .heading(level: 1))
        #expect(!model.canRedo)
        model.redo()
        #expect(model.corrections.type(for: second) == .heading(level: 1))
        model.undo()
        model.setType(.heading(level: 2), for: first)
        #expect(!model.canRedo)
    }

    @Test("converting again clears what could be redone")
    func redoClearedByNewBase() {
        let model = model()
        model.setType(.heading(level: 1), for: BlockAnchor(projectConversion().blockSources[0]))
        model.undo()
        model.replaceBase(projectConversion())
        #expect(!model.canRedo)
    }

    @Test("an ignored word is kept lowercased and saved apart from the corrections, and undo leaves it")
    func ignoredWords() {
        let model = model()
        model.ignoreWord("Журавeль")
        #expect(model.ignoredWords == ["журавeль"])
        #expect(storage.savedIgnored.last == ["журавeль"])
        #expect(storage.saved.isEmpty)
        #expect(!model.canUndo)
    }

    @Test("a project opened with ignored words has them")
    func opensWithIgnoredWords() {
        let model = ProjectModel(
            base: projectConversion(), ignoredWords: ["x"], location: location, storage: storage
        )
        #expect(model.ignoredWords == ["x"])
    }

    @Test("a group of types is one step to undo")
    func groupedTypes() {
        let model = model()
        let sources = projectConversion().blockSources
        model.setType(.heading(level: 2), for: [BlockAnchor(sources[0]), BlockAnchor(sources[3])])
        #expect(model.conversion.document.blocks.count {
            if case .heading = $0 {
                true
            } else {
                false
            }
        } == 2)
        model.undo()
        #expect(model.corrections.isEmpty)
    }

    @Test("an edit is recorded against the automatic text, even after earlier word rules")
    func editAgainstAutomaticText() {
        let model = model()
        let anchor = BlockAnchor(projectConversion().blockSources[2])
        model.replaceWord("Журавeль", with: "Журавель")
        #expect(model.conversion.document.blocks[2] == .paragraph(["Журавель is here."]))
        model.setText("Журавель is there.", for: anchor)
        #expect(model.corrections.corrections.contains(.edit(
            anchor,
            from: "Журавeль is here.",
            to: "Журавель is there."
        )))
        #expect(model.conversion.document.blocks[2] == .paragraph(["Журавель is there."]))
    }

    @Test("converting again keeps the corrections, saves the new conversion and reports what no longer applies")
    func replaceBase() {
        let model = model()
        let kept = BlockAnchor(projectConversion().blockSources[0])
        let lost = BlockAnchor(projectConversion().blockSources[3])
        model.setType(.heading(level: 1), for: kept)
        model.setType(.heading(level: 1), for: lost)
        var again = projectConversion()
        again.blockSources[3] = BlockSource(page: 1, box: CGRect(x: 0.1, y: 0.0, width: 0.3, height: 0.04))
        model.replaceBase(again)
        #expect(model.base == again)
        #expect(model.conversion.document.blocks[0] == .heading(level: 1, content: ["Title one"]))
        #expect(model.unapplied == [.retype(lost, to: .heading(level: 1))])
        #expect(storage.replaced == [again])
        #expect(model.canUndo == false)
    }

    @Test("similar blocks leave out the ones the user already decided")
    func similar() {
        let model = model()
        let sources = projectConversion().blockSources
        let reference = BlockAnchor(sources[0])
        model.setType(.heading(level: 1), for: reference)
        #expect(model.similarBlocks(like: reference, thatAre: .paragraph) == [BlockAnchor(sources[3])])
        model.setType(.paragraph, for: BlockAnchor(sources[3]))
        #expect(model.similarBlocks(like: reference, thatAre: .paragraph).isEmpty)
    }
}

@MainActor
@Suite("ProjectModel merging and splitting")
struct ProjectModelStructureTests {
    private let storage = FakeStorage()
    private let location = URL(fileURLWithPath: "/projects/Document.scanproject")
    private let sources = projectConversion().blockSources

    private func model() -> ProjectModel {
        ProjectModel(base: projectConversion(), location: location, storage: storage)
    }

    @Test("merging two blocks changes the document, is saved and can be undone")
    func merge() {
        let model = model()
        #expect(model.merge(BlockAnchor(sources[1]), with: BlockAnchor(sources[2])))
        #expect(model.conversion.document.blocks.count == 4)
        #expect(model.conversion.blockSources[1].areas.map(\.page) == [0, 1])
        #expect(storage.saved.last?.corrections.count == 1)
        model.undo()
        #expect(model.conversion == projectConversion())
        #expect(storage.saved.last?.isEmpty == true)
    }

    @Test("blocks that are not neighbours are not merged and nothing is recorded")
    func mergeRefused() {
        let model = model()
        #expect(!model.merge(BlockAnchor(sources[0]), with: BlockAnchor(sources[2])))
        #expect(!model.canUndo)
    }

    @Test("a split is saved, each part is typed on its own, and undo takes back one step at a time")
    func split() {
        let model = model()
        #expect(model.split(BlockAnchor(sources[3]), at: 6, of: "Title two"))
        let parts = model.conversion.blockSources
        #expect(model.conversion.document.blocks[3] == .paragraph(["Title"]))
        #expect(model.conversion.document.blocks[4] == .paragraph(["two"]))
        model.setType(.heading(level: 2), for: BlockAnchor(parts[4]))
        #expect(model.conversion.document.blocks[4] == .heading(level: 2, content: ["two"]))
        model.undo()
        #expect(model.conversion.document.blocks[4] == .paragraph(["two"]))
        model.undo()
        #expect(model.conversion == projectConversion())
    }

    @Test("a block whose text was edited or replaced, or a text that differs, is not split")
    func splitRefused() {
        let model = model()
        let anchor = BlockAnchor(sources[3])
        #expect(!model.split(anchor, at: 3, of: "Something else"))
        model.setText("Title 2", for: anchor)
        #expect(!model.split(anchor, at: 3, of: "Title 2"))
        #expect(!model.split(anchor, at: 3, of: "Title two"))
    }

    @Test("a text edit after a merge is checked against the merged text and applies")
    func editAfterMerge() {
        let model = model()
        _ = model.merge(BlockAnchor(sources[2]), with: BlockAnchor(sources[3]))
        model.setText("Sample is here. Title two", for: BlockAnchor(sources[2]))
        #expect(model.unapplied.isEmpty)
        #expect(model.conversion.document.blocks[2] == .paragraph(["Sample is here. Title two"]))
    }

    @Test("merges and splits made before converting again apply to the new conversion")
    func survivesNewBase() {
        let model = model()
        _ = model.merge(BlockAnchor(sources[1]), with: BlockAnchor(sources[2]))
        var again = projectConversion()
        again.blockSources = again.blockSources.map { source in
            var moved = source
            moved.start.box = moved.start.box.offsetBy(dx: 0.003, dy: 0.004)
            return moved
        }
        model.replaceBase(again)
        #expect(model.conversion.document.blocks.count == 4)
        #expect(model.unapplied.isEmpty)
    }
}
