import Foundation
import Importing
import Testing

@Suite("ImageFolderImporter")
struct ImageFolderImporterTests {
    private let importer = ImageFolderImporter()

    /// Creates a temporary folder holding empty files with the given names.
    private func folder(_ names: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names {
            let file = url.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: file)
        }
        return url
    }

    @Test("orders pages by the numbers in their names, not alphabetically")
    func naturalOrder() throws {
        let url = try folder(["shot_10.png", "shot_2.png", "shot_1.png", "shot_100.png"])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try importer.pageURLs(in: url).map(\.lastPathComponent) == [
            "shot_1.png",
            "shot_2.png",
            "shot_10.png",
            "shot_100.png",
        ])
    }

    @Test("keeps image files of any supported type and ignores everything else")
    func filtersFiles() throws {
        let url = try folder([
            "a.PNG",
            "b.jpg",
            "c.jpeg",
            "d.tiff",
            "e.heic",
            "notes.txt",
            ".DS_Store",
            ".hidden.png",
            "sub/f.png",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try importer.pageURLs(in: url).map(\.lastPathComponent) == [
            "a.PNG",
            "b.jpg",
            "c.jpeg",
            "d.tiff",
            "e.heic",
        ])
    }

    @Test("fails clearly when the folder is missing or has no images")
    func failures() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        #expect(throws: ImportError.notADirectory(missing)) { try importer.pageURLs(in: missing) }
        let url = try folder(["readme.txt"])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ImportError.noImages(url)) { try importer.pageURLs(in: url) }
    }
}
