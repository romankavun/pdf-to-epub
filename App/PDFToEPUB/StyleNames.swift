import AppModel
import LayoutAnalysis
import Styles
import SwiftUI

extension Styles.Style {
    /// The style's name: its type, numbered when the type has other styles,
    /// and its deciding rule unless that only repeats the type:
    /// "Heading 1 · larger than the text", "Paragraph (2)".
    var name: String {
        namesRule ? String(localized: "\(title) · \(rule.name)") : title
    }

    /// The type and number alone, which tell the style apart from the
    /// others of its group: "Paragraph (2)".
    var title: String {
        guard let number else { return type.name }
        return String(localized: "\(type.name) (\(number))")
    }

    /// What a sidebar row shows under the title: the deciding rule when the
    /// name has it, then what sets the style apart from body text.
    var subtitle: String {
        namesRule ? "\(rule.name) · \(featuresText)" : featuresText
    }

    /// The style's colour: one hue per type, so the styles of a group read
    /// as one family, in a different shade for each style of the type.
    var color: Color {
        // Three brightness steps, then three saturations: nine shades
        // before they repeat, all bright enough for a dark background and
        // dark enough for a light one.
        let shade = (number ?? 1) - 1
        let brightness = [0.96, 0.8, 0.66][shade % 3]
        guard let hue = type.hue else {
            return Color(white: [0.62, 0.48, 0.76][shade % 3])
        }
        let saturation = [0.7, 0.42, 0.95][(shade / 3) % 3]
        return Color(hue: hue, saturation: saturation, brightness: brightness)
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

    /// The hue of the type's styles; page furniture is grey. Heading levels
    /// share the warm hues, a step apart.
    var hue: Double? {
        switch self {
        case let .heading(level): min(Double(max(level, 1) - 1) * 0.055, 0.11)
        case .paragraph: 0.6
        case .figure: 0.8
        case .note: 0.46
        case .pageFurniture: nil
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
