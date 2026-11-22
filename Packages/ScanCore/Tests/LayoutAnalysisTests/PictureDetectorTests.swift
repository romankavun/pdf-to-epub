import Foundation
import LayoutAnalysis
import OCR
import Testing

private let paper = PageBitmap.Color(red: 248, green: 248, blue: 248)
private let ink = PageBitmap.Color(red: 20, green: 20, blue: 20)

/// A blank 200 x 400 page; one pixel is 0.005 of the width and 0.0025 of the height.
private func blankPage() -> PageBitmap {
    PageBitmap(width: 200, height: 400, color: paper)
}

/// Compares rectangles with a tolerance, since they come from pixel counts.
private func isClose(_ actual: CGRect, _ expected: CGRect) -> Bool {
    abs(actual.minX - expected.minX) < 0.001 && abs(actual.minY - expected.minY) < 0.001
        && abs(actual.width - expected.width) < 0.001 && abs(actual.height - expected.height) < 0.001
}

@Suite("PictureDetector")
struct PictureDetectorTests {
    private let detector = PictureDetector()

    @Test("a blank page has no pictures")
    func blank() {
        #expect(detector.pictureRegions(in: blankPage()).isEmpty)
    }

    @Test("a tall filled block is a picture, reported in normalized top-left coordinates")
    func solidBlock() throws {
        var page = blankPage()
        page.fill(x: 20, y: 40, width: 100, height: 120, with: ink)
        let regions = detector.pictureRegions(in: page)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3)))
    }

    @Test("rows of text separated by blank rows are not pictures")
    func textRows() {
        var page = blankPage()
        for row in 0 ..< 30 {
            page.fill(x: 10, y: 20 + row * 10, width: 180, height: 6, with: ink)
        }
        #expect(detector.pictureRegions(in: page).isEmpty)
    }

    @Test("an ornament lower than the minimum height is ignored")
    func smallOrnament() {
        var page = blankPage()
        page.fill(x: 80, y: 100, width: 40, height: 12, with: ink)
        #expect(detector.pictureRegions(in: page).isEmpty)
    }

    @Test("a tall band whose ink lies inside recognized text lines is text, not a picture")
    func largeHeading() {
        var page = blankPage()
        // Two touching lines of a large title: 60 rows without a blank row.
        page.fill(x: 20, y: 40, width: 160, height: 60, with: ink)
        let title = [
            TextLine(text: "BIG", box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.075)),
            TextLine(text: "TITLE", box: CGRect(x: 0.1, y: 0.175, width: 0.8, height: 0.075)),
        ]
        #expect(detector.pictureRegions(in: page, lines: title).isEmpty)
    }

    @Test("a picture stays a picture when text is recognized inside it")
    func pictureWithLettering() throws {
        var page = blankPage()
        page.fill(x: 20, y: 40, width: 100, height: 120, with: ink)
        let lettering = [TextLine(text: "SALE", box: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.05))]
        let regions = detector.pictureRegions(in: page, lines: lettering)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3)))
    }

    @Test("a picture on a white ground slightly lighter than the page is found whole")
    func whiteGround() throws {
        var page = blankPage()
        page.fill(x: 20, y: 40, width: 160, height: 100, with: PageBitmap.Color(red: 255, green: 255, blue: 255))
        page.fill(x: 60, y: 70, width: 30, height: 30, with: ink)
        let regions = detector.pictureRegions(in: page)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.25)))
    }

    @Test("pictures separated by blank rows are reported separately, top first")
    func twoPictures() throws {
        var page = blankPage()
        page.fill(x: 20, y: 240, width: 100, height: 80, with: ink)
        page.fill(x: 40, y: 40, width: 100, height: 80, with: ink)
        let regions = detector.pictureRegions(in: page)
        try #require(regions.count == 2)
        #expect(isClose(regions[0], CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.2)))
        #expect(isClose(regions[1], CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.2)))
    }

    @Test("the page background is taken from the border, whatever its colour")
    func darkPage() {
        var page = PageBitmap(width: 200, height: 400, color: ink)
        page.fill(x: 20, y: 40, width: 100, height: 120, with: paper)
        #expect(detector.pictureRegions(in: page).count == 1)
    }

    // Scanned pages: the document page lies on a scanner bed, its edges and the
    // gutter shadow are thin dark lines along the whole page, and the back of
    // the leaf shows through as faint grey text.

    @Test("a thin line along the page edge does not join lines of text into a picture")
    func pageEdge() {
        var page = blankPage()
        for row in 0 ..< 30 {
            page.fill(x: 10, y: 20 + row * 10, width: 170, height: 6, with: ink)
        }
        page.fill(x: 190, y: 10, width: 2, height: 380, with: ink)
        #expect(detector.pictureRegions(in: page).isEmpty)
    }

    @Test("a slanted page edge of a skewed scan is ignored too")
    func slantedPageEdge() {
        var page = blankPage()
        for row in 0 ..< 30 {
            page.fill(x: 10, y: 20 + row * 10, width: 170, height: 6, with: ink)
        }
        for step in 0 ..< 10 {
            page.fill(x: 186 + step, y: 10 + step * 38, width: 3, height: 38, with: ink)
        }
        #expect(detector.pictureRegions(in: page).isEmpty)
    }

    @Test("a page edge broken into short pieces by a faint scan is ignored as a whole")
    func brokenPageEdge() {
        var page = blankPage()
        // Lines of text with two blank rows between them, each bridged by a
        // piece of the edge; the pieces are far lower than a picture.
        for row in 0 ..< 30 {
            page.fill(x: 10, y: 20 + row * 10, width: 170, height: 8, with: ink)
            page.fill(x: 190, y: 27 + row * 10, width: 2, height: 4, with: ink)
        }
        #expect(detector.pictureRegions(in: page).isEmpty)
    }

    @Test("a picture beside a page edge line is found without the line")
    func pictureBesidePageEdge() throws {
        var page = blankPage()
        page.fill(x: 190, y: 0, width: 2, height: 400, with: ink)
        page.fill(x: 20, y: 40, width: 100, height: 120, with: ink)
        let regions = detector.pictureRegions(in: page)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3)))
    }

    @Test("a framed picture of printed text inside the text column stays a picture")
    func framedClipping() throws {
        var page = blankPage()
        var lines: [TextLine] = []
        // Body text above and below, as wide as the column.
        for top in [20, 30, 40, 300, 310, 320] {
            page.fill(x: 10, y: top, width: 180, height: 6, with: ink)
            lines.append(TextLine(
                text: "line", box: CGRect(x: 0.05, y: Double(top) / 400, width: 0.9, height: 6.0 / 400)
            ))
        }
        // A newspaper clipping: a thin frame around rows of small print
        // that the engine does not read. Without its sides the rows would
        // fall apart into bands lower than a picture.
        page.fill(x: 40, y: 100, width: 122, height: 2, with: ink)
        page.fill(x: 40, y: 258, width: 122, height: 2, with: ink)
        page.fill(x: 40, y: 100, width: 2, height: 160, with: ink)
        page.fill(x: 160, y: 100, width: 2, height: 160, with: ink)
        for row in 0 ..< 15 {
            page.fill(x: 46, y: 106 + row * 10, width: 110, height: 5, with: ink)
        }
        let regions = detector.pictureRegions(in: page, lines: lines)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.2, y: 0.25, width: 0.61, height: 0.4)))
    }

    @Test("a framed clipping stays a picture even when the engine reads the print inside it")
    func framedClippingWithReadText() throws {
        var page = blankPage()
        var lines: [TextLine] = []
        func text(x: Int, y: Int, width: Int) {
            page.fill(x: x, y: y, width: width, height: 6, with: ink)
            lines.append(TextLine(text: "line", box: CGRect(
                x: Double(x) / 200, y: Double(y) / 400, width: Double(width) / 200, height: 6.0 / 400
            )))
        }
        for top in [20, 30, 40, 300, 310, 320] {
            text(x: 10, y: top, width: 180)
        }
        page.fill(x: 40, y: 100, width: 2, height: 160, with: ink)
        page.fill(x: 160, y: 100, width: 2, height: 160, with: ink)
        // Lines of print touching each other, all read by the engine.
        for row in 0 ..< 26 {
            text(x: 46, y: 102 + row * 6, width: 110)
        }
        let regions = detector.pictureRegions(in: page, lines: lines)
        try #require(regions.count == 1)
        #expect(isClose(regions[0], CGRect(x: 0.2, y: 0.25, width: 0.61, height: 0.4)))
    }

    @Test("a page edge beside text set in thin strokes is ignored")
    func pageEdgeBesideStrokes() {
        var page = blankPage()
        var lines: [TextLine] = []
        // Glyphs are thin vertical strokes; across the gaps between lines
        // their chains run into the page edge's.
        for row in 0 ..< 30 {
            let top = 20 + row * 10
            for stroke in 0 ..< 34 {
                page.fill(x: 10 + stroke * 5, y: top, width: 2, height: 6, with: ink)
            }
            lines.append(TextLine(
                text: "line", box: CGRect(x: 0.05, y: Double(top) / 400, width: 0.85, height: 6.0 / 400)
            ))
        }
        page.fill(x: 190, y: 10, width: 2, height: 380, with: ink)
        #expect(detector.pictureRegions(in: page, lines: lines).isEmpty)
    }

    @Test("a page edge beside recognized text is ignored")
    func pageEdgeBesideText() {
        var page = blankPage()
        var lines: [TextLine] = []
        for row in 0 ..< 30 {
            page.fill(x: 10, y: 20 + row * 10, width: 170, height: 6, with: ink)
            lines.append(TextLine(
                text: "line", box: CGRect(x: 0.05, y: Double(20 + row * 10) / 400, width: 0.85, height: 6.0 / 400)
            ))
        }
        page.fill(x: 190, y: 10, width: 2, height: 380, with: ink)
        #expect(detector.pictureRegions(in: page, lines: lines).isEmpty)
    }

    @Test("faint show-through around recognized text does not make the text a picture")
    func showThrough() {
        var page = blankPage()
        let faint = PageBitmap.Color(red: 238, green: 238, blue: 238)
        var lines: [TextLine] = []
        // Real text, its blank rows bridged by faint specks.
        for row in 0 ..< 20 {
            let top = 20 + row * 10
            page.fill(x: 10, y: top, width: 180, height: 6, with: ink)
            page.fill(x: 10, y: top + 6, width: 180, height: 4, with: faint)
            lines.append(TextLine(
                text: "line", box: CGRect(x: 0.05, y: Double(top) / 400, width: 0.9, height: 6.0 / 400)
            ))
        }
        // Text from the back of the leaf, which the OCR engine does not read.
        for row in 0 ..< 15 {
            page.fill(x: 10, y: 220 + row * 10, width: 180, height: 10, with: faint)
        }
        #expect(detector.pictureRegions(in: page, lines: lines).isEmpty)
    }

    @Test("a bitmap rejects pixel data of the wrong size")
    func bitmapSize() {
        #expect(PageBitmap(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 15)) == nil)
        #expect(PageBitmap(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 16)) != nil)
    }
}
