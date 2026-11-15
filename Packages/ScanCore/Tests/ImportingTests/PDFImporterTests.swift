import CoreGraphics
import Foundation
import ImageIO
@testable import Importing
import Testing

@Suite("PDFImporter")
struct PDFImporterTests {
    private let importer = PDFImporter()

    private func scratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    /// The colour of the pixel at (`x`, `y`) of the image file, 0...255.
    private func pixel(of url: URL, x: Int, y: Int) throws -> [Int] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return bytes[offset ..< offset + 3].map(Int.init)
    }

    @Test("counts the pages of a PDF")
    func pageCount() throws {
        let pdf = try SyntheticPDF.write(Array(repeating: .init(size: CGSize(width: 100, height: 150)), count: 3))
        defer { try? FileManager.default.removeItem(at: pdf) }
        #expect(try importer.pageCount(of: pdf) == 3)
    }

    @Test("renders one numbered PNG per page, in page order")
    func order() async throws {
        // Each page has a different width, so the order shows in the output.
        let pdf = try SyntheticPDF
            .write((0 ..< 11).map { .init(size: CGSize(width: 72 * CGFloat(2 + $0), height: 72)) })
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let importer = PDFImporter(resolution: 72)
        let urls = try await importer.renderPages(of: pdf, into: folder)
        #expect(urls.count == 11)
        #expect(urls.first?.lastPathComponent == "page-0001.png")
        #expect(urls.last?.lastPathComponent == "page-0011.png")
        let widths = try urls.map { try pixelSize(of: $0).width }
        #expect(widths == (0 ..< 11).map { 72 * (2 + $0) })
        // Sorting by name the way the folder importer does keeps the order.
        #expect(try ImageFolderImporter().pageURLs(in: folder).map(\.lastPathComponent) == urls
            .map(\.lastPathComponent))
    }

    @Test("renders a page without images at the requested resolution")
    func vectorPageResolution() async throws {
        let pdf = try SyntheticPDF.write([.init(size: CGSize(width: 100, height: 150))])
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let urls = try await PDFImporter(resolution: 144).renderPages(of: pdf, into: folder)
        let size = try pixelSize(of: #require(urls.first))
        #expect(size.width == 200 && size.height == 300)
    }

    @Test("renders a page that is one image at the image's own pixel size")
    func nativeResolution() async throws {
        let image = try #require(SyntheticPDF.solidImage(width: 400, height: 600, red: 10, green: 20, blue: 200))
        let pdf = try SyntheticPDF.write([.init(size: CGSize(width: 100, height: 150)) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 150))
        }])
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let urls = try await importer.renderPages(of: pdf, into: folder)
        let size = try pixelSize(of: #require(urls.first))
        #expect(size.width == 400 && size.height == 600)
        // The link colour must survive: no compression, no colour shift.
        let colour = try pixel(of: #require(urls.first), x: 200, y: 300)
        #expect(colour == [10, 20, 200])
    }

    @Test("keeps the image's own pixels when it is placed smaller than the page")
    func placedImage() async throws {
        // 400x600 pixels over a 50x75 point rectangle: 8 pixels per point.
        let image = try #require(SyntheticPDF.solidImage(width: 400, height: 600, red: 200, green: 30, blue: 30))
        let pdf = try SyntheticPDF.write([.init(size: CGSize(width: 100, height: 150)) { context in
            context.draw(image, in: CGRect(x: 25, y: 37.5, width: 50, height: 75))
        }])
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let urls = try await importer.renderPages(of: pdf, into: folder)
        let file = try #require(urls.first)
        let size = try pixelSize(of: file)
        #expect(size.width == 800 && size.height == 1200)
        #expect(try pixel(of: file, x: 400, y: 600) == [200, 30, 30])
        #expect(try pixel(of: file, x: 20, y: 20) == [255, 255, 255])
    }

    @Test("caps the longest side of a page")
    func cap() async throws {
        let pdf = try SyntheticPDF.write([.init(size: CGSize(width: 1000, height: 2000))])
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let urls = try await PDFImporter(resolution: 144, longestSide: 1000).renderPages(of: pdf, into: folder)
        let size = try pixelSize(of: #require(urls.first))
        #expect(size.height == 1000 && size.width == 500)
    }

    @Test("reports progress after each page")
    func progress() async throws {
        let pdf = try SyntheticPDF.write(Array(repeating: .init(size: CGSize(width: 50, height: 50)), count: 3))
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let seen = Lock<[Int]>([])
        _ = try await importer.renderPages(of: pdf, into: folder) { done, total in
            #expect(total == 3)
            seen.mutate { $0.append(done) }
        }
        #expect(seen.value == [1, 2, 3])
    }

    @Test("stops when the task is cancelled")
    func cancellation() async throws {
        let pdf = try SyntheticPDF.write(Array(repeating: .init(size: CGSize(width: 50, height: 50)), count: 20))
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let importer = importer
        let task = Task { try await importer.renderPages(of: pdf, into: folder) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("a file that is not a PDF is reported as unreadable")
    func notAPDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PDFImportError.unreadable(url)) { try importer.pageCount(of: url) }
    }

    @Test("a missing file is reported as unreadable")
    func missing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        #expect(throws: PDFImportError.unreadable(url)) { try importer.pageCount(of: url) }
    }

    @Test("a password-protected PDF is reported as needing a password")
    func locked() throws {
        let pdf = try SyntheticPDF.write([.init(size: CGSize(width: 50, height: 50))], password: "secret")
        defer { try? FileManager.default.removeItem(at: pdf) }
        #expect(throws: PDFImportError.passwordRequired(pdf)) { try importer.pageCount(of: pdf) }
    }

    @Test("tells PDFs from folders by the file extension")
    func detection() {
        #expect(PDFImporter.isPDF(URL(fileURLWithPath: "/a/Document.PDF")))
        #expect(!PDFImporter.isPDF(URL(fileURLWithPath: "/a/document")))
        #expect(!PDFImporter.isPDF(URL(fileURLWithPath: "/a/document.png")))
    }
}

/// A value shared with callbacks that run on other threads.
final class Lock<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func mutate(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}
