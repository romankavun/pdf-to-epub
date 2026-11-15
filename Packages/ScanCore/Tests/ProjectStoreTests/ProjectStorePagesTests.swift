import Conversion
import DocumentModel
import Foundation
import ProjectStore
import Testing

/// A conversion of `count` pages whose images are files in `folder`.
private func conversion(withPagesIn folder: URL, count: Int = 2) throws -> Conversion {
    var urls: [URL] = []
    for number in 1 ... count {
        let url = folder.appendingPathComponent("page-000\(number).png")
        try Data("page \(number)".utf8).write(to: url)
        urls.append(url)
    }
    let document = Document(
        metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"),
        chapters: [Chapter(title: "One", blocks: [.paragraph(["Text"])])]
    )
    return Conversion(document: document, pageURLs: urls)
}

private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Suite("ProjectStore pages")
struct ProjectStorePagesTests {
    private let store = ProjectStore()

    @Test("moves rendered pages into the bundle and points the conversion at them")
    func movesPages() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let staging = folder.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bundle = folder.appendingPathComponent("Document.scanproject")

        let stored = try store.create(conversion(withPagesIn: staging), at: bundle, movingPages: true)

        #expect(stored.pageURLs.map(\.lastPathComponent) == ["page-0001.png", "page-0002.png"])
        for url in stored.pageURLs {
            #expect(url.deletingLastPathComponent().resolvingSymlinksInPath()
                == bundle.appendingPathComponent("pages").resolvingSymlinksInPath())
        }
        #expect(try String(contentsOf: stored.pageURLs[1], encoding: .utf8) == "page 2")
        #expect(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("page-0001.png").path))
    }

    @Test("a loaded project finds its pages after the bundle was moved")
    func pagesFollowTheBundle() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let staging = folder.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bundle = folder.appendingPathComponent("Document.scanproject")
        try store.create(conversion(withPagesIn: staging), at: bundle, movingPages: true)

        let moved = folder.appendingPathComponent("Elsewhere.scanproject")
        try FileManager.default.moveItem(at: bundle, to: moved)
        let loaded = try store.load(from: moved)

        #expect(loaded.conversion.pageURLs.count == 2)
        for url in loaded.conversion.pageURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url.resolvingSymlinksInPath().path.hasPrefix(moved.resolvingSymlinksInPath().path))
        }
    }

    @Test("converting again keeps the pages the bundle holds")
    func replaceKeepsPages() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let staging = folder.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bundle = folder.appendingPathComponent("Document.scanproject")
        let stored = try store.create(conversion(withPagesIn: staging), at: bundle, movingPages: true)

        try store.replaceConversion(in: bundle, with: stored)
        let loaded = try store.load(from: bundle)

        #expect(loaded.conversion.pageURLs.map(\.lastPathComponent) == ["page-0001.png", "page-0002.png"])
        #expect(loaded.conversion.pageURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("pages that were not moved stay where they are")
    func scansStayInPlace() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scans = folder.appendingPathComponent("scans")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        let bundle = folder.appendingPathComponent("Document.scanproject")
        let source = try conversion(withPagesIn: scans)

        try store.create(source, at: bundle)

        #expect(try store.load(from: bundle).conversion.pageURLs == source.pageURLs)
        #expect(!FileManager.default.fileExists(atPath: bundle.appendingPathComponent("pages").path))
    }

    @Test("nothing is left behind when a page cannot be moved")
    func failedMoveLeavesNothing() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = folder.appendingPathComponent("Document.scanproject")
        let missing = Conversion(
            document: Document(
                metadata: DocumentMetadata(identifier: "urn:test", title: "T", author: nil, language: "uk"), chapters: []
            ),
            pageURLs: [folder.appendingPathComponent("gone.png")]
        )

        #expect(throws: (any Error).self) { try store.create(missing, at: bundle, movingPages: true) }
        #expect(!FileManager.default.fileExists(atPath: bundle.path))
    }
}
