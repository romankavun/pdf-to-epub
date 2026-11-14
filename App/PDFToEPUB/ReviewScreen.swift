import AppModel
import Corrections
import SwiftUI

/// The page scan next to the blocks recognized on it, with suspicious
/// words highlighted and navigation between them.
struct ReviewScreen: View {
    @Bindable var model: ReviewModel
    var done: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if let page = model.currentPage {
                // Equal halves rather than a split view: a split view lets the
                // long text column squeeze the scan down to its minimum width.
                HStack(spacing: 16) {
                    PageScan(page: page, selectedItemID: model.selectedItemID, select: model.select)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BlockList(page: page, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("The document has no pages", systemImage: "doc")
            }
            if model.proposal != nil {
                ProposalBar(model: model)
            }
            if let error = model.project.saveError {
                Label("Corrections could not be saved: \(error)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Back to Summary", systemImage: "chevron.backward", action: done)
                // Esc belongs to the text editor while one is open.
                .keyboardShortcut(model.editingItemID == nil ? .cancelAction : nil)
            Spacer()
            Button("Previous Page", systemImage: "chevron.left", action: model.goToPreviousPage)
                .labelStyle(.iconOnly)
                .keyboardShortcut("[")
                .disabled(!model.canGoToPreviousPage)
            Text("Page \(model.pageIndex + 1) of \(model.pages.count)")
                .monospacedDigit()
            Button("Next Page", systemImage: "chevron.right", action: model.goToNextPage)
                .labelStyle(.iconOnly)
                .keyboardShortcut("]")
                .disabled(!model.canGoToNextPage)
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .labelStyle(.iconOnly)
                .keyboardShortcut("z")
                .disabled(!model.canUndo || model.isEditing)
            issueNavigation
        }
    }

    @ViewBuilder private var issueNavigation: some View {
        if model.flaggedItemCount == 0 {
            Label("No suspicious words", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            if let position = model.issuePosition {
                Text("Issue \(position) of \(model.flaggedItemCount)")
                    .monospacedDigit()
            } else {
                Text("Suspicious words: \(model.issueCount)")
            }
            Button("Previous Issue", systemImage: "chevron.up", action: model.goToPreviousIssue)
                .labelStyle(.iconOnly)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Next Issue", systemImage: "chevron.down", action: model.goToNextIssue)
                .keyboardShortcut("g")
        }
    }
}

/// The page image with the area of every block outlined; clicking an area
/// puts its block in focus.
private struct PageScan: View {
    var page: ReviewModel.Page
    var selectedItemID: ReviewModel.Item.ID?
    var select: (ReviewModel.Item.ID) -> Void

    var body: some View {
        AsyncImage(url: page.url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .overlay { GeometryReader { outlines(in: $0.size) } }
            case .failure:
                ContentUnavailableView("Could not load the page image", systemImage: "photo")
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
            }
        }
        // A new page must not show the previous page's image while loading.
        .id(page.url)
    }

    private func outlines(in size: CGSize) -> some View {
        ForEach(page.items) { item in
            let isSelected = item.id == selectedItemID
            let color = item.outlineColor
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 0.25 : 0.001))
                .stroke(color.opacity(isSelected ? 1 : 0.35), lineWidth: isSelected ? 2 : 1)
                .frame(width: item.box.width * size.width + 6, height: item.box.height * size.height + 6)
                .position(x: item.box.midX * size.width, y: item.box.midY * size.height)
                .onTapGesture { select(item.id) }
        }
    }
}

/// The blocks and note texts on the page, top to bottom.
private struct BlockList: View {
    var page: ReviewModel.Page
    var model: ReviewModel

    var body: some View {
        if page.items.isEmpty {
            ContentUnavailableView(
                "No text on this page",
                systemImage: "text.page.slash",
                description: Text("It is a cover or a blank page.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(page.items) { item in
                            BlockCard(
                                model: model,
                                item: item,
                                image: figureImage(for: item),
                                isSelected: item.id == model.selectedItemID
                            )
                            .id(item.id)
                            .onTapGesture { model.select(itemID: item.id) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: model.selectedItemID, initial: true) { _, selected in
                    guard let selected else { return }
                    withAnimation { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }

    private func figureImage(for item: ReviewModel.Item) -> NSImage? {
        guard case let .figure(imageID) = item.kind else { return nil }
        return model.images[imageID].flatMap(NSImage.init(data:))
    }
}

/// One block: what it is, its text with flagged words highlighted, and for
/// a figure the cropped picture.
private struct BlockCard: View {
    @Bindable var model: ReviewModel
    var item: ReviewModel.Item
    var image: NSImage?
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kindName)
                    .font(.caption)
                    .foregroundStyle(item.kind.isNote ? AnyShapeStyle(item.outlineColor) : AnyShapeStyle(.secondary))
                if item.continuesFromPreviousPage {
                    Label("Continued from the previous page", systemImage: "arrow.turn.left.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.issueCount > 0 {
                    Label("\(item.issueCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
            }
            if isEditing {
                editor
            } else if !item.runs.isEmpty {
                Text(attributedText)
                    .font(isHeading ? .title3.bold() : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.continuesOnNextPage {
                Label("Continues on the next page", systemImage: "arrow.turn.right.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isSelected, !isEditing {
                actions
            }
        }
        .opacity(item.kind == .ignored ? 0.6 : 1)
        .padding(10)
        .background(
            isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.quinary),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isEditing: Bool {
        model.editingItemID == item.id
    }

    /// The text of the block as plain text: note references are shown in
    /// brackets and must stay in them to stay in the document.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.draft)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
            Text("A note reference is shown in ⟦ ⟧ brackets; keep them to keep the note.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: model.cancelEditing)
                    .keyboardShortcut(.cancelAction)
                Button("Save Text", action: model.commitEditing)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// What can be done to the selected block.
    private var actions: some View {
        HStack {
            switch item.kind {
            case .ignored:
                Button("Bring Back", systemImage: "arrow.uturn.backward", action: model.resetSelectedType)
            case .note:
                Button("Edit Text", systemImage: "pencil", action: model.beginEditing)
            case .figure:
                Button("Edit Caption", systemImage: "pencil", action: model.beginEditing)
                Button("Ignore", systemImage: "eye.slash") { model.setSelectedType(.ignored) }
            case .heading, .paragraph:
                Button("Edit Text", systemImage: "pencil", action: model.beginEditing)
                typeMenu
            }
        }
        .controlSize(.small)
    }

    private var typeMenu: some View {
        Menu("Type", systemImage: "textformat") {
            Button("Paragraph") { model.setSelectedType(.paragraph) }
            Button("Heading 1") { model.setSelectedType(.heading(level: 1)) }
            Button("Heading 2") { model.setSelectedType(.heading(level: 2)) }
            Button("Heading 3") { model.setSelectedType(.heading(level: 3)) }
            Divider()
            Button("Ignore", systemImage: "eye.slash") { model.setSelectedType(.ignored) }
            Button("Reset to Recognized Type", action: model.resetSelectedType)
        }
    }

    private var isHeading: Bool {
        if case .heading = item.kind {
            true
        } else {
            false
        }
    }

    private var kindName: LocalizedStringKey {
        switch item.kind {
        case let .heading(level): "Heading \(level)"
        case .paragraph: "Paragraph"
        case .figure: "Illustration"
        case let .note(label): "Note \(label)"
        case .ignored: "Ignored"
        }
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for run in item.runs {
            var part = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .emphasis:
                part.inlinePresentationIntent = .emphasized
            case .strong:
                part.inlinePresentationIntent = .stronglyEmphasized
            case .noteReference:
                part.font = .caption
                part.baselineOffset = 5
                part.foregroundColor = .accentColor
            }
            if run.reason != nil {
                part.backgroundColor = .orange.opacity(0.45)
                part.underlineStyle = .single
            }
            result += part
        }
        return result
    }
}

private extension ReviewModel.Kind {
    var isNote: Bool {
        if case .note = self {
            true
        } else {
            false
        }
    }
}

private extension ReviewModel.Item {
    /// Flagged blocks stand out; note texts are told apart from the body.
    var outlineColor: Color {
        if issueCount > 0 {
            .orange
        } else if kind.isNote {
            .teal
        } else if kind == .ignored {
            .gray
        } else {
            .accentColor
        }
    }
}
