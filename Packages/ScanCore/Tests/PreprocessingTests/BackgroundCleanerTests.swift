import Preprocessing
import Testing

/// A cropped scanned page: grainy paper of `paper` brightness with text
/// lines from x 60 to 340, 12 px tall every 24 px, from y 60 to 440.
private func page(width: Int = 400, height: Int = 500, paper: UInt8 = 252) -> ScanBitmap {
    var bitmap = ScanBitmap(width: width, height: height, gray: paper)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let grain = SyntheticScans.paperTone(x: x, y: y) - 251
            bitmap.setGray(paper - 4 + grain, x: x, y: y)
        }
    }
    var top = 60
    while top + 12 <= 440 {
        bitmap.fill(.init(x: 60, y: top, width: 280, height: 12), gray: 30)
        top += 24
    }
    return bitmap
}

private func gray(_ bitmap: ScanBitmap, _ x: Int, _ y: Int) -> Int {
    let color = bitmap.color(x: x, y: y)
    return (Int(color.red) + Int(color.green) + Int(color.blue)) / 3
}

@Suite("BackgroundCleaner")
struct BackgroundCleanerTests {
    @Test("turns grainy paper white and keeps text dark")
    func whitensPaper() {
        let cleaned = BackgroundCleaner().cleaned(page())
        #expect(gray(cleaned, 30, 30) == 255)
        #expect(gray(cleaned, 200, 450) == 255)
        #expect(gray(cleaned, 100, 66) < 60)
    }

    @Test("evens out yellowed paper to white without washing out the text")
    func yellowedPaper() {
        var bitmap = page(paper: 228)
        for y in 0 ..< bitmap.height {
            for x in 0 ..< bitmap.width where gray(bitmap, x, y) > 200 {
                bitmap.setColor(red: 238, green: 228, blue: 205, x: x, y: y)
            }
        }
        let cleaned = BackgroundCleaner().cleaned(bitmap)
        #expect(cleaned.color(x: 30, y: 30) == ScanColor(red: 255, green: 255, blue: 255))
        #expect(gray(cleaned, 100, 66) < 60)
    }

    @Test("removes show-through from the back of the page")
    func removesShowThrough() {
        var bitmap = page()
        // Faint mirrored text between the lines.
        bitmap.fill(.init(x: 80, y: 450, width: 200, height: 10), gray: 232)
        bitmap.fill(.init(x: 80, y: 76, width: 200, height: 6), gray: 236)
        let cleaned = BackgroundCleaner().cleaned(bitmap)
        #expect(gray(cleaned, 150, 455) == 255)
        #expect(gray(cleaned, 150, 79) == 255)
    }

    @Test("evens out a gradual shadow towards the gutter")
    func evensGutterGradient() {
        var bitmap = page()
        for y in 0 ..< bitmap.height {
            for x in 300 ..< bitmap.width {
                let darker = (x - 300) / 4 // up to 25 darker at the edge
                bitmap.setGray(UInt8(gray(bitmap, x, y) - darker), x: x, y: y)
            }
        }
        let cleaned = BackgroundCleaner().cleaned(bitmap)
        #expect(gray(cleaned, 385, 50) == 255)
        #expect(gray(cleaned, 330, 66) < 60)
    }

    @Test("removes dark page edges and corner ticks at the border, keeps a page number there")
    func removesEdgesKeepsPageNumber() {
        var bitmap = page()
        // A dark page edge along the left side, broken into dashes.
        for top in stride(from: 20, to: 480, by: 40) {
            bitmap.fill(.init(x: 8, y: top, width: 3, height: 30), gray: 40)
        }
        // A shadow touching the right border.
        bitmap.fill(.init(x: 392, y: 0, width: 8, height: 500), gray: 60)
        // A corner tick.
        bitmap.fill(.init(x: 4, y: 6, width: 24, height: 2), gray: 20)
        // A page number of two digits near the bottom.
        bitmap.fill(.init(x: 190, y: 478, width: 6, height: 10), gray: 30)
        bitmap.fill(.init(x: 198, y: 478, width: 6, height: 10), gray: 30)

        let cleaned = BackgroundCleaner().cleaned(bitmap)

        #expect(gray(cleaned, 9, 35) == 255)
        #expect(gray(cleaned, 396, 250) == 255)
        #expect(gray(cleaned, 15, 7) == 255)
        #expect(gray(cleaned, 192, 483) < 60)
        #expect(gray(cleaned, 100, 66) < 60)
    }

    @Test("removes a faint grey page edge and a blot in a corner")
    func removesFaintEdgeAndCornerBlot() {
        var bitmap = page()
        bitmap.fill(.init(x: 385, y: 40, width: 2, height: 120), gray: 175)
        bitmap.fill(.init(x: 6, y: 482, width: 12, height: 12), gray: 50)

        let cleaned = BackgroundCleaner().cleaned(bitmap)

        #expect(gray(cleaned, 385, 100) == 255)
        #expect(gray(cleaned, 12, 488) == 255)
        #expect(gray(cleaned, 100, 66) < 60)
    }

    @Test("keeps a coloured note marker coloured")
    func keepsLinkColour() {
        var bitmap = page()
        for y in 100 ..< 108 {
            for x in 345 ..< 352 {
                bitmap.setColor(red: 30, green: 90, blue: 200, x: x, y: y)
            }
        }
        let color = BackgroundCleaner().cleaned(bitmap).color(x: 348, y: 104)
        #expect(Int(color.blue) > Int(color.red) + 100)
    }
}
