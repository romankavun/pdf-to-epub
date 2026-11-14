import AppModel
import SwiftUI

/// The suggestions for one flagged word, as buttons that replace it, and a
/// way to edit the whole text instead.
struct QuickFix: View {
    var model: ReviewModel
    var itemID: ReviewModel.ItemID
    var runIndex: Int
    var close: () -> Void

    var body: some View {
        let suggestions = model.suggestions(forRunAt: runIndex, in: itemID)
        VStack(alignment: .leading, spacing: 6) {
            if suggestions.isEmpty {
                Text("No suggestions")
                    .foregroundStyle(.secondary)
            }
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) {
                    close()
                    model.replaceRun(at: runIndex, in: itemID, with: suggestion)
                }
                .buttonStyle(.borderless)
            }
            Divider()
            Button("Ignore This Word", systemImage: "eye.slash") {
                close()
                model.ignoreWord(inRunAt: runIndex, of: itemID)
            }
            .buttonStyle(.borderless)
            Button("Edit Text…", systemImage: "pencil") {
                close()
                model.beginEditing()
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }
}
