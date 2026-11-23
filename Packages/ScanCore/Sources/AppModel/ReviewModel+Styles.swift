import Conversion
import CoreGraphics
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Styles
import TextReview

public extension ReviewModel {
    /// How many examples a selected style shows before *Show All*.
    nonisolated static let exampleCount = 6

    /// The styles of one type, as the sidebar lists them under one heading.
    struct StyleSection: Sendable, Equatable, Identifiable {
        public var type: StyleType
        /// In order of first appearance.
        public var styles: [Styles.Style]

        public var id: StyleType {
            type
        }
    }

    /// What the user did to a block of a style.
    enum ExampleMark: Sendable, Equatable {
        /// Its type, text or boundaries were changed.
        case corrected
        /// It was left out of the document.
        case ignored
    }

    /// One block of a style as the style overview shows it: a crop of the
    /// page image (see GLOSSARY.md, *Example*).
    struct StyleExample: Sendable, Equatable, Identifiable {
        public var member: StyleMember
        /// The page the block starts on.
        public var page: Int
        /// Its area on that page, normalized, origin at the top-left corner.
        public var box: CGRect
        /// Whether the user corrected or ignored it; `nil` when it stands as recognized.
        public var mark: ExampleMark?

        public var id: StyleMember {
            member
        }
    }

    /// The blocks of the selected style on the page in view, which the scan
    /// outlines in the style's colour.
    struct StyleOutlines: Sendable, Equatable {
        /// Blocks and note texts, top to bottom.
        public var itemIDs: [ItemID]
        /// Areas of page furniture, which has no block of its own.
        public var furniture: [CGRect]
    }

    /// Something that sets a style apart from body text, for saying its
    /// deciding rule in words ("1.6 × taller than the text, centred").
    enum StyleFeature: Sendable, Equatable {
        /// Its lines are this many times as tall as the text's.
        case taller(Double)
        /// Small print: its lines are this share of the text's.
        case smaller(Double)
        case heavier
        case lighter
        case indented
        case centered
        case right
        /// At least ``Styles/StyleGrouping/fullWidth`` of the text column.
        case fullWidth
        /// Several lines; one line is not mentioned.
        case lines(Int)
        case topEdge
        case bottomEdge
        case underPicture
        case opensWithNoteLabel
    }

    // MARK: - The sidebar

    /// The document's styles, from what recognition decided (not the
    /// corrections), so they never reshuffle while the user works; `nil` for
    /// a project saved before styles were kept (format version 1).
    var styles: [Styles.Style]? {
        styleIndex.styles
    }

    /// The styles as the sidebar lists them, grouped by type.
    var styleSections: [StyleSection] {
        styleIndex.sections
    }

    /// The selected style, while the sidebar shows it.
    var selectedStyle: Styles.Style? {
        guard showsStyles, let selectedStyleID, let styles, styles.indices.contains(selectedStyleID) else {
            return nil
        }
        return styles[selectedStyleID]
    }

    /// Whether a style's blocks replace the page's block list. The issue and
    /// spelling controls, which act on the block list, are hidden meanwhile.
    var isShowingStyle: Bool {
        selectedStyle != nil
    }

    /// Shows the blocks of the style `id`, or the block list again for
    /// `nil`. Closes the editor, whose card goes out of view.
    func selectStyle(_ id: Styles.Style.ID?) {
        cancelEditing()
        if id != nil {
            showsStyles = true
        }
        selectedStyleID = showsStyles ? id : nil
    }

    /// The style `item` was recognized with: an ignored or retyped block
    /// stays in its style. `nil` without styles, and for a block a split
    /// made, which recognition never saw.
    func style(of item: Item) -> Styles.Style? {
        guard let styles, let member = member(of: item), let index = styleIndex.memberStyle[member] else { return nil }
        return styles[index]
    }

    /// Opens the sidebar on the style of `item`: the way back from a block to its style.
    func showStyle(of item: Item) {
        guard let style = style(of: item) else { return }
        selectStyle(style.id)
    }

    /// Why `style` is probably wrong, or `nil` when it looks as expected.
    /// Judged from what recognition decided, like the styles themselves;
    /// text probably misrecognized is judged with the review's dictionary.
    func warning(of style: Styles.Style) -> StyleWarning? {
        styleIndex.warnings[style.id]
    }

    /// How many blocks of `style` the user corrected or ignored. A word
    /// replaced everywhere does not count: it is not a decision about the block.
    func correctedCount(of style: Styles.Style) -> Int {
        style.members.count { correctedMembers[$0] != nil }
    }

    /// The examples of `style`: `limit` blocks from pages spread across the
    /// document, no two from one page while another page still has one, in
    /// page order; every block for `nil`.
    func examples(of style: Styles.Style, limit: Int? = exampleCount) -> [StyleExample] {
        let placed = style.members.compactMap { member in
            place(of: member).map {
                StyleExample(member: member, page: $0.page, box: $0.box, mark: correctedMembers[member])
            }
        }
        guard let limit else { return placed }
        return Self.spread(pages: placed.map(\.page), count: limit).map { placed[$0] }
    }

    /// The blocks of the selected style on the page in view; `nil` while no
    /// style is shown.
    var styleOutlines: StyleOutlines? {
        guard let style = selectedStyle, let page = currentPage else { return nil }
        let itemIDs = page.items.filter { self.style(of: $0)?.id == style.id }.map(\.id)
        let furniture = style.members.compactMap { member -> CGRect? in
            guard case .pageFurniture = member, let area = place(of: member), area.page == page.id else { return nil }
            return area.box
        }
        return StyleOutlines(itemIDs: itemIDs, furniture: furniture)
    }

    /// Goes to the page of `example`, selects its block and brings back the
    /// block list. A block merged into the one before opens the merged
    /// block; page furniture, which has no block, opens its page only.
    func open(_ example: StyleExample) {
        selectStyle(nil)
        goToPage(example.page)
        let items = currentPage?.items ?? []
        let target: Item? = switch example.member {
        case .pageFurniture: nil
        case let .note(index):
            project.base.document.notes.indices.contains(index)
                ? items.first { $0.id == .note(project.base.document.notes[index].id) } : nil
        case .block:
            items.first { $0.anchor.matches(BlockAnchor(page: example.page, box: example.box)) }
                ?? items.filter { !$0.kind.isNote }.max { overlap($0.box, example.box) < overlap($1.box, example.box) }
                .flatMap { overlap($0.box, example.box) > 0 ? $0 : nil }
        }
        if let target {
            select(itemID: target.id)
        }
    }

    // MARK: - Wording

    /// What sets `style` apart from body text, judged by its typical look
    /// with the buckets the grouping uses: size, ink, alignment, width,
    /// lines, place on the page.
    nonisolated static func features(of style: Styles.Style) -> [StyleFeature] {
        let look = style.typical
        return sizeAndInk(of: look) + alignmentAndWidth(of: look) + lines(of: look)
    }

    /// `pages` (0-based, ascending) as runs of consecutive page numbers,
    /// counting from 1, for saying where a style's blocks are ("3–5, 9").
    nonisolated static func pageRanges(_ pages: [Int]) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        for page in pages.map({ $0 + 1 }) {
            if let last = ranges.last, page <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound ... max(page, last.upperBound)
            } else {
                ranges.append(page ... page)
            }
        }
        return ranges
    }
}

extension ReviewModel {
    private nonisolated static func sizeAndInk(of look: BlockStyle) -> [StyleFeature] {
        let rounded = (look.lineHeight * 10).rounded() / 10
        var features: [StyleFeature] = []
        let size = StyleGrouping.lineHeightBucket(of: look) ?? 0
        if size > 0 {
            features.append(.taller(rounded))
        } else if size < 0 {
            features.append(.smaller(rounded))
        }
        let ink = StyleGrouping.inkBucket(of: look) ?? 0
        if look.rule == .bodySizeBold || ink > 0 {
            features.append(.heavier)
        } else if ink < 0 {
            features.append(.lighter)
        }
        return features
    }

    private nonisolated static func alignmentAndWidth(of look: BlockStyle) -> [StyleFeature] {
        let alignment: [StyleFeature] = switch look.alignment {
        case .margin: []
        case .indented: [.indented]
        case .centered: [.centered]
        case .right: [.right]
        }
        return alignment + (look.width >= StyleGrouping.fullWidth ? [.fullWidth] : [])
    }

    private nonisolated static func lines(of look: BlockStyle) -> [StyleFeature] {
        var features: [StyleFeature] = look.lineCount > 1 ? [.lines(look.lineCount)] : []
        switch look.zone {
        case .top: features.append(.topEdge)
        case .bottom: features.append(.bottomEdge)
        case .body: break
        }
        if look.isUnderPicture {
            features.append(.underPicture)
        }
        if look.opensWithNoteLabel {
            features.append(.opensWithNoteLabel)
        }
        return features
    }

    /// The positions of `count` entries of `pages` (each entry's page, in
    /// order) spread across the document: with enough pages one from each of
    /// `count` pages evenly spaced from the first to the last, otherwise one
    /// from every page in turn until `count` are taken. Ascending.
    nonisolated static func spread(pages: [Int], count: Int) -> [Int] {
        var byPage: [Int: [Int]] = [:]
        var order: [Int] = []
        for (position, page) in pages.enumerated() {
            if byPage[page] == nil {
                order.append(page)
            }
            byPage[page, default: []].append(position)
        }
        guard count > 0, !order.isEmpty else { return [] }
        if order.count >= count {
            let step = count > 1 ? Double(order.count - 1) / Double(count - 1) : 0
            return (0 ..< count).compactMap { byPage[order[Int((Double($0) * step).rounded())]]?.first }
        }
        var chosen: [Int] = []
        var round = 0
        while chosen.count < min(count, pages.count) {
            for page in order {
                if let positions = byPage[page], positions.indices.contains(round), chosen.count < count {
                    chosen.append(positions[round])
                }
            }
            round += 1
        }
        return chosen.sorted()
    }

    /// Where a member starts: its page and area there.
    func place(of member: StyleMember) -> PageArea? {
        let base = project.base
        switch member {
        case let .block(index):
            return base.blockSources.indices.contains(index) ? base.blockSources[index].start : nil
        case let .note(index):
            return base.noteSources.indices.contains(index) ? base.noteSources[index].start : nil
        case let .pageFurniture(index):
            let furniture = base.styles?.pageFurniture ?? []
            return furniture.indices.contains(index) ? furniture[index].area : nil
        }
    }

    /// The recognized block or note text `item` stands for: by note, or by
    /// the place its block starts.
    private func member(of item: Item) -> StyleMember? {
        if case let .note(id) = item.id {
            return project.base.document.notes.firstIndex { $0.id == id }.map(StyleMember.note)
        }
        return recognizedBlock(at: item.anchor).map(StyleMember.block)
    }

    private func recognizedBlock(at anchor: BlockAnchor) -> Int? {
        let sources = project.base.blockSources
        return styleIndex.blocksByPage[anchor.page]?.first { anchor.matches(sources[$0]) }
    }

    /// The members the corrections act on, by the anchors they name.
    func correctedStyleMembers() -> [StyleMember: ExampleMark] {
        guard styles != nil else { return [:] }
        let base = project.base
        var marks: [StyleMember: ExampleMark] = [:]
        func mark(_ anchor: BlockAnchor, _ mark: ExampleMark) {
            var members = recognizedBlock(at: anchor).map { [StyleMember.block($0)] } ?? []
            if members.isEmpty, let note = base.noteSources.firstIndex(where: { anchor.matches($0) }) {
                members = [.note(note)]
            }
            for member in members where marks[member] != .ignored {
                marks[member] = mark
            }
        }
        for correction in project.corrections.corrections {
            switch correction {
            case let .retype(anchor, type): mark(anchor, type == .ignored ? .ignored : .corrected)
            case let .edit(anchor, _, _), let .split(anchor, _, _): mark(anchor, .corrected)
            case let .merge(first, second):
                mark(first, .corrected)
                mark(second, .corrected)
            case .replaceWord: break
            }
        }
        return marks
    }

    private func overlap(_ one: CGRect, _ other: CGRect) -> CGFloat {
        let common = one.intersection(other)
        return common.isNull ? 0 : common.width * common.height
    }
}

/// A document's styles, grouped once when the review opens, with what it
/// takes to find the style of a block.
struct StyleIndex {
    /// `nil` for a project without styles.
    let styles: [Styles.Style]?
    let sections: [ReviewModel.StyleSection]
    /// The style of each block, note text and line of page furniture, by its
    /// index in ``styles``.
    let memberStyle: [StyleMember: Int]
    /// The recognized blocks that start on each page, by index.
    let blocksByPage: [Int: [Int]]
    /// The warnings of the styles that are probably wrong, by style.
    let warnings: [Styles.Style.ID: StyleWarning]

    init(base: Conversion, detector: SuspiciousWordDetector) {
        let styles = base.styles.map {
            StyleGrouping.styles(
                blocks: base.document.blocks, blockSources: base.blockSources, noteSources: base.noteSources,
                styles: $0
            )
        }
        self.styles = styles
        sections = Dictionary(grouping: styles ?? [], by: \.type)
            .map {
                ReviewModel.StyleSection(type: $0.key, styles: $0.value.sorted { $0.paletteIndex < $1.paletteIndex })
            }
            .sorted { $0.type < $1.type }
        memberStyle = Dictionary(
            (styles ?? []).enumerated().flatMap { index, style in style.members.map { ($0, index) } }
        ) { first, _ in first }
        blocksByPage = Dictionary(grouping: base.blockSources.indices) { base.blockSources[$0].page }
        if let styles, let blockStyles = base.styles {
            let misrecognized = Self.misrecognized(in: styles, document: base.document, detector: detector)
            warnings = Dictionary(uniqueKeysWithValues: styles.compactMap { style in
                StyleWarning(
                    for: style, in: blockStyles, blocks: base.document.blocks, misrecognized: misrecognized
                ).map { (style.id, $0) }
            })
        } else {
            warnings = [:]
        }
    }
}
