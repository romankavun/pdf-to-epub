import CoreGraphics

/// The lines of a block and what is known about it, before measuring.
struct MeasuredBlock {
    var lines: [MeasuredLine]
    var rule: DecidingRule
    /// The step from the line before to the first line, if any.
    var stepAbove: Double?
    /// The step from the last line to the next one, if any.
    var stepBelow: Double?
    var isUnderPicture = false
    var opensWithNoteLabel = false
}

/// What measuring a block against the document needs besides its lines.
struct StyleContext {
    let metrics: Metrics
    /// The margin of each page, by page index.
    let margins: [PageMargin]
    /// The document's typical ink density; `nil` when no line was measured.
    let typicalInk: Double?
    /// Where the text of a page usually starts and ends: the median top of
    /// the first line and bottom of the last line of the pages with text.
    let textBand: ClosedRange<Double>

    init(metrics: Metrics, pages: [[PageElement]], margins: [PageMargin], typicalInk: Double?) {
        self.metrics = metrics
        self.margins = margins
        self.typicalInk = typicalInk
        let rows = pages.map { $0.compactMap(\.row?.line.box) }.filter { !$0.isEmpty }
        let top = Metrics.median(rows.compactMap { $0.first.map { Double($0.minY) } }) ?? 0
        let bottom = Metrics.median(rows.compactMap { $0.last.map { Double($0.maxY) } }) ?? 1
        textBand = top ... max(top, bottom)
    }
}

extension LayoutAnalyzer {
    /// The style of `block`, measured against the document.
    func style(of block: MeasuredBlock, context: StyleContext) -> BlockStyle {
        let metrics = context.metrics
        let lines = block.lines
        let (rule, isUnderPicture, opensWithNoteLabel) = (block.rule, block.isUnderPicture, block.opensWithNoteLabel)
        guard let first = lines.first else {
            return BlockStyle(rule: rule, isUnderPicture: isUnderPicture, opensWithNoteLabel: opensWithNoteLabel)
        }
        let start = lines.prefix { $0.page == first.page }.map(\.box).reduce(first.box) { $0.union($1) }
        let heights = lines.map { Double($0.box.height) }
        let inks = lines.compactMap(\.ink)
        let ink = context.typicalInk.flatMap { typical in
            inks.isEmpty || typical <= 0 ? nil : inks.reduce(0, +) / Double(inks.count) / typical
        }
        return BlockStyle(
            rule: rule,
            lineHeight: metrics.lineHeight > 0 ? (Metrics.median(heights) ?? 0) / metrics.lineHeight : 1,
            ink: ink,
            alignment: alignment(of: start, firstLine: first.box, page: first.page, context: context),
            width: width(of: start, context: context),
            // A block that runs on is part of the text, wherever it starts.
            zone: lines.contains { $0.page != first.page } ? .body : zone(of: start, context: context),
            lineCount: lines.count,
            spaceAbove: block.stepAbove.map { inSteps($0, metrics: metrics) },
            spaceBelow: block.stepBelow.map { inSteps($0, metrics: metrics) },
            isUnderPicture: isUnderPicture,
            opensWithNoteLabel: opensWithNoteLabel
        )
    }

    /// The style of a figure without a caption: the picture's place alone.
    func style(ofPictureAt box: CGRect, page: Int, stepAbove: Double?, context: StyleContext) -> BlockStyle {
        BlockStyle(
            rule: .picture,
            lineHeight: 0,
            alignment: alignment(of: box, firstLine: nil, page: page, context: context),
            width: width(of: box, context: context),
            zone: zone(of: box, context: context),
            lineCount: 0,
            spaceAbove: stepAbove.map { inSteps($0, metrics: context.metrics) }
        )
    }

    private func inSteps(_ step: Double, metrics: Metrics) -> Double {
        metrics.lineStep > 0 ? step / metrics.lineStep : 0
    }

    /// The width of the text column; never zero, so it can divide.
    private func columnWidth(_ metrics: Metrics) -> Double {
        max(metrics.rightEdge - metrics.margin, 0.01)
    }

    private func width(of box: CGRect, context: StyleContext) -> Double {
        Double(box.width) / columnWidth(context.metrics)
    }

    /// Centred blocks keep clear of both edges by a twentieth of the column
    /// at least (a full line that ends a little short is no centred line); a
    /// block that starts at a fifth of the column or further and ends at the
    /// right edge is set to the right.
    private func alignment(
        of box: CGRect, firstLine: CGRect?, page: Int, context: StyleContext
    ) -> BlockStyle.Alignment {
        let column = columnWidth(context.metrics)
        let margin = context.margins.indices.contains(page)
            ? context.margins[page].at(Double(box.minY)) : context.metrics.margin
        let right = margin + column
        let clearLeft = Double(box.minX) > margin + options.indentThreshold
        let clearRight = Double(box.maxX) < right - options.indentThreshold
        let isNarrow = min(Double(box.minX) - margin, right - Double(box.maxX)) >= 0.05 * column
        if isNarrow, abs(Double(box.midX) - (margin + column / 2)) <= options.bodyHeadingCenterTolerance {
            return .centered
        }
        if clearLeft, !clearRight, Double(box.minX) - margin >= 0.2 * column {
            return .right
        }
        if let firstLine, Double(firstLine.minX) > margin + options.indentThreshold {
            return .indented
        }
        return .margin
    }

    /// At an edge when the block lies above where the text of a page
    /// usually starts, or below where it usually ends, by more than half a
    /// line: the first and last lines of an ordinary page are in the body.
    private func zone(of box: CGRect, context: StyleContext) -> BlockStyle.Zone {
        let slack = context.metrics.lineHeight / 2
        if Double(box.maxY) <= context.textBand.lowerBound + slack {
            return .top
        }
        return Double(box.minY) >= context.textBand.upperBound - slack ? .bottom : .body
    }

    /// The lines left out of each page as page furniture, top to bottom.
    func pageFurniture(
        pageNumbers: [Row?], runningLines: [[(row: Row, rule: DecidingRule)]], context: StyleContext
    ) -> [PageFurniture] {
        zip(pageNumbers, runningLines).enumerated().flatMap { page, removed in
            (removed.1 + (removed.0.map { [($0, DecidingRule.pageNumber)] } ?? []))
                .sorted { $0.row.line.box.minY < $1.row.line.box.minY }
                .map { row, rule in
                    let line = MeasuredLine(page: page, box: row.line.box, ink: row.ink)
                    return PageFurniture(
                        area: PageArea(page: page, box: row.line.box),
                        text: row.line.text,
                        style: style(
                            of: MeasuredBlock(lines: [line], rule: rule, stepAbove: nil, stepBelow: nil),
                            context: context
                        )
                    )
                }
        }
    }
}
