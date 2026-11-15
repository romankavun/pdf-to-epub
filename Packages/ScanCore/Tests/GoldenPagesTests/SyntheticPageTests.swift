import Conversion
import Foundation
import Testing
import TestSupport

@Suite("SyntheticPage")
struct SyntheticPageTests {
    private func render(_ page: SyntheticPage) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try page.writePNG(to: url)
        return url
    }

    @Test("note markers written as {label} are drawn in link blue and found by the marker locator")
    func markersAreDetected() throws {
        let url = try render(SyntheticPage([.line("A sentence with a note{1} and another{2} one."), .line("Plain.")]))
        defer { try? FileManager.default.removeItem(at: url) }
        let boxes = try ImageNoteMarkerLocator().markers(inImageAt: url)
        #expect(boxes.count == 2)
        #expect(boxes[0].minX < boxes[1].minX)
    }

    @Test("a page without markers has none detected, whatever else is on it")
    func noMarkersWithoutLabels() throws {
        let url = try render(SyntheticPage([
            .heading("Title"), .line("Body text."), .picture(height: 0.2, caption: "A caption"), .rule,
            .pageNumber("7"),
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ImageNoteMarkerLocator().markers(inImageAt: url).isEmpty)
    }

    @Test("the picture band is found as an illustration")
    func pictureIsDetected() throws {
        let url = try render(SyntheticPage([
            .line("Text above."), .picture(height: 0.25, caption: "Caption"), .line("Text below."),
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        let pictures = try ImagePictureExtractor().pictures(inImageAt: url, lines: [])
        #expect(pictures.count == 1)
        #expect(pictures.first.map { $0.box.height > 0.2 } == true)
    }
}

@Suite("TextSimilarity")
struct TextSimilarityTests {
    @Test("identical text, differing only in case and spacing, matches")
    func identical() {
        #expect(TextSimilarity.matches("Hello  World", "hello world", threshold: 1))
    }

    @Test("a few misread characters are tolerated; different text is not")
    func tolerance() {
        #expect(TextSimilarity.matches("The quick brown fox jumps", "The qu1ck brown f0x jumps", threshold: 0.85))
        #expect(!TextSimilarity.matches("The quick brown fox jumps", "Something else entirely", threshold: 0.85))
    }
}
