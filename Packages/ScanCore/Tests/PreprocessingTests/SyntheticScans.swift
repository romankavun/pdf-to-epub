import Foundation
import Preprocessing

/// Pages built in code that imitate the two kinds of input: a document page
/// lying on a scanner bed, and a clean-page source clean page.
enum SyntheticScans {
    /// A rectangle in pixels, for describing where things were drawn.
    struct Rect {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    /// The paper of a scanned page: almost white but never quite, with a
    /// little grain, the way a scanner sees it. Deterministic.
    static func paperTone(x: Int, y: Int) -> UInt8 {
        255 - UInt8((x * 7 + y * 13) % 5)
    }

    /// A white scanner bed with a smaller document page on it. The page has
    /// grainy paper and dark text lines, 12 px tall every 24 px, inset by
    /// `textInset` from the page's sides, descending to the right by
    /// `skew` degrees.
    static func scan(
        width: Int = 600,
        height: Int = 800,
        page: Rect = Rect(x: 150, y: 200, width: 300, height: 400),
        textInset: Int = 30,
        lineHeight: Int = 12,
        skew: Double = 0
    ) -> ScanBitmap {
        var bitmap = ScanBitmap(width: width, height: height, gray: 255)
        for y in page.y ..< page.y + page.height {
            for x in page.x ..< page.x + page.width {
                bitmap.setGray(paperTone(x: x, y: y), x: x, y: y)
            }
        }
        var top = page.y + textInset
        while top + lineHeight <= page.y + page.height - textInset {
            let slope = tan(skew * .pi / 180)
            for x in page.x + textInset ..< page.x + page.width - textInset where (x - page.x) % 28 < 20 {
                let shift = Int((Double(x - page.x - page.width / 2) * slope).rounded())
                bitmap.fill(Rect(x: x, y: top + shift, width: 1, height: lineHeight), gray: 30)
            }
            top += 2 * lineHeight
        }
        return bitmap
    }

    /// a clean-page source clean page: one exact background colour, text lines with
    /// margins, and a status bar along the bottom edge.
    static func cleanPage(width: Int = 600, height: Int = 800, statusBar: Bool = true) -> ScanBitmap {
        var bitmap = ScanBitmap(width: width, height: height, gray: 248)
        var top = 60
        while top + 12 <= height - 80 {
            bitmap.fill(Rect(x: 50, y: top, width: width - 100, height: 12), gray: 40)
            top += 24
        }
        if statusBar {
            bitmap.fill(Rect(x: 0, y: height - 20, width: width, height: 20), gray: 200)
        }
        return bitmap
    }
}

extension ScanBitmap {
    mutating func fill(_ rect: SyntheticScans.Rect, gray: UInt8) {
        for y in max(0, rect.y) ..< min(height, rect.y + rect.height) {
            for x in max(0, rect.x) ..< min(width, rect.x + rect.width) {
                setGray(gray, x: x, y: y)
            }
        }
    }

    mutating func setGray(_ gray: UInt8, x: Int, y: Int) {
        setColor(red: gray, green: gray, blue: gray, x: x, y: y)
    }
}
