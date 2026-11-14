import Corrections
import DocumentModel
import Foundation
import TextReview

/// Quick fixes for flagged words.
public extension ReviewModel {
    /// Corrections to offer for the flagged word in run `index` of the item
    /// `itemID`, best first; empty when the run is not flagged.
    func suggestions(forRunAt index: Int, in itemID: ItemID) -> [String] {
        guard let run = run(at: index, in: itemID), let reason = run.reason else { return [] }
        return detector.suggestions(for: run.text, reason: reason)
    }

    /// Replaces the flagged word in run `index` of `itemID` with
    /// `replacement`, recorded as a text correction like any edit. When the
    /// same word stands elsewhere, replacing it everywhere is offered in
    /// ``proposal``. Does nothing for a run that is not flagged.
    func replaceRun(at index: Int, in itemID: ItemID, with replacement: String) {
        guard let item = pages.lazy.compactMap({ $0.items.first { $0.id == itemID } }).first,
              item.runs.indices.contains(index), item.runs[index].reason != nil,
              item.runs[index].text != replacement
        else { return }
        var runs = item.runs
        runs[index].text = replacement
        let old = item.canonicalText
        let new = runs.map { $0.style == .noteReference ? "\u{FFFC}" : $0.text }.joined()
        proposal = nil
        project.setText(new, for: item.anchor)
        rebuild()
        if let change = WordReplacement.singleWordChange(from: old, to: new) {
            let count = WordReplacement.occurrences(of: change.old, in: project.conversion)
            if count > 0 {
                proposal = .word(find: change.old, replacement: change.new, occurrences: count)
            }
        }
    }

    private func run(at index: Int, in itemID: ItemID) -> Run? {
        let item = pages.lazy.compactMap { $0.items.first { $0.id == itemID } }.first
        return item.flatMap { $0.runs.indices.contains(index) ? $0.runs[index] : nil }
    }
}
