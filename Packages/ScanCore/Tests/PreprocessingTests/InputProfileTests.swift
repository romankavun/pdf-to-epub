import Foundation
import Preprocessing
import Testing

@Suite("InputProfile")
struct InputProfileTests {
    @Test("a page on a scanner bed with grainy paper is a paper scan")
    func scanPage() {
        #expect(InputProfile(of: SyntheticScans.scan()) == .paperScan)
    }

    @Test("a clean page is not a scan, with or without a status bar along the edge")
    func cleanPages() {
        #expect(InputProfile(of: SyntheticScans.cleanPage()) == .cleanPage)
        #expect(InputProfile(of: SyntheticScans.cleanPage(statusBar: false)) == .cleanPage)
    }

    @Test("a dark cover on the bed alone does not make a scan: it has no paper")
    func coverAlone() {
        var cover = ScanBitmap(width: 600, height: 800, gray: 255)
        cover.fill(.init(x: 150, y: 200, width: 300, height: 400), gray: 40)
        #expect(InputProfile(of: cover) == .cleanPage)
    }

    @Test("a document is a scan when most of its pages look scanned", arguments: [
        ([true, true, false], InputProfile.paperScan),
        ([true, false, false], .cleanPage),
        ([true, false], .cleanPage),
        ([], .cleanPage),
    ])
    func majority(pages: [Bool], expected: InputProfile) {
        #expect(InputProfile(ofDocument: pages.map { $0 ? .paperScan : .cleanPage }) == expected)
    }

    @Test("samples at most a handful of pages, spread over the document")
    func sample() {
        #expect(InputProfile.sampleIndices(pageCount: 3) == [0, 1, 2])
        let sample = InputProfile.sampleIndices(pageCount: 380)
        #expect(sample.count == InputProfile.sampleSize)
        #expect(sample.first == 0 && sample.last == 379)
        #expect(sample == sample.sorted() && Set(sample).count == sample.count)
    }
}
