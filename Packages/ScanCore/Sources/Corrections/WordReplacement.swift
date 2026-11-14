import Conversion
import DocumentModel
import Foundation

/// Helps to turn a fix of one word into a rule for the whole document.
public enum WordReplacement {
    /// The word that `new` has in place of one in `old`, when that is the
    /// only difference: the same words and the same text between them
    /// otherwise. `nil` for any other change, so a rewritten sentence is
    /// never offered as a rule.
    public static func singleWordChange(from old: String, to new: String) -> (old: String, new: String)? {
        let (oldWords, oldGaps) = split(old)
        let (newWords, newGaps) = split(new)
        guard oldGaps == newGaps, oldWords.count == newWords.count else { return nil }
        let changed = zip(oldWords, newWords).filter { $0 != $1 }
        guard changed.count == 1, let pair = changed.first else { return nil }
        return (pair.0, pair.1)
    }

    /// How many times `word` stands as a whole word in the text of the
    /// document's blocks, figure captions and notes.
    public static func occurrences(of word: String, in conversion: Conversion) -> Int {
        guard !word.isEmpty else { return 0 }
        let document = conversion.document
        let texts = document.blocks.map(\.content) + document.notes.map(\.content)
        return texts.reduce(0) { total, content in
            total + content.reduce(0) { count, inline in
                switch inline {
                case let .text(text), let .emphasis(text), let .strong(text): count + text.wholeWordCount(of: word)
                case .noteReference: count
                }
            }
        }
    }

    /// The words of `text` and the stretches between them, which include the
    /// start and the end, so equal gaps mean the words sit in the same places.
    private static func split(_ text: String) -> (words: [String], gaps: [String]) {
        var words: [String] = []
        var gaps = [""]
        for character in text {
            let isWord = character.isLetter || character.isNumber || "'’ʼ".contains(character)
            if isWord {
                if gaps.count > words.count {
                    words.append("")
                }
                words[words.count - 1].append(character)
            } else {
                if words.count == gaps.count {
                    gaps.append("")
                }
                gaps[gaps.count - 1].append(character)
            }
        }
        return (words, gaps)
    }
}

extension Block {
    var content: [Inline] {
        switch self {
        case let .heading(_, content), let .paragraph(content): content
        case let .figure(figure): figure.caption
        }
    }
}

extension String {
    /// The number of places `word` stands as a whole word, using the same
    /// rule as ``replacingWholeWord(_:with:)``.
    func wholeWordCount(of word: String) -> Int {
        let marker = "\u{0}"
        let replaced = replacingWholeWord(word, with: marker)
        return replaced.components(separatedBy: marker).count - 1
    }
}
