import CoreGraphics
import Foundation
import OCR

extension LayoutAnalyzer {
    /// How the line at `index` of `page`, which is not taller than body
    /// text, stands out as a heading set at body size, if it is one.
    ///
    /// Such headings are told apart by what surrounds them, since their type
    /// is the same as the text's: a single line with blank space above and
    /// below, short, not ending like a sentence, and either centered or in
    /// heavier ink than the body text (ADR 0006). A line right under a
    /// picture is a caption and never qualifies.
    ///
    /// - Parameter typicalInk: The document's usual ink density, or `nil` when
    ///   the pages were not measured, in which case only centering counts.
    func bodySizeHeadingStyle(
        at index: Int, in page: [PageElement], metrics: Metrics, typicalInk: Double?
    ) -> HeadingStyle? {
        guard let row = page[index].row, row.markers.isEmpty else { return nil }
        let line = row.line
        let width = Double(line.box.width)
        let text = line.text.trimmingCharacters(in: .whitespaces)
        guard width <= options.bodyHeadingMaximumWidth, !text.isEmpty,
              text.count <= options.bodyHeadingMaximumLength,
              !(text.last.map { ".,;:…".contains($0) } ?? false)
        else { return nil }

        // Set apart above: the first thing on the page, or a blank line.
        let spaceAbove: Bool
        if index == 0 {
            spaceAbove = true
        } else if let above = page[index - 1].row {
            spaceAbove = isBlankLine(between: above.line, and: line, metrics: metrics)
        } else {
            return nil // under a picture
        }
        // And below: the last thing on the page, a picture, or a blank line.
        let spaceBelow: Bool = if index == page.count - 1 {
            true
        } else if let below = page[index + 1].row {
            isBlankLine(between: line, and: below.line, metrics: metrics)
        } else {
            true
        }
        guard spaceAbove else { return nil }

        let isBold = row.ink.flatMap { ink in typicalInk.map { ink >= options.boldInkFactor * $0 } } ?? false
        // Bold is evidence enough that the text below may follow closely: a
        // heading is often set tight above its first paragraph. A centered
        // line in body weight needs space on both sides.
        if isBold {
            return .bold
        }
        let isCentered = abs(Double(line.box.midX) - 0.5) <= options.bodyHeadingCenterTolerance
        let isShort = text.split(separator: " ").count <= options.centeredHeadingMaximumWords
        return isCentered && isShort && spaceBelow ? .centered : nil
    }

    /// Whether the vertical step from `upper` to `lower` is a paragraph gap.
    private func isBlankLine(between upper: TextLine, and lower: TextLine, metrics: Metrics) -> Bool {
        Double(lower.box.minY - upper.box.minY) > options.paragraphGapFactor * metrics.lineStep
    }

    /// The ink density most lines of the document have, `nil` when none were
    /// measured. The lower median, like ``Metrics``: bold lines are few.
    func typicalInk(of pages: [[PageElement]]) -> Double? {
        let densities = pages.flatMap { $0.compactMap { $0.row?.ink } }.sorted()
        return densities.isEmpty ? nil : densities[(densities.count - 1) / 2]
    }
}
