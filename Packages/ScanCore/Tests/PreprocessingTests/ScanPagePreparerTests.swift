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

        let prepared = try ScanPagePreparer(folder: output).prepare(pageAt: original, as: .scannedPage)

        #expect(prepared == output.appendingPathComponent("page-0001.png"))
        let bitmap = try #require(ScanImageFile.read(prepared))
        #expect(bitmap.width < 340 && bitmap.height < 440)
        // Cleaned: the grainy paper is white.
        #expect(bitmap.color(x: 21, y: 20) == ScanColor(red: 255, green: 255, blue: 255))
    }

    @Test("levels a skewed scan")
    func levelsSkewedScan() throws {
        let original = try write(SyntheticScans.scan(skew: 2), named: "skewed.png")
        let prepared = try ScanPagePreparer(folder: folder).prepare(pageAt: original, as: .scannedPage)
        let bitmap = try #require(ScanImageFile.read(prepared))
        #expect(abs(Deskew().skewAngle(of: bitmap)) <= 0.15)
    }

    @Test("decides the profile of a document from its pages")
    func profileOfDocument() throws {
        let scans = try (1 ... 3).map { try write(SyntheticScans.scan(), named: "scan-\($0).png") }
        let cleanPages = try (1 ... 3)
            .map { try write(SyntheticScans.cleanPage(statusBar: false), named: "clean-\($0).png") }
        let preparer = ScanPagePreparer(folder: folder)
        #expect(try preparer.profile(ofDocumentWith: scans + [cleanPages[0]]) == .scannedPage)
        #expect(try preparer.profile(ofDocumentWith: cleanPages + [scans[0]]) == .cleanPage)
    }

    @Test("in a scanned document, writes every page, even one that needs no crop")
    func writesEveryPageOfScan() throws {
        let blank = try write(ScanBitmap(width: 100, height: 100, gray: 250), named: "blank.png")
        let output = folder.appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        #expect(try ScanPagePreparer(folder: output).prepare(pageAt: blank, as: .scannedPage)
            == output.appendingPathComponent("blank.png"))
    }

    @Test("in a document of clean pages, returns each page's own file and writes nothing, even for a scan-like page")
    func cleanPageUntouched() throws {
        let original = try write(SyntheticScans.scan(), named: "page.png")
        let output = folder.appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)

        #expect(try ScanPagePreparer(folder: output).prepare(pageAt: original, as: .cleanPage) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test("fails with a clear error for a file that is not an image")
    func unreadable() throws {
        let url = folder.appendingPathComponent("note.png")
        try Data("not an image".utf8).write(to: url)
        #expect(throws: PreprocessingError.unreadableImage(url)) {
            try ScanPagePreparer(folder: folder).prepare(pageAt: url, as: .scannedPage)
        }
    }
}
