import AppModel
import Corrections
import ImageIO
import Styles
import SwiftUI

/// Every style of the document, grouped by type; selecting one shows its
/// blocks in place of the block list.
struct StyleSidebar: View {
    var model: ReviewModel

    var body: some View {
        List(selection: Binding(get: { model.selectedStyleID }, set: model.selectStyle)) {
            ForEach(model.styleSections) { section in
                Section {
                    ForEach(section.styles) { style in
                        StyleRow(style: style, warning: model.warning(of: style))
                            .tag(style.id)
                    }
                } header: {
                    Label(section.type.sectionTitle, systemImage: section.type.symbol)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("styleSidebar")
    }
}

/// A style in the sidebar: its colour, title and number of blocks, with a
/// mark when it is probably wrong; the rule and look on a line below, cut
/// at the end when long, so the title always shows whole.
private struct StyleRow: View {
    var style: Styles.Style
    var warning: StyleWarning?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(style.color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(style.title)
                    .lineLimit(1)
                    .fixedSize()
                Text(style.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if warning != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Probably wrong")
                    .accessibilityIdentifier("styleWarningMark")
            }
            Text(style.members.count.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("styleRow")
    }

    /// The whole name and look, and why the style is probably wrong.
    private var helpText: String {
        [style.name, style.featuresText, warning?.text].compactMap(\.self).joined(separator: "\n")
    }
}

/// The selected style: its deciding rule in words, where its blocks are,
/// and examples of them; a click on one opens it on its page.
struct StyleBlocks: View {
    var model: ReviewModel
    var style: Styles.Style
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 12)
            ScrollView {
                let examples = model.examples(of: style, limit: showsAll ? nil : ReviewModel.exampleCount)
                LazyVGrid(columns: columns(for: examples), spacing: 10) {
                    ForEach(examples) { example in
                        Button {
                            model.open(example)
                        } label: {
                            ExampleCrop(example: example, url: model.pages[example.page].url)
                        }
                        .buttonStyle(.plain)
                        .help("Show this block on its page")
                        .accessibilityIdentifier("styleExample")
                    }
                }
                .padding(.horizontal, 12)
                if style.members.count > ReviewModel.exampleCount {
                    Button(showsAll ? "Show Fewer" : "Show All \(style.members.count)") { showsAll.toggle() }
                        .padding(12)
                        .accessibilityIdentifier("showAllExamples")
                }
            }
        }
        // Another style starts with its examples again.
        .id(style.id)
    }

    /// Tiles for most styles; one example per row when most examples are
    /// long strips such as full-width lines, which a tile would shrink
    /// past reading.
    private func columns(for examples: [ReviewModel.StyleExample]) -> [GridItem] {
        let strips = examples.filter(\.isStrip).count
        return strips * 2 > examples.count
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 180), spacing: 10)]
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(style.name).font(.headline)
                } icon: {
                    Circle().fill(style.color).frame(width: 10, height: 10)
                }
                if let warning = model.warning(of: style) {
                    Label {
                        Text("Probably wrong. \(warning.text)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("styleWarning")
                }
                Text(style.featuresText)
                Text("Deciding rule: \(style.rule.name)")
                    .foregroundStyle(.secondary)
                Text("Blocks: \(style.members.count) · corrected: \(model.correctedCount(of: style))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Pages: \(style.pagesText)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                changeTo
            }
            .font(.callout)
            .textSelection(.enabled)
            Spacer()
            Button("Back to Blocks", systemImage: "xmark.circle.fill") { model.selectStyle(nil) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Show the page's blocks again")
        }
    }
}

/// *Change to…* for a whole style, and what the last change did.
private extension StyleBlocks {
    @ViewBuilder var changeTo: some View {
        let choices = model.typeChoices(for: style)
        if !choices.isEmpty {
            Menu("Change to…") {
                ForEach(choices, id: \.self) { type in
                    if type == .ignored {
                        Divider()
                    }
                    Button(type.menuTitle) { model.changeType(of: style, to: type) }
                        .accessibilityIdentifier(type.menuIdentifier)
                }
            }
            .fixedSize()
            .help(
                // swiftlint:disable:next line_length
                "Gives every block of this style the type, as one step to undo. Blocks you already gave a type, merged or split are left as they are."
            )
            .accessibilityIdentifier("styleChangeTo")
        }
        if let change = model.styleTypeChange, change.style == style.id {
            Group {
                if change.skipped == 0 {
                    Text("Blocks changed: \(change.changed).")
                } else {
                    Text(
                        // swiftlint:disable:next line_length
                        "Blocks changed: \(change.changed). Left as they are: \(change.skipped) (you already gave them a type, merged or split them)."
                    )
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("styleChangeResult")
        }
    }
}

private extension BlockType {
    var menuTitle: LocalizedStringKey {
        switch self {
        case .paragraph: "Paragraph"
        case let .heading(level): "Heading \(level)"
        case .ignored: "Ignore"
        }
    }

    var menuIdentifier: String {
        switch self {
        case .paragraph: "styleTypeParagraph"
        case let .heading(level): "styleTypeHeading\(level)"
        case .ignored: "styleTypeIgnore"
        }
    }
}

/// One example: a crop of the page image, with its page number and a badge
/// when the user corrected or ignored the block.
private struct ExampleCrop: View {
    var example: ReviewModel.StyleExample
    var url: URL
    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: example.isStrip ? 120 : 90)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            HStack(spacing: 6) {
                Text("p. \(example.page + 1)")
                    .monospacedDigit()
                switch example.mark {
                case .corrected:
                    Label("Corrected", systemImage: "pencil.circle.fill")
                        .foregroundStyle(.blue)
                case .ignored:
                    Label("Ignored", systemImage: "eye.slash")
                case nil:
                    EmptyView()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .task(id: example) {
            image = await PageCrops.shared.crop(of: url, box: example.box)
        }
    }
}

private extension ReviewModel.StyleExample {
    /// Whether the block is a long strip: on a page about 0.7 as wide as
    /// it is tall, at least eight times as wide as it is high.
    var isStrip: Bool {
        box.height > 0 && box.width * 0.7 / box.height >= 8
    }
}

/// Crops of page images for examples, keeping the last few pages decoded
/// so that a style's examples on one page do not decode it again.
private actor PageCrops {
    static let shared = PageCrops()
    /// How many decoded pages are kept.
    private let capacity = 16
    private var pages: [URL: CGImage] = [:]
    private var recent: [URL] = []

    /// The part of the page at `url` under `box` (normalized, origin top-left),
    /// with a small margin.
    func crop(of url: URL, box: CGRect) -> CGImage? {
        guard let page = page(at: url) else { return nil }
        let size = CGSize(width: page.width, height: page.height)
        let margin = 0.006 * max(size.width, size.height)
        let rect = CGRect(
            x: box.minX * size.width, y: box.minY * size.height,
            width: box.width * size.width, height: box.height * size.height
        )
        .insetBy(dx: -margin, dy: -margin)
        .integral
        .intersection(CGRect(origin: .zero, size: size))
        return page.cropping(to: rect)
    }

    private func page(at url: URL) -> CGImage? {
        if let page = pages[url] {
            return page
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let page = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { return nil }
        pages[url] = page
        recent.append(url)
        if recent.count > capacity {
            pages[recent.removeFirst()] = nil
        }
        return page
    }
}
