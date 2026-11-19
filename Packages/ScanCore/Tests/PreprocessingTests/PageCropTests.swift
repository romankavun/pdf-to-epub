import Preprocessing
import Testing

@Suite("PageCrop")
struct PageCropTests {
    @Test("finds the document page on a scanner bed, with a small margin")
    func findsPageOnBed() throws {
        let scan = SyntheticScans.scan()
        let box = try #require(PageCrop().pageBox(in: scan))
        // The text spans x 180...420, y 230...570; the paper beyond it is
        // indistinguishable from the bed except for its grain, so the crop
        // follows the paper.
        #expect(box.x <= 150 && box.x >= 130)
        #expect(box.y <= 200 && box.y >= 180)
        #expect(box.x + box.width >= 450 && box.x + box.width <= 470)
        #expect(box.y + box.height >= 600 && box.y + box.height <= 620)
    }

    @Test("crops the scan to the page")
    func cropsScan() {
        let scan = SyntheticScans.scan()
        let cropped = PageCrop().cropped(scan)
        #expect(cropped.width < 340 && cropped.width >= 300)
        #expect(cropped.height < 440 && cropped.height >= 400)
    }

    @Test("leaves a clean-page source clean page alone")
    func cleanPageUntouched() {
        let shot = SyntheticScans.cleanPage()
        #expect(PageCrop().pageBox(in: shot) == nil)
        #expect(PageCrop().cropped(shot) == shot)
    }

    @Test("leaves a clean page without a status bar alone: its margins are not a scanner bed")
    func cleanPageWithMarginsUntouched() {
        let shot = SyntheticScans.cleanPage(statusBar: false)
        #expect(PageCrop().pageBox(in: shot) == nil)
    }

    @Test("leaves a page alone when the page fills the image")
    func pageFillingImage() {
        let scan = SyntheticScans.scan(page: .init(x: 0, y: 0, width: 600, height: 800))
        #expect(PageCrop().pageBox(in: scan) == nil)
    }

    @Test("ignores a speck of dust on the bed")
    func ignoresDust() throws {
        var scan = SyntheticScans.scan()
        scan.fill(.init(x: 20, y: 20, width: 3, height: 3), gray: 0)
        let box = try #require(PageCrop().pageBox(in: scan))
        #expect(box.x >= 130 && box.y >= 180)
    }

    @Test("an empty bed has no page")
    func emptyBed() {
        #expect(PageCrop().pageBox(in: ScanBitmap(width: 100, height: 100, gray: 255)) == nil)
    }
}
