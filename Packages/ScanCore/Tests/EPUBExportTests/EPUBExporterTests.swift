import DocumentModel
@testable import EPUBExport
import Foundation
import Testing

@Suite("EPUBExporter")
struct EPUBExporterTests {
    private let exporter = EPUBExporter()
    private let modified = Date(timeIntervalSince1970: 1_767_323_045)

    private func entries(_ document: Document = Fixtures.document) throws -> [ZipEntry] {
        try exporter.entries(for: document, modified: modified)
    }

    private func text(_ path: String) throws -> String {
        let entry = try #require(try entries().first { $0.path == path })
        return String(decoding: entry.data, as: UTF8.self)
    }

    @Test("lays out the container with the mimetype first and uncompressed")
    func layout() throws {
        let entries = try entries()
        #expect(entries.map(\.path) == [
            "mimetype",
            "META-INF/container.xml",
            "EPUB/package.opf",
            "EPUB/nav.xhtml",
            "EPUB/style.css",
            "EPUB/chapter-001.xhtml",
            "EPUB/chapter-002.xhtml",
            "EPUB/images/cover.png",
            "EPUB/images/fig-001.png",
        ])
        #expect(entries[0].data == Data("application/epub+zip".utf8))
        #expect(entries[0].compress == false)
        #expect(entries.last?.data == Fixtures.pngData)
    }

    @Test("container.xml points at the package document")
    func container() throws {
        #expect(try text("META-INF/container.xml").contains(
            "<rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\"/>"
        ))
    }

    @Test("writes each chapter's own content")
    func chapters() throws {
        #expect(try text("EPUB/chapter-001.xhtml").contains("<h2>Details</h2>"))
        #expect(try text("EPUB/chapter-002.xhtml").contains("No notes here."))
    }

    @Test("rejects documents that cannot become a valid EPUB")
    func invalidDocuments() {
        var noChapters = Fixtures.document
        noChapters.chapters = []
        #expect(throws: EPUBExportError.noChapters) { try entries(noChapters) }

        var noCover = Fixtures.document
        noCover.coverImageID = "ghost"
        #expect(throws: EPUBExportError.missingImage(id: "ghost")) { try entries(noCover) }

        var clash = Fixtures.document
        clash.images.append(ImageResource(id: "other", filename: "cover.png", mediaType: "image/png", data: Data()))
        #expect(throws: EPUBExportError.duplicateImageFilename("cover.png")) { try entries(clash) }

        var dangling = Fixtures.document
        dangling.notes = []
        #expect(throws: EPUBExportError.missingNote(id: "n1")) { try entries(dangling) }
    }

    @Test("every XML file in the container is well formed")
    func wellFormedXML() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for entry in try entries() where ["xml", "opf", "xhtml"].contains((entry.path as NSString).pathExtension) {
            let file = directory.appendingPathComponent(entry.path.replacingOccurrences(of: "/", with: "_"))
            try entry.data.write(to: file)
            let result = try Shell.run("/usr/bin/xmllint", ["--noout", file.path])
            #expect(result.status == 0, "\(entry.path): \(String(decoding: result.output, as: UTF8.self))")
        }
    }

    @Test("writes a readable archive to disk, replacing an existing file")
    func exportToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old".utf8).write(to: url)
        try exporter.export(Fixtures.document, to: url, modified: modified)
        let result = try Shell.run("/usr/bin/unzip", ["-tq", url.path])
        #expect(result.status == 0, "\(String(decoding: result.output, as: UTF8.self))")
    }

    /// Full conformance check. Skipped when epubcheck is not installed
    /// (`brew install epubcheck`).
    @Test("passes epubcheck", .enabled(if: EPUBCheck.path != nil, "epubcheck is not installed"))
    func epubcheck() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try exporter.export(Fixtures.document, to: url, modified: modified)
        let result = try Shell.run(#require(EPUBCheck.path), ["--failonwarnings", url.path])
        #expect(result.status == 0, "\(String(decoding: result.output, as: UTF8.self))")
    }
}

enum EPUBCheck {
    /// Location of the epubcheck launcher, if installed via Homebrew.
    static let path: String? = ["/opt/homebrew/bin/epubcheck", "/usr/local/bin/epubcheck"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}
