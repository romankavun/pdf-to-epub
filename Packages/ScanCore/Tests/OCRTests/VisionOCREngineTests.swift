import AppKit
import Foundation
import OCR
import Testing

/// Integration tests against the real Vision framework. Assertions are
/// tolerant on purpose: exact OCR output can change between OS releases.
@Suite("VisionOCREngine")
struct VisionOCREngineTests {
    /// Draws black text lines on a white page and saves it as a PNG.
    /// `lines` are (text, font size, top in pixels).
    private func renderPage(_ lines: [(String, CGFloat, CGFloat)]) throws -> URL {
        let width = 1600, height = 1000
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let bitmap = try #require(NSGraphicsContext(bitmapImageRep: rep))
        bitmap.cgContext.translateBy(x: 0, y: CGFloat(height))
        bitmap.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap.cgContext, flipped: true)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (text, size, top) in lines {
            NSAttributedString(string: text, attributes: [
                .font: NSFont(name: "Times New Roman", size: size) ?? .systemFont(ofSize: size),
                .foregroundColor: NSColor.black,
            ]).draw(at: NSPoint(x: 100, y: top))
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    @Test("reads Ukrainian and English lines with top-left based positions", .timeLimit(.minutes(5)))
    func recognizesLines() async throws {
        let url = try renderPage([
            ("Велика назва", 90, 100),
            ("Перший рядок звичайного тексту на сторінці.", 48, 400),
            ("A second line written in English.", 48, 500),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let page = try await VisionOCREngine().recognize(imageAt: url)
        let lines = page.lines.sorted { $0.box.minY < $1.box.minY }
        try #require(lines.count == 3)
        #expect(lines[0].text.contains("назва"))
        #expect(lines[1].text.contains("звичайного"))
        #expect(lines[2].text.contains("English"))
        // The title was drawn at the top, so it must have the smallest y.
        #expect(lines[0].box.minY < 0.3)
        #expect(lines[2].box.minY > 0.4)
        #expect(lines[0].box.height > 1.5 * lines[1].box.height)
        #expect(lines.allSatisfy { $0.box.minX > 0.03 && $0.box.maxX <= 1 && $0.confidence > 0 })
    }

    @Test("fails with a clear error for a file that is not an image")
    func unreadableImage() async {
        let url = URL(fileURLWithPath: "/nonexistent/page.png")
        await #expect(throws: OCRError.unreadableImage(url)) {
            try await VisionOCREngine().recognize(imageAt: url)
        }
    }
}
