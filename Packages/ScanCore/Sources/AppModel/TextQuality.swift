import Conversion
import CoreGraphics
import DocumentModel
import LayoutAnalysis
import TextReview

/// Pages that probably lost their text to a figure: on a badly scanned page
/// picture detection can take the whole page for an illustration, and its
/// text then never reaches OCR. Nothing in the document says so, so the review
/// has to warn.
enum LostText {
    /// The share of the document's text area a lone figure must cover to be
    /// suspected. A scanned figure that took a text page covers 0.7 to 1.0
    /// of it; an ordinary illustration in the flow of text covers far less.
    static let minimumCoverage = 0.6

    /// The indices in ``Document/blocks`` of the figures that are the only
    /// content of their page, have no caption, and cover at least
    /// ``minimumCoverage`` of the text area.
    ///
    /// A full-page plate without a caption is flagged too: the warning asks
    /// the user to look, and a caption or *Ignore* answers it.
    static func figures(in conversion: Conversion) -> Set<Int> {
        let blocks = conversion.document.blocks
        let sources = zip(blocks, conversion.blockSources)
        var contentCount: [Int: Int] = [:]
        for source in conversion.blockSources + conversion.noteSources {
            for page in Set(source.areas.map(\.page)) {
                contentCount[page, default: 0] += 1
            }
        }
        let textBoxes = sources.filter { !$0.0.isFigure }.flatMap { $0.1.areas.map(\.box) }
            + conversion.noteSources.flatMap { $0.areas.map(\.box) }
        let area = textArea(of: textBoxes)
        var result: Set<Int> = []
        for (index, (block, source)) in sources.enumerated() {
            guard case let .figure(figure) = block, figure.caption.isEmpty, source.continuations.isEmpty,
                  contentCount[source.page] == 1
            else { continue }
            let covered = source.box.intersection(area)
            if !covered.isNull, covered.width * covered.height >= minimumCoverage * area.width * area.height {
                result.insert(index)
            }
        }
        return result
    }

    /// Where the document's text usually lies on a page: the edges of the text
    /// boxes, each taken at the 5th or 95th percentile so that one stray
    /// block does not stretch it. A scan with wide margins has a small text
    /// area; a document with too little text to tell gets the whole page.
    static func textArea(of boxes: [CGRect]) -> CGRect {
        guard boxes.count >= 3 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        func percentile(_ values: [CGFloat], _ fraction: Double) -> CGFloat {
            let sorted = values.sorted()
            return sorted[Int(Double(sorted.count - 1) * fraction)]
        }
        let minX = percentile(boxes.map(\.minX), 0.05), minY = percentile(boxes.map(\.minY), 0.05)
        let maxX = percentile(boxes.map(\.maxX), 0.95), maxY = percentile(boxes.map(\.maxY), 0.95)
        guard maxX > minX, maxY > minY else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension SuspiciousWordDetector {
    /// The spelling tally of a block's text, summed over its pieces of text
    /// as the review splits them into runs; note references are not words.
    func spellingTally(
        of content: [Inline], in language: SpellLanguage?, ignoring ignoredWords: Set<String>
    ) -> SpellingTally {
        content.reduce(SpellingTally()) { tally, inline in
            switch inline {
            case let .text(text), let .emphasis(text), let .strong(text):
                tally + spellingTally(of: text, in: language, ignoring: ignoredWords)
            case .noteReference:
                tally
            }
        }
    }
}

extension Block {
    var isFigure: Bool {
        if case .figure = self {
            true
        } else {
            false
        }
    }
}
