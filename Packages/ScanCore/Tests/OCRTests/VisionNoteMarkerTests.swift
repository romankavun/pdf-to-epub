import AppKit
import Foundation
import OCR
import Testing

/// A page with one line of black text that carries two blue note markers.
private struct MarkedPage {
    var url: URL
    /// Marker boxes, normalized, origin top-left, left to right.
    var markers: [CGRect]
}

/// Draws `pieces` one after another on a line; pieces flagged `true` are
/// drawn in link blue and reported as markers.
private func renderLine(_ pieces: [(String, Bool)]) throws -> MarkedPage {
    let width = 1600, height = 400
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
    let font = NSFont(name: "Times New Roman", size: 48) ?? .systemFont(ofSize: 48)
    let blue = NSColor(deviceRed: 0.42, green: 0.51, blue: 0.98, alpha: 1)
    var x: CGFloat = 100
    var markers: [CGRect] = []
    for (text, isMarker) in pieces {
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: isMarker ? blue : NSColor.black,
        ])
        string.draw(at: NSPoint(x: x, y: 150))
        let size = string.size()
        if isMarker {
            markers.append(CGRect(
                x: x / CGFloat(width), y: 150 / CGFloat(height),
                width: size.width / CGFloat(width), height: size.height / CGFloat(height)
            ))
        }
        x += size.width
    }
    NSGraphicsContext.restoreGraphicsState()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return MarkedPage(url: url, markers: markers)
}

/// Integration tests against the real Vision framework; tolerant on purpose.
@Suite("VisionOCREngine note markers")
struct VisionNoteMarkerTests {
    private let pieces: [(String, Bool)] = [
        ("Перший рядок тексту", false), ("23", true), (" і продовження рядка", false), ("456", true),
        (" до кінця.", false),
    ]

    @Test("reports the words of a line with their boxes, left to right", .timeLimit(.minutes(5)))
    func words() async throws {
        let page = try renderLine(pieces)
        defer { try? FileManager.default.removeItem(at: page.url) }

        let line = try #require(await VisionOCREngine().recognize(imageAt: page.url).lines.first)
        #expect(line.words.count >= 6)
        #expect(line.words.map(\.text).joined(separator: " ") == line.text)
        #expect(zip(line.words, line.words.dropFirst()).allSatisfy { $0.box.minX < $1.box.minX })
        #expect(line.words.allSatisfy { $0.box.minX >= line.box.minX - 0.01 && $0.box.maxX <= line.box.maxX + 0.01 })
    }

    @Test("erased regions do not reach the recognized text", .timeLimit(.minutes(5)))
    func erasing() async throws {
        let page = try renderLine(pieces)
        defer { try? FileManager.default.removeItem(at: page.url) }

        let engine = VisionOCREngine()
        let plain = try await engine.recognize(imageAt: page.url).lines.map(\.text).joined(separator: " ")
        let erased = try await engine.recognize(imageAt: page.url, erasing: page.markers)
            .lines.map(\.text).joined(separator: " ")
        #expect(plain.contains("456"))
        #expect(!erased.contains("23") && !erased.contains("456"))
        #expect(erased.contains("продовження") && erased.contains("кінця"))
    }

    @Test("reads the labels in the given regions, in order", .timeLimit(.minutes(5)))
    func labels() async throws {
        let page = try renderLine(pieces)
        defer { try? FileManager.default.removeItem(at: page.url) }

        let labels = try await VisionOCREngine().readLabels(inImageAt: page.url, regions: page.markers)
        #expect(labels == ["23", "456"])
        #expect(try await VisionOCREngine().readLabels(inImageAt: page.url, regions: []).isEmpty)
    }

    @Test("label reading fails with a clear error for a file that is not an image")
    func unreadableImage() async {
        let url = URL(fileURLWithPath: "/nonexistent/page.png")
        await #expect(throws: OCRError.unreadableImage(url)) {
            try await VisionOCREngine().readLabels(
                inImageAt: url,
                regions: [CGRect(x: 0, y: 0, width: 0.1, height: 0.1)]
            )
        }
    }
}
