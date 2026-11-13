/// Finds words that OCR has probably misread, by rules that need no
/// dictionary: the checks are cheap, deterministic and work the same for
/// Ukrainian and English.
///
/// A flagged word is a suggestion to look, not a verdict: "H2O" is flagged
/// too.
public struct SuspiciousWordDetector: Sendable {
    /// Why a word was flagged.
    public enum Reason: Sendable, Equatable {
        /// Latin and Cyrillic letters in one word: a look-alike letter from
        /// the wrong alphabet ("Журавeль" with a Latin "o").
        case mixedScript
        /// A digit with letters on both sides: a letter read as a digit
        /// ("сл0во").
        case digitInsideWord
    }

    /// A stretch of text that is either one suspicious word or everything
    /// between two of them.
    public struct Segment: Sendable, Equatable {
        public var text: String
        /// `nil` for text with nothing to flag.
        public var reason: Reason?

        public init(text: String, reason: Reason? = nil) {
            self.text = text
            self.reason = reason
        }
    }

    public init() {}

    /// Splits `text` so that every suspicious word is a segment of its own.
    /// The segments joined together give `text` back.
    public func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        func add(_ word: Substring) {
            if let reason = reason(for: word) {
                if !plain.isEmpty {
                    segments.append(Segment(text: plain))
                    plain = ""
                }
                segments.append(Segment(text: String(word), reason: reason))
            } else {
                plain += word
            }
        }

        var wordStart: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            let inWord = character.isLetter || character.isNumber
                || (Self.apostrophes.contains(character) && wordStart != nil
                    && next < text.endIndex && text[next].isLetter)
            if inWord {
                wordStart = wordStart ?? index
            } else {
                if let start = wordStart {
                    add(text[start ..< index])
                    wordStart = nil
                }
                plain.append(character)
            }
            index = next
        }
        if let start = wordStart {
            add(text[start...])
        }
        if !plain.isEmpty {
            segments.append(Segment(text: plain))
        }
        return segments
    }

    /// The number of suspicious words in `text`.
    public func suspiciousWordCount(in text: String) -> Int {
        segments(of: text).count { $0.reason != nil }
    }

    private static let apostrophes: Set<Character> = ["'", "’", "ʼ"]

    private func reason(for word: Substring) -> Reason? {
        var hasLatin = false, hasCyrillic = false
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0xC0 ... 0x24F: hasLatin = true
            case 0x400 ... 0x52F: hasCyrillic = true
            default: break
            }
        }
        if hasLatin, hasCyrillic {
            return .mixedScript
        }
        guard let firstLetter = word.firstIndex(where: \.isLetter),
              let lastLetter = word.lastIndex(where: \.isLetter)
        else { return nil }
        return word[firstLetter ..< lastLetter].contains(where: \.isNumber) ? .digitInsideWord : nil
    }
}
