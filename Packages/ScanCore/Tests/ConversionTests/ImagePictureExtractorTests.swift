import Conversion
import CoreGraphics
import Foundation
import ImageIO
import OCR
import Testing
import UniformTypeIdentifiers

/// Draws a light page with one dark rectangle and saves it as a PNG.
/// `picture` is in pixels from the top-left corner.
private func writePage(width: Int, height: Int, picture: CGRect) throws -> URL {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
    // Core Graphics counts y from the bottom.
    context.fill(CGRect(
        x: picture.minX, y: CGFloat(height) - picture.maxY, width: picture.width, height: picture.height
    ))
    let image = try #require(context.makeImage())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return url
}

@Suite("ImagePictureExtractor")
struct ImagePictureExtractorTests {
    @Test("crops a picture out of a page image at full resolution as PNG")
    func cropsPicture() throws {
        let url = try writePage(width: 400, height: 600, picture: CGRect(x: 40, y: 60, width: 200, height: 240))
        defer { try? FileManager.default.removeItem(at: url) }

        let pictures = try ImagePictureExtractor().pictures(inImageAt: url, lines: [])
        try #require(pictures.count == 1)
        let box = pictures[0].box
        #expect(abs(box.minX - 0.1) < 0.005 && abs(box.minY - 0.1) < 0.005)
        #expect(abs(box.width - 0.5) < 0.005 && abs(box.height - 0.4) < 0.005)

        let source = try #require(CGImageSourceCreateWithData(pictures[0].pngData as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let crop = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(abs(crop.width - 200) <= 2 && abs(crop.height - 240) <= 2)
    }

    @Test("a page without pictures gives none")
    func noPictures() throws {
        let url = try writePage(width: 400, height: 600, picture: .zero)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ImagePictureExtractor().pictures(inImageAt: url, lines: []).isEmpty)
    }

    @Test("fails with a clear error for a file that is not an image")
    func unreadableImage() {
        let url = URL(fileURLWithPath: "/nonexistent/page.png")
        #expect(throws: PictureExtractionError.unreadableImage(url)) {
            try ImagePictureExtractor().pictures(inImageAt: url, lines: [])
        }
    }
}
