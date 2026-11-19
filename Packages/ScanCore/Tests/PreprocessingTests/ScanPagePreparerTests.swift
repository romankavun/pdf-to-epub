import Foundation
import Preprocessing
import Testing

@Suite("ScanPagePreparer")
struct ScanPagePreparerTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanPagePreparerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func write(_ bitmap: ScanBitmap, named name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try #require(ScanImageFile.writePNG(bitmap, to: url))
        return url
    }

    @Test("a page written and read back keeps its exact pixels")
    func roundTrip() throws {
        let scan = SyntheticScans.scan(width: 120, height: 160, page: .init(x: 30, y: 40, width: 60, height: 80))
        let url = try write(scan, named: "round.png")
        #expect(ScanImageFile.read(url) == scan)
    }

    @Test("writes a cropped scan into the folder under the page's name")
    func writesPreparedScan() throws {
        let original = try write(SyntheticScans.scan(), named: "page-0001.png")
        let output = folder.appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)

        let prepared = try ScanPagePreparer(folder: output).prepare(pageAt: original)

        #expect(prepared == output.appendingPathComponent("page-0001.png"))
        let bitmap = try #require(ScanImageFile.read(prepared))
        #expect(bitmap.width < 340 && bitmap.height < 440)
    }

    @Test("returns a clean page's own file and writes nothing")
    func cleanPageUntouched() throws {
        let original = try write(SyntheticScans.cleanPage(), named: "shot.png")
        let output = folder.appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)

        #expect(try ScanPagePreparer(folder: output).prepare(pageAt: original) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test("fails with a clear error for a file that is not an image")
    func unreadable() throws {
        let url = folder.appendingPathComponent("note.png")
        try Data("not an image".utf8).write(to: url)
        #expect(throws: PreprocessingError.unreadableImage(url)) {
            try ScanPagePreparer(folder: folder).prepare(pageAt: url)
        }
    }
}
