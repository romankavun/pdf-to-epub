import Foundation
import LayoutAnalysis
import Testing

private let paper = PageBitmap.Color(red: 248, green: 248, blue: 248)
private let ink = PageBitmap.Color(red: 20, green: 20, blue: 20)
private let link = PageBitmap.Color(red: 108, green: 131, blue: 249)

/// A blank 400 x 400 page; one pixel is 0.0025 of each side.
private func blankPage() -> PageBitmap {
    PageBitmap(width: 400, height: 400, color: paper)
}

private func isClose(_ actual: CGRect, _ expected: CGRect) -> Bool {
    abs(actual.minX - expected.minX) < 0.001 && abs(actual.minY - expected.minY) < 0.001
        && abs(actual.width - expected.width) < 0.001 && abs(actual.height - expected.height) < 0.001
}

@Suite("NoteMarkerDetector")
struct NoteMarkerDetectorTests {
    private let detector = NoteMarkerDetector()

    @Test("a page without link-coloured ink has no markers")
    func noLinkColour() {
        var page = blankPage()
        page.fill(x: 40, y: 100, width: 300, height: 10, with: ink)
        #expect(detector.markerRegions(in: blankPage()).isEmpty)
        #expect(detector.markerRegions(in: page).isEmpty)
    }

    @Test("a small link-coloured token right after a word is a marker")
    func referenceAfterWord() throws {
        var page = blankPage()
        page.fill(x: 40, y: 100, width: 100, height: 10, with: ink)
        page.fill(x: 142, y: 98, width: 8, height: 8, with: link)
        let regions = detector.markerRegions(in: page)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.355, y: 0.245, width: 0.02, height: 0.02)))
    }

    @Test("a link-coloured token at the start of a line of text is a marker")
    func labelBeforeText() {
        var page = blankPage()
        page.fill(x: 40, y: 100, width: 8, height: 10, with: link)
        page.fill(x: 52, y: 100, width: 200, height: 10, with: ink)
        #expect(detector.markerRegions(in: page).count == 1)
    }

    @Test("a line set entirely in the link colour is a link, not a marker")
    func linkLine() {
        var page = blankPage()
        // A long contents entry and a one-word entry.
        page.fill(x: 40, y: 100, width: 200, height: 10, with: link)
        page.fill(x: 40, y: 130, width: 24, height: 10, with: link)
        #expect(detector.markerRegions(in: page).isEmpty)
    }

    @Test("a long link-coloured run inside a line of text is a link, not a marker")
    func inlineLink() {
        var page = blankPage()
        page.fill(x: 40, y: 100, width: 100, height: 10, with: ink)
        page.fill(x: 144, y: 100, width: 80, height: 10, with: link)
        #expect(detector.markerRegions(in: page).isEmpty)
    }

    @Test("markers are reported top to bottom, then left to right")
    func order() throws {
        var page = blankPage()
        page.fill(x: 40, y: 200, width: 100, height: 10, with: ink)
        page.fill(x: 142, y: 200, width: 8, height: 10, with: link)
        page.fill(x: 40, y: 100, width: 300, height: 10, with: ink)
        page.fill(x: 250, y: 98, width: 8, height: 8, with: link)
        page.fill(x: 100, y: 98, width: 8, height: 8, with: link)
        let regions = detector.markerRegions(in: page)
        try #require(regions.count == 3)
        #expect(regions.map { Int(($0.minX * 400).rounded()) } == [100, 250, 142])
    }

    @Test("stray coloured pixels are ignored")
    func specks() {
        var page = blankPage()
        page.fill(x: 40, y: 100, width: 100, height: 10, with: ink)
        page.fill(x: 142, y: 100, width: 1, height: 1, with: link)
        #expect(detector.markerRegions(in: page).isEmpty)
    }
}
