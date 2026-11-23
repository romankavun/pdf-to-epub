import Foundation
import LayoutAnalysis
import Styles

/// The styles of a conversion as `pagescan --styles` prints them, in English.
enum StyleReport {
    /// A count line, then one line per style, grouped by type as the style
    /// overview lists them. Page numbers count from 1.
    static func lines(for styles: [Style]) -> [String] {
        let sorted = styles.sorted { ($0.type, $0.paletteIndex) < ($1.type, $1.paletteIndex) }
        return ["Styles: \(styles.count)"] + sorted.map { "  " + line(for: $0) }
    }

    private static func line(for style: Style) -> String {
        let name = typeName(style.type) + (style.number.map { " \($0)" } ?? "") + " · " + ruleName(style.rule)
        let count = style.members.count
        let pages = style.pages.count == 1 ? "page " : "pages "
        let blocks = "\(count) block\(count == 1 ? "" : "s")"
        return "\(name): \(blocks), \(pages)\(ranges(style.pages)) (\(look(style.typical)))"
    }

    private static func look(_ style: BlockStyle) -> String {
        var parts = [String(format: "height %.2f", style.lineHeight)]
        if let ink = style.ink {
            parts.append(String(format: "ink %.2f", ink))
        }
        parts.append(style.alignment.rawValue)
        if style.zone != .body {
            parts.append(style.zone.rawValue)
        }
        if style.width < StyleGrouping.fullWidth {
            parts.append(String(format: "width %.2f", style.width))
        }
        parts.append("\(style.lineCount) line\(style.lineCount == 1 ? "" : "s")")
        if style.isUnderPicture {
            parts.append("under a picture")
        }
        return parts.joined(separator: ", ")
    }

    /// "1-4, 8" for pages 0, 1, 2, 3 and 7.
    private static func ranges(_ pages: [Int]) -> String {
        var runs: [ClosedRange<Int>] = []
        for page in pages {
            if let last = runs.last, last.upperBound == page - 1 {
                runs[runs.count - 1] = last.lowerBound ... page
            } else {
                runs.append(page ... page)
            }
        }
        return runs.map { $0.count == 1 ? "\($0.lowerBound + 1)" : "\($0.lowerBound + 1)-\($0.upperBound + 1)" }
            .joined(separator: ", ")
    }

    private static func typeName(_ type: StyleType) -> String {
        switch type {
        case let .heading(level): "Heading \(level)"
        case .paragraph: "Paragraph"
        case .figure: "Figure"
        case .note: "Note text"
        case .pageFurniture: "Page furniture"
        }
    }

    private static func ruleName(_ rule: DecidingRule) -> String {
        switch rule {
        case .largerThanText: "larger than the text"
        case .bodySizeBold: "body size and bold"
        case .bodySizeCentered: "body size and centred"
        case .captionByLabel: "caption by label"
        case .captionByGap: "caption by gap"
        case .picture: "picture without caption"
        case .noteText: "note text"
        case .paragraph: "paragraph"
        case .runningLine: "repeats at the page edge"
        case .pageNumber: "page number"
        }
    }
}
