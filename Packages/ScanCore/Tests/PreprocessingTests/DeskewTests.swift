import Foundation
import Preprocessing
import Testing

/// A white page with text lines that descend to the right at `degrees`:
/// words of 20 px with 8 px gaps, lines 10 px tall every 26 px.
private func skewedPage(degrees: Double, width: Int = 500, height: Int = 600) -> ScanBitmap {
    var bitmap = ScanBitmap(width: width, height: height, gray: 255)
    let slope = tan(degrees * .pi / 180)
    var top = 60
    while top + 10 <= height - 80 {
        for x in 50 ..< width - 50 where (x - 50) % 28 < 20 {
            let shift = Int((Double(x - width / 2) * slope).rounded())
            for y in top ..< top + 10 {
                bitmap.setGray(25, x: x, y: y + shift)
            }
        }
        top += 26
    }
    return bitmap
}

@Suite("Deskew")
struct DeskewTests {
    @Test("measures the angle of text lines", arguments: [-2.5, -1.2, 0.0, 0.7, 1.5, 3.0])
    func measuresAngle(degrees: Double) {
        let angle = Deskew().skewAngle(of: skewedPage(degrees: degrees))
        #expect(abs(angle - degrees) <= 0.15, "measured \(angle)")
    }

    @Test("rotates a skewed page so its lines are level")
    func levelsPage() {
        let page = skewedPage(degrees: 1.5)
        let straightened = Deskew().straightened(page)
        #expect(abs(Deskew().skewAngle(of: straightened)) <= 0.15)
        // The canvas grows so that no corner of the page is cut.
        #expect(straightened.width >= page.width && straightened.height >= page.height)
    }

    @Test("leaves a level page untouched")
    func levelPageUntouched() {
        let page = skewedPage(degrees: 0)
        #expect(Deskew().straightened(page) == page)
    }

    @Test("a blank page has no skew")
    func blankPage() {
        #expect(Deskew().skewAngle(of: ScanBitmap(width: 50, height: 50, gray: 255)) == 0)
    }
}
