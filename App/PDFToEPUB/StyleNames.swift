import AppModel
import LayoutAnalysis
import Styles
import SwiftUI

extension Styles.Style {
    /// The type and deciding rule, numbered when another style shares both:
    /// "Heading 1 · larger than the text", "Paragraph (2) · paragraph".
    var name: String {
        let rule = rule.name
        if let number {
            return String(localized: "\(type.name) (\(number)) · \(rule)")
        }
        return String(localized: "\(type.name) · \(rule)")
    }

    /// The style's colour: a fixed sequence of hues, so a project always gets
    /// the same colours and neighbours in the order of first appearance
    /// differ clearly.
    var color: Color {
        // The golden angle spreads any number of hues around the wheel.
        let hue = (Double(paletteIndex) * 0.618_034).truncatingRemainder(dividingBy: 1)
        let brightness = paletteIndex.isMultiple(of: 2) ? 0.78 : 0.62
        return Color(hue: hue, saturation: 0.75, brightness: brightness)
    }

    /// The pages as runs ("3–5, 9, 12–40"); long lists end in "…".
    var pagesText: String {
        let ranges = ReviewModel.pageRanges(pages)
        let shown = ranges.prefix(12).map { range in
            range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
        }
        return shown.joined(separator: ", ") + (ranges.count > shown.count ? ", …" : "")
    }

    /// What sets the style apart from body text, in words.
    var featuresText: String {
        let features = ReviewModel.features(of: self)
        guard !features.isEmpty else { return String(localized: "Looks like the body text") }
        return features.map(\.text).joined(separator: ", ")
    }
}

extension StyleType {
    /// The type as part of a style's name.
    var name: String {
        switch self {
        case let .heading(level): String(localized: "Heading \(level)")
        case .paragraph: String(localized: "Paragraph")
        case .figure: String(localized: "Illustration")
        case .note: String(localized: "Note text")
        case .pageFurniture: String(localized: "Page furniture")
        }
    }

    /// The heading of the type's group in the sidebar.
    var sectionTitle: String {
        switch self {
        case let .heading(level): String(localized: "Heading \(level)")
        case .paragraph: String(localized: "Paragraphs")
        case .figure: String(localized: "Figures and captions")
        case .note: String(localized: "Note texts")
        case .pageFurniture: String(localized: "Page furniture")
        }
    }

    var symbol: String {
        switch self {
        case .heading: "textformat.size"
        case .paragraph: "text.alignleft"
        case .figure: "photo"
        case .note: "note.text"
        case .pageFurniture: "rectangle.topthird.inset.filled"
        }
    }
}

extension DecidingRule {
    /// The rule as part of a style's name.
    var name: String {
        switch self {
        case .largerThanText: String(localized: "larger than the text")
        case .bodySizeBold: String(localized: "body size, bold")
        case .bodySizeCentered: String(localized: "body size, centred")
        case .captionByLabel: String(localized: "caption by label")
        case .captionByGap: String(localized: "caption by gap")
        case .picture: String(localized: "picture")
        case .noteText: String(localized: "note label")
        case .paragraph: String(localized: "paragraph")
        case .runningLine: String(localized: "running line")
        case .pageNumber: String(localized: "page number")
        }
    }
}

extension StyleWarning {
    /// What makes the style probably wrong, and what it probably is.
    var text: String {
        switch self {
        case let .headingAtPageEdge(pages):
            String(
                // swiftlint:disable:next line_length
                localized: "At the top or bottom edge of the page, on \(pages) pages: probably a running header taken for a heading."
            )
        case let .unjoinedLines(count):
            String(
                // swiftlint:disable:next line_length
                localized: "Full-width one-line paragraphs that stop mid-sentence (\(count)): probably lines of a paragraph that were not joined."
            )
        case let .mostlyMisrecognized(count):
            String(localized: "Most of its blocks (\(count)) are text probably misrecognized.")
        case .furnitureLooksLikeText:
            String(
                localized: "Its lines are long or vary from page to page: probably body text removed as page furniture."
            )
        }
    }
}

extension ReviewModel.StyleFeature {
    var text: String {
        switch self {
        case let .taller(times):
            String(localized: "\(times.formatted(.number.precision(.fractionLength(1)))) × taller than the text")
        case let .smaller(share):
            String(localized: "small print, \(share.formatted(.number.precision(.fractionLength(1)))) × the text")
        case .heavier: String(localized: "heavier")
        case .lighter: String(localized: "lighter")
        case .indented: String(localized: "indented")
        case .centered: String(localized: "centred")
        case .right: String(localized: "right-aligned")
        case .fullWidth: String(localized: "full width")
        case let .lines(count): String(localized: "\(count) lines")
        case .topEdge: String(localized: "at the top edge")
        case .bottomEdge: String(localized: "at the bottom edge")
        case .underPicture: String(localized: "under a picture")
        case .opensWithNoteLabel: String(localized: "opens with a note label")
        }
    }
}
