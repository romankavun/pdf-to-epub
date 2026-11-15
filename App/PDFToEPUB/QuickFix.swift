import AppModel
import SwiftUI

/// The suggestions for one flagged word, shown in a row inside the block's
/// card: buttons that replace the word, a way to ignore it, and a way to
/// edit the whole text instead. A row, not a popover, because `Text` gives
/// no rectangle for a clicked word to anchor a popover to.
struct QuickFix: View {
    var model: ReviewModel
    var itemID: ReviewModel.ItemID
    var runIndex: Int
    /// The flagged word, so the row says what it is about.
    var word: String
    var close: () -> Void

    var body: some View {
        let suggestions = model.suggestions(forRunAt: runIndex, in: itemID)
        HStack(spacing: 8) {
            Text("“\(word)”")
                .bold()
                .lineLimit(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if suggestions.isEmpty {
                        Text("No suggestions")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            close()
                            model.replaceRun(at: runIndex, in: itemID, with: suggestion)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Ignore This Word", systemImage: "eye.slash") {
                        close()
                        model.ignoreWord(inRunAt: runIndex, of: itemID)
                    }
                    Button("Edit Text…", systemImage: "pencil") {
                        close()
                        model.beginEditing()
                    }
                }
            }
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .controlSize(.small)
        .padding(6)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
    }
}
