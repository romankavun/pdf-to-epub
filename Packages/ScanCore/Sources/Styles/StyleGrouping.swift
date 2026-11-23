import DocumentModel
import Foundation
import LayoutAnalysis

/// Groups what layout analysis recognized into styles.
///
/// Deterministic, no learning: each block's measured features are quantized
/// into buckets, and blocks with the same type, the same deciding rule and
/// the same buckets form a style. Buckets are fine, so a block that looks a
/// little different stands out as a style of its own, yet wide enough that
/// the noise of recognition (a line box a few percent taller, a short last
/// line) does not split a style.
///
/// Tuned on the sample sets: the median line of a body paragraph measures
/// anywhere from 0.9 to 1.15 of the document's, and its mean ink from 0.85 to
/// 1.25, so body text gets one wide bucket of each. A single line's box
/// depends on its letters (digits and letters without descenders come out
/// shorter, a short word lighter), so a single line never counts as smaller
/// or lighter than the text; only several lines do (small print).
///
/// Styles are computed from the recognized document, not the corrected one,
/// so they do not reshuffle while the user fixes blocks.
public enum StyleGrouping {
    /// Line heights in this range, as a multiple of the document's, are body text.
    static let bodyLineHeight = 0.75 ..< 1.35
    /// The ratio between the line heights of neighbouring buckets beyond body text.
    static let lineHeightStep = 1.5
    /// Mean ink in this range, as a multiple of the typical line's, is regular.
    static let regularInk = 0.7 ..< 1.35
    /// A block at least this wide (a share of the text column) is full width.
    public static let fullWidth = 0.8

    /// The styles of a document in order of first appearance.
    ///
    /// - Parameters:
    ///   - blocks: The recognized blocks, in reading order.
    ///   - blockSources: The origin of each block, in the same order.
    ///   - noteSources: The origin of each note text, in note order.
    ///   - styles: The style of each block, note and line of page furniture.
    ///   Entries without a counterpart in the other arrays are left out.
    public static func styles(
        blocks: [Block], blockSources: [BlockSource], noteSources: [BlockSource], styles: BlockStyles
    ) -> [Style] {
        var entries: [Entry] = []
        for (index, (block, style)) in zip(blocks, styles.blocks).enumerated() {
            entries.append(Entry(
                member: .block(index), type: type(of: block), style: style,
                area: blockSources.indices.contains(index) ? blockSources[index].start : nil
            ))
        }
        for (index, style) in styles.notes.enumerated() {
            entries.append(Entry(
                member: .note(index), type: .note, style: style,
                area: noteSources.indices.contains(index) ? noteSources[index].start : nil
            ))
        }
        for (index, furniture) in styles.pageFurniture.enumerated() {
            entries.append(Entry(
                member: .pageFurniture(index), type: .pageFurniture, style: furniture.style, area: furniture.area
            ))
        }
        // Stable, so entries at the same place keep the order they came in.
        let ordered = entries.enumerated().sorted { first, second in
            let (one, other) = (first.element, second.element)
            return (one.page, one.top, first.offset) < (other.page, other.top, second.offset)
        }.map(\.element)

        var groups: [Signature: [Entry]] = [:]
        var order: [Signature] = []
        for entry in ordered {
            let signature = Signature(entry)
            if groups[signature] == nil {
                order.append(signature)
            }
            groups[signature, default: []].append(entry)
        }

        let clashes = Dictionary(grouping: order) { NameKey(type: $0.type, rule: $0.rule) }
        return order.enumerated().map { paletteIndex, signature in
            let members = groups[signature] ?? []
            let sharing = clashes[NameKey(type: signature.type, rule: signature.rule)] ?? []
            return Style(
                type: signature.type,
                rule: signature.rule,
                number: sharing.count > 1 ? sharing.firstIndex(of: signature).map { $0 + 1 } : nil,
                members: members.map(\.member),
                pages: Array(Set(members.compactMap(\.area?.page))).sorted(),
                paletteIndex: paletteIndex,
                typical: typical(of: members.map(\.style))
            )
        }
    }

    private static func type(of block: Block) -> StyleType {
        switch block {
        case let .heading(level, _): .heading(level: level)
        case .paragraph: .paragraph
        case .figure: .figure
        }
    }

    /// The median of each measurement, the place of the first.
    private static func typical(of styles: [BlockStyle]) -> BlockStyle {
        guard var typical = styles.first else { return BlockStyle(rule: .paragraph) }
        func median(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.sorted()[(values.count - 1) / 2]
        }
        typical.lineHeight = median(styles.map(\.lineHeight)) ?? typical.lineHeight
        typical.ink = median(styles.compactMap(\.ink))
        typical.width = median(styles.map(\.width)) ?? typical.width
        typical.lineCount = Int(median(styles.map { Double($0.lineCount) }) ?? 0)
        typical.spaceAbove = median(styles.compactMap(\.spaceAbove))
        typical.spaceBelow = median(styles.compactMap(\.spaceBelow))
        return typical
    }

    /// 0 for body text, positive for larger type in steps of
    /// ``lineHeightStep``, negative for small print; `nil` for no lines.
    static func lineHeightBucket(of style: BlockStyle) -> Int? {
        let height = style.lineHeight
        guard height > 0 else { return nil }
        let body = bodyLineHeight
        if height >= body.upperBound {
            return 1 + Int(floor(log(height / body.upperBound) / log(lineHeightStep)))
        }
        guard height < body.lowerBound, style.lineCount > 1 else { return 0 }
        return -1 - Int(floor(log(body.lowerBound / height) / log(lineHeightStep)))
    }

    /// 0 for regular ink, 1 for heavy, -1 for light (several lines only);
    /// `nil` when not measured, or for a heading that is bold by its rule.
    static func inkBucket(of style: BlockStyle) -> Int? {
        guard let ink = style.ink, style.rule != .bodySizeBold else { return nil }
        if ink >= regularInk.upperBound {
            return 1
        }
        return ink < regularInk.lowerBound && style.lineCount > 1 ? -1 : 0
    }

    /// The type and rule a style's name is made of.
    private struct NameKey: Hashable {
        let type: StyleType
        let rule: DecidingRule
    }

    /// One thing to group, with where it first appears.
    private struct Entry {
        let member: StyleMember
        let type: StyleType
        let style: BlockStyle
        let area: PageArea?

        /// The page it starts on; an entry without a place goes last.
        var page: Int {
            area?.page ?? .max
        }

        var top: Double {
            area.map { Double($0.box.minY) } ?? 0
        }
    }

    /// What blocks of one style share.
    private struct Signature: Hashable {
        let type: StyleType
        let rule: DecidingRule
        let lineHeight: Int?
        let ink: Int?
        let alignment: BlockStyle.Alignment
        let isFullWidth: Bool
        let zone: BlockStyle.Zone
        let isMultiLine: Bool
        let isUnderPicture: Bool
        let opensWithNoteLabel: Bool

        init(_ entry: Entry) {
            let style = entry.style
            type = entry.type
            rule = style.rule
            lineHeight = StyleGrouping.lineHeightBucket(of: style)
            ink = StyleGrouping.inkBucket(of: style)
            alignment = style.alignment
            isFullWidth = style.width >= StyleGrouping.fullWidth
            zone = style.zone
            isMultiLine = style.lineCount > 1
            isUnderPicture = style.isUnderPicture
            opensWithNoteLabel = style.opensWithNoteLabel
        }
    }
}
