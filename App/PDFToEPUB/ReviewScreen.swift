// PROTOTYPE (style overview): lint relaxed on the prototype branch only.
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable large_tuple
import AppModel
import Corrections
import SwiftUI

/// The page scan next to the blocks recognized on it, with suspicious
/// words highlighted and navigation between them.
struct ReviewScreen: View {
    @Bindable var model: ReviewModel
    var done: () -> Void
    #if DEBUG
        /// PROTOTYPE: the styles sidebar, off each time the review opens.
        @State private var showsStyles = false
        @State private var styles: [ProtoStyle] = []
        @State private var selectedStyle: ProtoStyle.ID?
    #endif

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if let page = model.currentPage {
                // Equal halves rather than a split view: a split view lets the
                // long text column squeeze the scan down to its minimum width.
                HStack(spacing: 16) {
                    #if DEBUG
                        if showsStyles {
                            ProtoStyleSidebar(styles: styles, selection: $selectedStyle)
                                .frame(width: 230)
                        }
                        PageScan(
                            page: page, selectedItemID: model.selectedItemID, select: model.select,
                            highlight: highlightedStyle.map { style in
                                Dictionary(style.members.map { ($0.anchor, style.color) }) { first, _ in first }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let style = highlightedStyle {
                            ProtoStyleBlocks(style: style, open: openStyleMember) { selectedStyle = nil }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            BlockList(page: page, model: model, styleLink: styleLink)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    #else
                        PageScan(page: page, selectedItemID: model.selectedItemID, select: model.select)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        BlockList(page: page, model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif
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
        #if DEBUG
        // PROTOTYPE: room for the sidebar, the scan and the right column.
        .frame(minWidth: showsStyles ? 1180 : nil)
        .task {
            if styles.isEmpty {
                styles = protoRecognizedStyles(of: model)
            }
        }
        #endif
    }

    #if DEBUG
        private var highlightedStyle: ProtoStyle? {
            guard showsStyles, let selectedStyle else { return nil }
            return styles.first { $0.id == selectedStyle }
        }

        private func styleLink(_ item: ReviewModel.Item) -> (name: String, color: Color, open: () -> Void)? {
            guard let style = styles.first(where: { style in style.members.contains { $0.anchor == item.anchor } })
            else { return nil }
            return (style.name, style.color, {
                showsStyles = true
                selectedStyle = style.id
            })
        }

        private func openStyleMember(_ member: ProtoMember) {
            model.goToPage(member.pageIndex)
            if let item = model.currentPage?.items.first(where: { $0.anchor == member.anchor }) {
                model.select(itemID: item.id)
            }
            selectedStyle = nil
        }
    #endif

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Back to Summary", systemImage: "chevron.backward", action: done)
                // Esc belongs to the text editor while one is open.
                .keyboardShortcut(model.editingItemID == nil ? .cancelAction : nil)
            #if DEBUG
                Toggle(isOn: $showsStyles) {
                    Label { Text(verbatim: "Styles") } icon: { Image(systemName: "sidebar.left") }
                }
                .toggleStyle(.button)
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help("PROTOTYPE: show the document's styles (⌃⌘S)")
                .onChange(of: showsStyles) {
                    if !showsStyles {
                        selectedStyle = nil
                    }
                }
            #endif
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
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .labelStyle(.iconOnly)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo || model.isEditing)
            #if DEBUG
                // PROTOTYPE: issues and spelling belong to the block list, which a
                // style's blocks replace.
                if highlightedStyle == nil {
                    issueNavigation
                }
            #else
                issueNavigation
            #endif
        }
    }

    @ViewBuilder private var issueNavigation: some View {
        if model.flaggedItemCount == 0 {
            Label("No issues found", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            if let position = model.issuePosition {
                Text("Issue \(position) of \(model.flaggedItemCount)")
                    .monospacedDigit()
                    .accessibilityIdentifier("issueCounter")
            } else {
                // The page's own number first: a document total alone looks the
                // same on every page.
                Text("Issues: \(model.issueCountOnPage) on this page, \(model.flaggedItemCount) in the document")
                    .monospacedDigit()
                    .help("Suspicious words, text probably misrecognized and pages that may have lost text.")
                    .accessibilityIdentifier("issueCounter")
            }
            Button("Previous Issue", systemImage: "chevron.up", action: model.goToPreviousIssue)
                .labelStyle(.iconOnly)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Next Issue", systemImage: "chevron.down", action: model.goToNextIssue)
                .accessibilityIdentifier("nextIssueButton")
                .keyboardShortcut("g")
        }
        Divider().frame(height: 16)
        Toggle("Spelling", isOn: $model.showsSpelling)
            .toggleStyle(.button)
            .help("Mark words the dictionary does not know. Noisy: names and rare words are marked too.")
        if model.showsSpelling {
            if let position = model.misspellingPosition {
                Text("Misspelling \(position) of \(model.misspelledItemCount)")
                    .monospacedDigit()
            } else {
                Text("Misspelled words: \(model.misspellingCount)")
            }
            Button("Previous Misspelling", systemImage: "chevron.up", action: model.goToPreviousMisspelling)
                .labelStyle(.iconOnly)
                .keyboardShortcut("g", modifiers: [.command, .shift, .option])
                .disabled(model.misspelledItemCount == 0)
            Button("Next Misspelling", systemImage: "chevron.down", action: model.goToNextMisspelling)
                .labelStyle(.iconOnly)
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(model.misspelledItemCount == 0)
        }
    }
}

/// The blocks and note texts on the page, top to bottom.
private struct BlockList: View {
    var page: ReviewModel.Page
    var model: ReviewModel
    /// PROTOTYPE: the style link of a block, if its style is known.
    var styleLink: (ReviewModel.Item) -> (name: String, color: Color, open: () -> Void)? = { _ in nil }

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
                                isSelected: item.id == model.selectedItemID,
                                styleLink: styleLink(item)
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
