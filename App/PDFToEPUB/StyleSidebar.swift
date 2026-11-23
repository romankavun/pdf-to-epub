import AppModel
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
                        StyleRow(style: style)
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

/// A style in the sidebar: its colour, name and number of blocks.
private struct StyleRow: View {
    var style: Styles.Style

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(style.color)
                .frame(width: 9, height: 9)
            Text(style.name)
                .lineLimit(1)
                .truncationMode(.middle)
            // The slot for the probably-wrong mark (#35).
            Spacer(minLength: 4)
            Text(style.members.count.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help(style.featuresText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("styleRow")
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(model.examples(of: style, limit: showsAll ? nil : ReviewModel.exampleCount)) { example in
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(style.name).font(.headline)
                } icon: {
                    Circle().fill(style.color).frame(width: 10, height: 10)
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
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 90)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            HStack(spacing: 6) {
                Text("p. \(example.page + 1)")
                    .monospacedDigit()
                switch example.mark {
                case .corrected:
                    Label("corrected", systemImage: "pencil.circle.fill")
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
