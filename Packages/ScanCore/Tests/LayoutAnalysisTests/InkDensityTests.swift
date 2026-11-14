import Foundation
import LayoutAnalysis
import Testing

private let paper = PageBitmap.Color(red: 248, green: 248, blue: 248)
private let ink = PageBitmap.Color(red: 20, green: 20, blue: 20)

/// A 400 x 400 page with a row of vertical strokes `thickness` pixels wide,
/// every 8 pixels, over the rectangle x 40...360, y 100...120.
private func page(strokeThickness thickness: Int) -> PageBitmap {
    var bitmap = PageBitmap(width: 400, height: 400, color: paper)
    for x in stride(from: 40, to: 360, by: 8) {
        bitmap.fill(x: x, y: 100, width: thickness, height: 20, with: ink)
    }
    return bitmap
}

private let region = CGRect(x: 0.1, y: 0.25, width: 0.8, height: 0.05)

@Suite("Ink density")
struct InkDensityTests {
    @Test("an empty area has no ink")
    func blank() {
        #expect(PageBitmap(width: 400, height: 400, color: paper).inkDensity(in: region) == 0)
    }

    @Test("thicker strokes give proportionally more ink")
    func thicker() {
        let thin = page(strokeThickness: 1).inkDensity(in: region)
        let bold = page(strokeThickness: 2).inkDensity(in: region)
        #expect(thin > 0.05)
        #expect(abs(bold / thin - 2) < 0.15)
    }

    @Test("light text on a dark page measures the same as dark on light")
    func inverted() {
        var dark = PageBitmap(width: 400, height: 400, color: ink)
        for x in stride(from: 40, to: 360, by: 8) {
            dark.fill(x: x, y: 100, width: 1, height: 20, with: paper)
        }
        let normal = page(strokeThickness: 1).inkDensity(in: region)
        #expect(abs(dark.inkDensity(in: region) - normal) < 0.01)
    }

    @Test("an area outside the page or of no size has no ink")
    func outside() {
        let bitmap = page(strokeThickness: 1)
        #expect(bitmap.inkDensity(in: CGRect(x: 1.5, y: 0.2, width: 0.1, height: 0.1)) == 0)
        #expect(bitmap.inkDensity(in: .zero) == 0)
    }
}
