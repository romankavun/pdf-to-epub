import AppModel
import SwiftUI

/// One block: what it is, its text with flagged words highlighted, and for
/// a figure the cropped picture.
struct BlockCard: View {
    @Bindable var model: ReviewModel
    var item: ReviewModel.Item
    var image: NSImage?
    var isSelected: Bool
    /// The run whose quick fixes are open.
    @State private var fixingRun: Int?
    @State private var isHovered = false
    /// The cursor or selection in the editor, for splitting at the cursor.
    @State private var selection: TextSelection?

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
                if model.showsSpelling, item.misspellingCount > 0 {
                    Label("\(item.misspellingCount)", systemImage: "textformat.abc.dottedunderline")
                        .font(.caption)
                        .foregroundStyle(.blue)
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
                    // Selectable text swallows clicks, so only the selected
                    // block has it: a click anywhere else selects the block.
                    .selectable(isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "fix", let index = Int(url.host() ?? "") else { return .discarded }
                        model.select(itemID: item.id)
                        fixingRun = index
                        return .handled
                    })
                if let index = fixingRun {
                    QuickFix(
                        model: model, itemID: item.id, runIndex: index,
                        word: item.runs.indices.contains(index) ? item.runs[index].text : ""
                    ) { fixingRun = nil }
                }
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
            isSelected ? AnyShapeStyle(.selection.opacity(0.35))
                : AnyShapeStyle(isHovered ? .quaternary : .quinary),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }

    private var isEditing: Bool {
        model.editingItemID == item.id
    }

    /// The text of the block as plain text: note references are shown in
    /// brackets and must stay in them to stay in the document.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.draft, selection: $selection)
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
                if isHeading || item.kind == .paragraph || item.kind.isNote {
                    Button("Split at Cursor", systemImage: "scissors", action: splitAtCursor)
                        .disabled(cursorOffset == nil || !model.canSplitEditing)
                        .help("Cuts the block in two at the cursor. Save the text first if you changed it.")
                }
            }
        }
    }

    /// The cursor's position in the draft, in characters; `nil` while text is
    /// selected or there is no cursor.
    private var cursorOffset: Int? {
        guard case let .selection(range)? = selection?.indices, range.isEmpty else { return nil }
        return model.draft.distance(from: model.draft.startIndex, to: range.lowerBound)
    }

    private func splitAtCursor() {
        guard let offset = cursorOffset else { return }
        model.splitEditing(atDraftOffset: offset)
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
                Button("Merge with Next", systemImage: "arrow.triangle.merge", action: model.mergeSelectedWithNext)
                    .disabled(!model.canMergeSelectedWithNext)
                    .help("Joins the next block into this one.")
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
        for (index, run) in item.runs.enumerated() {
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
            if run.reason?.isOCRSuspect == true {
                part.backgroundColor = .orange.opacity(0.45)
                part.underlineStyle = .single
            } else if run.reason != nil, model.showsSpelling {
                // Spelling is a hint, not a defect: only an underline.
                part.underlineStyle = .patternDot.union(.single)
                part.underlineColor = .systemBlue
            }
            if run.reason?.isOCRSuspect == true || (run.reason != nil && model.showsSpelling) {
                // A click on a flagged word opens its quick fixes.
                part.link = URL(string: "fix://\(index)")
            }
            result += part
        }
        return result
    }
}
