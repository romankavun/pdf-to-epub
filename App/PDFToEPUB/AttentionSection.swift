import AppModel
import SwiftUI

/// The summary's "Needs attention" section: what the user should look at
/// before saving, most serious first. Each number opens the review at the
/// first issue.
struct AttentionSection: View {
    var summary: ConversionSummary
    /// The summary with words counted; `nil` until counted.
    var counted: ConversionSummary?
    var review: (ReviewStart) -> Void

    var body: some View {
        if isNeeded {
            Section("Needs attention") {
                if summary.pagesThatMayHideText > 0 {
                    LabeledContent("Pages that may have lost their text") {
                        Button(summary.pagesThatMayHideText.formatted()) { review(.issue) }
                            .buttonStyle(.link)
                            .help("Pages taken whole for an illustration. Opens the review at the first issue.")
                    }
                }
                if let counted, counted.misrecognizedBlocks > 0 {
                    LabeledContent("Blocks with text probably misrecognized") {
                        Button(counted.misrecognizedBlocks.formatted()) { review(.issue) }
                            .buttonStyle(.link)
                            .help("Too many of their words are unknown. Opens the review at the first issue.")
                    }
                }
                if let counted, counted.suspiciousWords > 0 {
                    LabeledContent("Suspicious words") {
                        Button(counted.suspiciousWords.formatted()) { review(.issue) }
                            .buttonStyle(.link)
                            .help("Opens the review at the first issue.")
                    }
                }
                LabeledContent("References without a note", value: summary.unlinkedReferences.formatted())
                LabeledContent("Notes without a reference", value: summary.unlinkedNotes.formatted())
            }
        }
    }

    private var isNeeded: Bool {
        summary.unlinkedReferences > 0 || summary.unlinkedNotes > 0 || summary.pagesThatMayHideText > 0
            || (counted?.suspiciousWords ?? 0) > 0 || (counted?.misrecognizedBlocks ?? 0) > 0
    }
}
