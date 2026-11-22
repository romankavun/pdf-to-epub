// swiftlint:disable:next blanket_disable_command
// swiftlint:disable all
// PROTOTYPE - throwaway. Lives on the `prototype/style-overview` branch only.
//
// Question: what should the style overview look like?
// Three structurally different variants, switched from the floating bar at
// the bottom (or ← / →). Opened from the summary's "Style Overview
// (Prototype)" button in Debug builds.
//
// Styles here are guessed from block boxes only (type, alignment, page zone,
// height). The real feature takes them from layout analysis, with the
// deciding rule; the "why" text below is a stand-in for it.

#if DEBUG
    import AppModel
    import Corrections
    import ImageIO
    import SwiftUI

    // MARK: - Data

    struct ProtoMember: Identifiable {
        var id: ReviewModel.ItemID
        var anchor: BlockAnchor
        var pageIndex: Int
        var url: URL
        var box: CGRect
        var text: String
        var misrecognized: Bool
    }

    enum ProtoGroup: Int, CaseIterable, Identifiable {
        case heading1, heading2, heading3, paragraph, figure, note, ignored, removed
        var id: Int {
            rawValue
        }

        var title: String {
            switch self {
            case .heading1: "Heading 1"
            case .heading2: "Heading 2"
            case .heading3: "Heading 3"
            case .paragraph: "Paragraphs"
            case .figure: "Figures and captions"
            case .note: "Note texts"
            case .ignored: "Ignored blocks"
            case .removed: "Removed running headers and footers"
            }
        }

        var symbol: String {
            switch self {
            case .heading1, .heading2, .heading3: "textformat.size"
            case .paragraph: "text.alignleft"
            case .figure: "photo"
            case .note: "note.text"
            case .ignored: "eye.slash"
            case .removed: "scissors"
            }
        }

        var hue: Double {
            switch self {
            case .heading1: 0.0
            case .heading2: 0.07
            case .heading3: 0.13
            case .paragraph: 0.6
            case .figure: 0.8
            case .note: 0.48
            case .ignored: 0.0
            case .removed: 0.0
            }
        }
    }

    struct ProtoStyle: Identifiable {
        var id: String
        var group: ProtoGroup
        var index: Int
        var rule: String
        var members: [ProtoMember]
        var warning: String?

        var name: String {
            "\(group.title) · style \(index)"
        }

        var pagesText: String {
            let pages = Set(members.map(\.pageIndex)).sorted()
            guard let first = pages.first, let last = pages.last else { return "" }
            let span = first == last ? "p. \(first + 1)" : "pp. \(first + 1)–\(last + 1)"
            return "\(members.count) block\(members.count == 1 ? "" : "s") on \(pages.count) page\(pages.count == 1 ? "" : "s"), \(span)"
        }

        var color: Color {
            if group == .ignored || group == .removed {
                return .gray
            }
            let brightness = 0.85 - Double(index - 1).truncatingRemainder(dividingBy: 4) * 0.15
            return Color(hue: group.hue, saturation: 0.75, brightness: brightness)
        }
    }

    @MainActor
    enum ProtoStyles {
        static func make(from pages: [ReviewModel.Page]) -> [ProtoStyle] {
            var seen = Set<ReviewModel.ItemID>()
            var members: [(group: ProtoGroup, key: String, rule: String, member: ProtoMember)] = []
            let paragraphLefts = pages.flatMap(\.items).filter { $0.kind == .paragraph }.map(\.box.minX).sorted()
            let margin = paragraphLefts.isEmpty ? 0.1 : paragraphLefts[paragraphLefts.count / 2]
            for (pageIndex, page) in pages.enumerated() {
                for item in page.items where !seen.contains(item.id) {
                    seen.insert(item.id)
                    let group: ProtoGroup = switch item.kind {
                    case let .heading(level): level <= 1 ? .heading1 : level == 2 ? .heading2 : .heading3
                    case .paragraph: .paragraph
                    case .figure: .figure
                    case .note: .note
                    case .ignored: .ignored
                    }
                    let box = item.box
                    let align = if abs(box.midX - 0.5) < 0.03, box.width < 0.8 {
                        "centred"
                    } else if box.minX > 0.5 {
                        "right"
                    } else if box.minX > margin + 0.02 {
                        "indented"
                    } else {
                        "at the margin"
                    }
                    let zone = box.minY < 0.1 ? "top edge" : box.maxY > 0.9 ? "bottom edge" : "body"
                    let width = box.width > 0.7 ? "full width" : "narrow"
                    let size: String = switch group {
                    case .paragraph, .note: box.height < 0.025 ? "one line" : "several lines"
                    case .figure: box.height > 0.6 ? "full page" : "part page"
                    default: "\(Int((box.height * 100 / 1.5).rounded() * 1.5))% of page tall"
                    }
                    let key = "\(group.rawValue)|\(align)|\(zone)|\(width)|\(size)"
                    let rule = "\(size), \(align), \(width), \(zone)"
                    let member = ProtoMember(
                        id: item.id, anchor: item.anchor, pageIndex: pageIndex, url: page.url, box: box,
                        text: item.runs.map(\.text).joined(), misrecognized: item.isProbablyMisrecognized
                    )
                    members.append((group, key, rule, member))
                }
            }
            var byKey: [String: ProtoStyle] = [:]
            for entry in members {
                byKey[entry.key, default: ProtoStyle(
                    id: entry.key, group: entry.group, index: 0, rule: entry.rule, members: []
                )].members.append(entry.member)
            }
            var styles: [ProtoStyle] = []
            for group in ProtoGroup.allCases {
                let inGroup = byKey.values.filter { $0.group == group }.sorted { $0.members.count > $1.members.count }
                for (offset, var style) in inGroup.enumerated() {
                    style.index = offset + 1
                    style.warning = warning(for: style)
                    styles.append(style)
                }
            }
            return styles
        }

        private static func warning(for style: ProtoStyle) -> String? {
            let pages = Set(style.members.map(\.pageIndex)).count
            let isHeading = [.heading1, .heading2, .heading3].contains(style.group)
            if isHeading, style.rule.contains("edge"), pages >= 3 {
                return "A heading at the page edge on \(pages) pages: maybe a running header"
            }
            if style.group == .paragraph, style.rule.hasPrefix("one line"), style.rule.contains("full width"),
               style.members.count >= 5
            {
                return "Many one-line paragraphs across the full width: lines may not have been joined"
            }
            let bad = style.members.count(where: \.misrecognized)
            if bad * 2 > style.members.count, bad > 0 {
                return "Mostly text probably misrecognized"
            }
            return nil
        }
    }

    // MARK: - Images

    struct ProtoImage: @unchecked Sendable {
        let image: CGImage
    }

    actor ProtoImageLoader {
        static let shared = ProtoImageLoader()
        private var pages: [URL: CGImage] = [:]
        private var order: [URL] = []
        private var thumbnails: [URL: CGImage] = [:]

        func crop(_ url: URL, _ box: CGRect) -> ProtoImage? {
            guard let page = page(url) else { return nil }
            let width = CGFloat(page.width), height = CGFloat(page.height)
            let rect = CGRect(
                x: box.minX * width - 6, y: box.minY * height - 6,
                width: box.width * width + 12, height: box.height * height + 12
            ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            return page.cropping(to: rect).map(ProtoImage.init)
        }

        func thumbnail(_ url: URL) -> ProtoImage? {
            if let cached = thumbnails[url] {
                return ProtoImage(image: cached)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            thumbnails[url] = image
            return ProtoImage(image: image)
        }

        private func page(_ url: URL) -> CGImage? {
            if let cached = pages[url] {
                return cached
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(
                      source,
                      0,
                      [kCGImageSourceShouldCache: true] as CFDictionary
                  )
            else { return nil }
            pages[url] = image
            order.append(url)
            if order.count > 24 {
                pages[order.removeFirst()] = nil
            }
            return image
        }
    }

    struct ProtoCrop: View {
        var member: ProtoMember
        var height: CGFloat = 64
        @State private var image: ProtoImage?

        var body: some View {
            Group {
                if let image {
                    Image(decorative: image.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                        .frame(width: height * 3)
                }
            }
            .frame(height: height)
            .frame(maxWidth: 360)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            .task(id: member.id) {
                image = await ProtoImageLoader.shared.crop(member.url, member.box)
            }
        }
    }

    // MARK: - Host

    struct StyleOverviewPrototype: View {
        var model: ReviewModel
        var done: () -> Void
        var open: (_ pageIndex: Int, _ itemID: ReviewModel.ItemID?) -> Void
        @AppStorage("prototype.styleOverview.variant") private var variant = 0
        @State private var styles: [ProtoStyle] = []

        private let names = ["A: Rows by type", "B: Styles and their blocks", "C: Pages coloured by style"]

        var body: some View {
            VStack(spacing: 12) {
                HStack {
                    Button("Back to Summary", systemImage: "chevron.backward", action: done)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Text(verbatim: "Style overview (prototype): \(styles.count) styles")
                        .font(.headline)
                    Spacer()
                }
                Group {
                    switch variant {
                    case 1: ProtoVariantB(styles: styles, open: open)
                    case 2: ProtoVariantC(styles: styles, pages: model.pages, open: open)
                    default: ProtoVariantA(styles: styles, open: open)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) { switcher }
            .onAppear { styles = ProtoStyles.make(from: model.pages) }
        }

        private var switcher: some View {
            HStack(spacing: 14) {
                Button { variant = (variant + names.count - 1) % names.count } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Text(verbatim: names[min(variant, names.count - 1)])
                    .font(.callout.monospaced())
                    .frame(minWidth: 240)
                Button { variant = (variant + 1) % names.count } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.85)))
            .shadow(radius: 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Shared bits

    struct ProtoStyleSummary: View {
        var style: ProtoStyle

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(style.color).frame(width: 10, height: 10)
                    Text(verbatim: style.name).font(.headline)
                }
                Text(verbatim: "Why: \(style.rule)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(verbatim: style.pagesText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = style.warning {
                    Label { Text(verbatim: warning) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    struct ProtoRemovedPlaceholder: View {
        var body: some View {
            Label {
                Text(
                    verbatim: "Removed running headers and footers: not kept by the conversion yet (needs layout analysis to keep them)."
                )
            } icon: {
                Image(systemName: ProtoGroup.removed.symbol)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Variant A: one long list of rows, grouped by type

    struct ProtoVariantA: View {
        var styles: [ProtoStyle]
        var open: (Int, ReviewModel.ItemID?) -> Void

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: .sectionHeaders) {
                    ForEach(ProtoGroup.allCases) { group in
                        let inGroup = styles.filter { $0.group == group }
                        if group == .removed || !inGroup.isEmpty {
                            Section {
                                if group == .removed {
                                    ProtoRemovedPlaceholder().padding(.horizontal, 12)
                                }
                                ForEach(inGroup) { style in row(style) }
                            } header: {
                                Label { Text(verbatim: "\(group.title) (\(inGroup.count))") } icon: {
                                    Image(systemName: group.symbol)
                                }
                                .font(.title3.bold())
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                            }
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }

        private func row(_ style: ProtoStyle) -> some View {
            HStack(alignment: .top, spacing: 16) {
                ProtoStyleSummary(style: style)
                    .frame(width: 280, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(style.members.prefix(4)) { member in
                            Button { open(member.pageIndex, member.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    ProtoCrop(member: member)
                                    Text(verbatim: "p. \(member.pageIndex + 1)").font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Open the review on this block")
                        }
                        if style.members.count > 4 {
                            Text(verbatim: "+\(style.members.count - 4) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
            .overlay(alignment: .leading) {
                Rectangle().fill(style.color).frame(width: 4)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Variant B: list of styles on the left, every block of the selected one on the right

    struct ProtoVariantB: View {
        var styles: [ProtoStyle]
        var open: (Int, ReviewModel.ItemID?) -> Void
        @State private var selection: ProtoStyle.ID?

        var body: some View {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(ProtoGroup.allCases) { group in
                        let inGroup = styles.filter { $0.group == group }
                        if group == .removed || !inGroup.isEmpty {
                            Section {
                                ForEach(inGroup) { style in
                                    HStack {
                                        Circle().fill(style.color).frame(width: 9, height: 9)
                                        Text(verbatim: "Style \(style.index)")
                                        if style.warning != nil {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        }
                                        Spacer()
                                        Text(verbatim: "\(style.members.count)").foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .tag(style.id)
                                }
                                if group == .removed {
                                    Text(verbatim: "Not kept yet").foregroundStyle(.secondary)
                                }
                            } header: {
                                Label { Text(verbatim: group.title) } icon: { Image(systemName: group.symbol) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 280)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { selection = selection ?? styles.first?.id }
        }

        @ViewBuilder private var detail: some View {
            if let style = styles.first(where: { $0.id == (selection ?? styles.first?.id) }) {
                VStack(alignment: .leading, spacing: 12) {
                    ProtoStyleSummary(style: style).padding([.horizontal, .top], 16)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                            ForEach(style.members) { member in
                                Button { open(member.pageIndex, member.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProtoCrop(member: member, height: 80)
                                        Text(verbatim: "p. \(member.pageIndex + 1)  \(member.text.prefix(60))")
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 50)
                    }
                }
            } else {
                ContentUnavailableView("Choose a style", systemImage: "square.stack.3d.up")
            }
        }
    }

    // MARK: - In Review: the sidebar and the blocks of the selected style

    /// The styles as recognition left them (Q4): computed from the base
    /// conversion, not the corrected one.
    @MainActor
    func protoRecognizedStyles(of model: ReviewModel) -> [ProtoStyle] {
        ProtoStyles.make(from: ReviewModel(conversion: model.project.base).pages)
    }

    struct ProtoStyleSidebar: View {
        var styles: [ProtoStyle]
        @Binding var selection: ProtoStyle.ID?

        var body: some View {
            List(selection: $selection) {
                ForEach(ProtoGroup.allCases) { group in
                    let inGroup = styles.filter { $0.group == group }
                    if group == .removed || !inGroup.isEmpty {
                        Section {
                            ForEach(inGroup) { style in
                                HStack {
                                    Circle().fill(style.color).frame(width: 9, height: 9)
                                    Text(verbatim: "Style \(style.index)")
                                    if style.warning != nil {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    }
                                    Spacer()
                                    Text(verbatim: "\(style.members.count)").foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .help(style.rule)
                                .tag(style.id)
                            }
                            if group == .removed {
                                Text(verbatim: "Not kept yet").foregroundStyle(.secondary)
                            }
                        } header: {
                            Label { Text(verbatim: group.title) } icon: { Image(systemName: group.symbol) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    struct ProtoStyleBlocks: View {
        var style: ProtoStyle
        var open: (ProtoMember) -> Void
        var close: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    ProtoStyleSummary(style: style)
                    Spacer()
                    Button("Back to Blocks", systemImage: "xmark.circle.fill", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Show the page's blocks again")
                }
                .padding(.horizontal, 12)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(style.members) { member in
                            Button { open(member) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    ProtoCrop(member: member, height: 60)
                                    Text(verbatim: "p. \(member.pageIndex + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Show this block on its page")
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    // MARK: - Variant C: every page as a thumbnail, blocks coloured by style

    struct ProtoVariantC: View {
        var styles: [ProtoStyle]
        var pages: [ReviewModel.Page]
        var open: (Int, ReviewModel.ItemID?) -> Void
        @State private var highlighted: ProtoStyle.ID?

        var body: some View {
            let styleOf = Dictionary(styles.flatMap { style in style.members.map { ($0.id, style) } }) { first, _ in
                first
            }
            HStack(spacing: 0) {
                legend.frame(width: 300)
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 14) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            let shown = highlighted
                                .map { id in page.items.contains { styleOf[$0.id]?.id == id } } ?? true
                            Button { open(index, nil) } label: {
                                VStack(spacing: 2) {
                                    ProtoPageThumb(page: page, styleOf: styleOf, highlighted: highlighted)
                                    Text(verbatim: "\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                                }
                                .opacity(shown ? 1 : 0.25)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 50)
                }
            }
        }

        private var legend: some View {
            List {
                Text(verbatim: "Click a style to show where it is used; click again to show all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ProtoGroup.allCases) { group in
                    let inGroup = styles.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        Section(group.title) {
                            ForEach(inGroup) { style in
                                Button {
                                    highlighted = highlighted == style.id ? nil : style.id
                                } label: {
                                    HStack(alignment: .top) {
                                        RoundedRectangle(cornerRadius: 2).fill(style.color).frame(width: 14, height: 14)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: "Style \(style.index): \(style.rule)").font(.callout)
                                            Text(verbatim: style.pagesText).font(.caption).foregroundStyle(.secondary)
                                            if let warning = style.warning {
                                                Text(verbatim: warning).font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    .padding(4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(highlighted == style.id ? style.color.opacity(0.2) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section(ProtoGroup.removed.title) { ProtoRemovedPlaceholder() }
            }
        }
    }

    struct ProtoPageThumb: View {
        var page: ReviewModel.Page
        var styleOf: [ReviewModel.ItemID: ProtoStyle]
        var highlighted: ProtoStyle.ID?
        @State private var image: ProtoImage?

        var body: some View {
            ZStack {
                if let image {
                    Image(decorative: image.image, scale: 1).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(0.7, contentMode: .fit)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    ForEach(page.items) { item in
                        let style = styleOf[item.id]
                        let isOn = highlighted == nil || style?.id == highlighted
                        Rectangle()
                            .fill((style?.color ?? .gray).opacity(isOn ? 0.45 : 0.05))
                            .frame(
                                width: item.box.width * geometry.size.width,
                                height: item.box.height * geometry.size.height
                            )
                            .position(x: item.box.midX * geometry.size.width, y: item.box.midY * geometry.size.height)
                    }
                }
            }
            .background(.white)
            .overlay(Rectangle().stroke(.separator))
            .task(id: page.url) { image = await ProtoImageLoader.shared.thumbnail(page.url) }
        }
    }
#endif
