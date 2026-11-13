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

    @Test("a bitmap rejects pixel data of the wrong size")
    func bitmapSize() {
        #expect(PageBitmap(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 15)) == nil)
        #expect(PageBitmap(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 16)) != nil)
    }
}
