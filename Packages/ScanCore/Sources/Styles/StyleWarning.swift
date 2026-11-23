import DocumentModel
import Foundation
import LayoutAnalysis

/// Why the style overview marks a style as probably wrong: a pattern that
/// usually means a recognition rule misfired for the whole document.
///
/// A warning is a hint to look, not a verdict, so the rules are tuned to be
/// rare and mostly right on the sample sets: each needs the pattern on
/// several blocks, as one odd block is the block list's business. The rules
/// are deterministic and judge what recognition decided, not the corrections.
public enum StyleWarning: Sendable, Equatable, Hashable {
    /// A heading style at the top or bottom edge of this many pages: probably
    /// a running header the repetition rule missed.
    case headingAtPageEdge(pages: Int)
    /// This many one-line paragraphs that run across the full width of the
    /// text column stop mid-sentence: probably lines of a paragraph that were
    /// not joined.
    case unjoinedLines(count: Int)
    /// This many blocks of the style, most of them, are text probably
    /// misrecognized.
    case mostlyMisrecognized(count: Int)
    /// Page furniture whose lines are long or vary from page to page:
    /// probably body text removed by mistake.
    case furnitureLooksLikeText

    /// A heading style at a page edge on at least this many pages is marked:
    /// a chapter title opens one page, a running header stands on many.
    public static let edgeHeadingPages = 3
    /// A style of one-line, full-width paragraphs is marked when at least
    /// this many of them stop mid-sentence, and more than
    /// ``unjoinedLineShare`` of them.
    public static let unjoinedLineMinimum = 10
    /// The share of a style's one-line paragraphs that must stop mid-sentence.
    /// Tuned on the sample sets: where the lines of numbered references were
    /// not joined, 44 to 49% of them stop mid-sentence (the last line of each
    /// reference ends it); where full lines are dialogue or one-sentence
    /// paragraphs, 3 to 11%. The width alone does not tell them apart, as a
    /// short line of dialogue can be measured across the full column.
    public static let unjoinedLineShare = 0.25
    /// At least this many blocks must be misrecognized to mark their style.
    public static let misrecognizedMinimum = 3
    /// Page furniture this wide, as the median share of the text column, is
    /// long: running headers and page numbers are short.
    public static let longFurnitureWidth = 0.6
    /// Page furniture whose most common text, digits and spaces ignored, is
    /// on less than this share of its lines varies from page to page. Left
    /// and right running headers take turns, so each is on half.
    public static let commonFurnitureShare = 0.4

    /// The warning for `style`, or `nil` for a style that looks as expected.
    ///
    /// - Parameters:
    ///   - style: A style of the document.
    ///   - styles: The block styles the document's styles were grouped from,
    ///     for measurements of each member.
    ///   - blocks: The document's recognized blocks, for the text of
    ///     one-line paragraphs; without them that rule is off.
    ///   - misrecognized: The blocks and note texts whose text was probably
    ///     misrecognized. Judging that needs a dictionary, which the caller
    ///     has; without one, pass none and the rule is off.
    public init?(
        for style: Style, in styles: BlockStyles, blocks: [Block] = [], misrecognized: Set<StyleMember> = []
    ) {
        let misread = style.members.count { misrecognized.contains($0) }
        if misread >= Self.misrecognizedMinimum, misread * 2 > style.members.count {
            self = .mostlyMisrecognized(count: misread)
            return
        }
        guard let warning = Self.lookWarning(for: style, in: styles, blocks: blocks) else { return nil }
        self = warning
    }

    /// The warnings judged by measurements and the shape of the text.
    private static func lookWarning(for style: Style, in styles: BlockStyles, blocks: [Block]) -> StyleWarning? {
        switch style.type {
        case .heading:
            guard style.typical.zone != .body, style.pages.count >= edgeHeadingPages else { return nil }
            return .headingAtPageEdge(pages: style.pages.count)
        case .paragraph:
            guard style.rule == .paragraph, style.typical.lineCount == 1,
                  style.typical.width >= StyleGrouping.fullWidth
            else { return nil }
            let open = style.members.count { member in
                guard case let .block(index) = member, blocks.indices.contains(index) else { return false }
                return !endsSentence(blocks[index])
            }
            let isCommon = Double(open) > unjoinedLineShare * Double(style.members.count)
            return open >= unjoinedLineMinimum && isCommon ? .unjoinedLines(count: open) : nil
        case .pageFurniture:
            let lines = style.members.compactMap { member -> PageFurniture? in
                guard case let .pageFurniture(index) = member, styles.pageFurniture.indices.contains(index) else {
                    return nil
                }
                return styles.pageFurniture[index]
            }
            return !lines.isEmpty && (isLong(lines) || varies(lines)) ? .furnitureLooksLikeText : nil
        case .figure, .note:
            return nil
        }
    }

    /// Whether the text of `block` ends a sentence: with a full stop,
    /// question or exclamation mark, ellipsis, colon or semicolon, or a
    /// closing quote or bracket. A line cut off from the rest of its
    /// paragraph usually stops mid-sentence.
    public static func endsSentence(_ block: Block) -> Bool {
        let content: [Inline] = switch block {
        case let .heading(_, content), let .paragraph(content): content
        case let .figure(figure): figure.caption
        }
        let text = content.compactMap { inline -> String? in
            switch inline {
            case let .text(text), let .emphasis(text), let .strong(text): text
            case .noteReference: nil
            }
        }.joined()
        guard let last = text.last(where: { !$0.isWhitespace }) else { return false }
        return ".!?…:;»\"”’)]".contains(last)
    }

    private static func isLong(_ lines: [PageFurniture]) -> Bool {
        let widths = lines.map(\.style.width).sorted()
        return widths[(widths.count - 1) / 2] >= longFurnitureWidth
    }

    /// Whether no one text, digits and spaces ignored, is on enough of the lines.
    private static func varies(_ lines: [PageFurniture]) -> Bool {
        let counts = Dictionary(grouping: lines) { line in
            line.text.lowercased().filter { !$0.isNumber && !$0.isWhitespace }
        }.mapValues(\.count)
        let common = counts.values.max() ?? 0
        return Double(common) < commonFurnitureShare * Double(lines.count)
    }
}
