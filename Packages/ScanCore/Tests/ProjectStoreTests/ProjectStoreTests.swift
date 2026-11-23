import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import ProjectStore
import Testing

private func sampleConversion(imageBytes: [UInt8] = [1, 2, 3], title: String = "T") -> Conversion {
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: title, author: "A", language: "uk"),
        chapters: [Chapter(title: "One", blocks: [
            .heading(level: 1, content: ["One"]),
            .paragraph(["Text", .noteReference("note-1"), .emphasis(" more")]),
            .figure(Figure(imageID: "figure-001", alternativeText: "", caption: ["Fig."])),
        ])],
        notes: [Note(id: "note-1", label: "1", content: ["Note."])],
        images: [ImageResource(
            id: "figure-001",
            filename: "figure-001.png",
            mediaType: "image/png",
            data: Data(imageBytes)
        )],
        coverImageID: "figure-001"
    )
    return Conversion(
        document: document,
        unlinkedReferences: 2,
        unlinkedNotes: 1,
        pageURLs: [URL(fileURLWithPath: "/scans/1.png"), URL(fileURLWithPath: "/scans/2.png")],
        blockSources: (0 ..< 3).map { BlockSource(
            page: 0,
            box: CGRect(x: 0.1, y: 0.2 * Double($0), width: 0.8, height: 0.1)
        ) },
        noteSources: [BlockSource(page: 1, box: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1))],
        styles: BlockStyles(
            blocks: [
                BlockStyle(rule: .largerThanText, lineHeight: 1.8, ink: 1.1, alignment: .centered, width: 0.4),
                BlockStyle(rule: .paragraph, alignment: .indented, lineCount: 4, spaceAbove: 2.5, spaceBelow: 1),
                BlockStyle(rule: .captionByLabel, width: 0.3, isUnderPicture: true),
            ],
            notes: [BlockStyle(rule: .noteText, lineHeight: 0.8, zone: .bottom, opensWithNoteLabel: true)],
            pageFurniture: [PageFurniture(
                area: PageArea(page: 1, box: CGRect(x: 0.45, y: 0.95, width: 0.1, height: 0.02)), text: "12",
                style: BlockStyle(rule: .pageNumber, width: 0.1, zone: .bottom)
            )]
        )
    )
}

private func sampleCorrections() -> CorrectionSet {
    var set = CorrectionSet()
    set.setType(.heading(level: 2), for: BlockAnchor(page: 0, box: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.1)))
    set.replaceWord("a", with: "b")
    set.merge(
        BlockAnchor(page: 0, box: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.1)),
        with: BlockAnchor(page: 1, box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1)),
        texts: ("", "")
    )
    set.split(BlockAnchor(page: 1, box: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.1)), at: 4, of: "One two three.")
    return set
}

/// Each test gets an empty folder to put the project in, removed afterwards.
private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    return try body(folder)
}

@Suite("ProjectStore")
struct ProjectStoreTests {
    private let store = ProjectStore()

    @Test("a created project loads back with the same conversion and no corrections")
    func roundTrip() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            let conversion = sampleConversion()
            try store.create(conversion, at: url)
            let project = try store.load(from: url)
            #expect(project.conversion == conversion)
            #expect(project.corrections.isEmpty)
            #expect(store.isProject(at: url))
        }
    }

    @Test("images are files in the bundle, not part of the JSON")
    func imagesAreFiles() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(imageBytes: [9, 8, 7]), at: url)
            #expect(try Data(contentsOf: url.appendingPathComponent("images/figure-001.png")) == Data([9, 8, 7]))
            let json = try String(contentsOf: url.appendingPathComponent("project.json"), encoding: .utf8)
            #expect(!json.contains("CQgH")) // base64 of 9, 8, 7
        }
    }

    @Test("saved corrections, merges and splits come back with the project")
    func savesCorrections() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(), at: url)
            try store.save(sampleCorrections(), to: url)
            #expect(try store.load(from: url).corrections == sampleCorrections())
        }
    }

    @Test("ignored words come back with the project")
    func savesIgnoredWords() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(), at: url)
            #expect(try store.load(from: url).ignoredWords.isEmpty)
            try store.save(ignoredWords: ["бо", "abc"], to: url)
            #expect(try store.load(from: url).ignoredWords == ["бо", "abc"])
        }
    }

    @Test("creating over an existing item fails and leaves it alone")
    func refusesToOverwrite() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("keep".utf8).write(to: url.appendingPathComponent("note.txt"))
            #expect(throws: ProjectStoreError.alreadyExists) { try store.create(sampleConversion(), at: url) }
            #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("note.txt").path))
        }
    }

    @Test("a folder without a project file is not a project")
    func notAProject() throws {
        try withFolder { folder in
            #expect(!store.isProject(at: folder))
            #expect(throws: ProjectStoreError.notAProject) { try store.load(from: folder) }
        }
    }

    @Test("a project from a newer format is refused")
    func newerFormat() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(), at: url)
            let file = url.appendingPathComponent("project.json")
            let json = try String(contentsOf: file, encoding: .utf8)
                .replacingOccurrences(of: "\"formatVersion\" : 2", with: "\"formatVersion\" : 99")
            try Data(json.utf8).write(to: file)
            #expect(throws: ProjectStoreError.unsupportedVersion(99)) { try store.load(from: url) }
        }
    }

    @Test("the styles of a conversion come back with the project")
    func stylesRoundTrip() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            let conversion = sampleConversion()
            try store.create(conversion, at: url)
            #expect(try store.load(from: url).conversion.styles == conversion.styles)
            #expect(conversion.styles != nil)
        }
    }

    @Test("a version 1 project, written before styles were kept, loads without styles")
    func versionOne() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(), at: url)
            let file = url.appendingPathComponent("project.json")
            var json = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            )
            json["formatVersion"] = 1
            json["styles"] = nil
            try JSONSerialization.data(withJSONObject: json).write(to: file)

            let conversion = try store.load(from: url).conversion
            #expect(conversion.styles == nil)
            #expect(conversion.document == sampleConversion().document)
        }
    }

    @Test("a missing image file makes the project damaged")
    func damaged() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("Document.scanproject")
            try store.create(sampleConversion(), at: url)
            try FileManager.default.removeItem(at: url.appendingPathComponent("images/figure-001.png"))
            #expect(throws: ProjectStoreError.self) { try store.load(from: url) }
        }
    }

    @Test("an image name that leaves the images folder is refused")
    func unsafeImageName() throws {
        try withFolder { folder in
            var conversion = sampleConversion()
            conversion.document.images[0].filename = "../evil.png"
            let url = folder.appendingPathComponent("Document.scanproject")
            #expect(throws: ProjectStoreError.invalidImageName("../evil.png")) { try store.create(conversion, at: url) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("evil.png").path))
        }
    }
}
