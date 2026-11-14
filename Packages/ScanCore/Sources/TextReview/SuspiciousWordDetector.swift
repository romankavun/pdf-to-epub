/// Finds words that OCR has probably misread. Two rules need no dictionary
/// and work the same for Ukrainian and English; a third asks an injected
/// ``SpellChecking`` dictionary, and is off when there is none.
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
        /// A word of plain letters that the dictionary of its language does
        /// not know ("докмент"). The language follows the word's script, so a
        /// Ukrainian text with English fragments is checked fragment by
        /// fragment.
        case misspelled

        /// Whether the reason points to an OCR misreading (a wrong letter or
        /// digit) rather than to a spelling the dictionary does not know.
        /// The review treats these first: a misspelling is far noisier
        /// (names, dialect, archaic words), so it is kept apart.
        public var isOCRSuspect: Bool {
            self != .misspelled
        }
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

    private let spellChecker: (any SpellChecking)?

    /// - Parameter spellChecker: the dictionary for the spelling rule; with
    ///   `nil` only the two dictionary-free rules apply.
    public init(spellChecker: (any SpellChecking)? = nil) {
        self.spellChecker = spellChecker
    }

    /// Splits `text` so that every suspicious word is a segment of its own.
    /// The segments joined together give `text` back.
    public func segments(of text: String) -> [Segment] {
        var segments: [Segment] = []
        var plain = ""
        var atSentenceStart = true
        func add(_ word: Substring) {
            defer { atSentenceStart = false }
            if let reason = reason(for: word, atSentenceStart: atSentenceStart) {
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
                if Self.sentenceEnds.contains(character) {
                    atSentenceStart = true
                }
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

    /// The number of OCR-suspect words in `text` (see ``Reason/isOCRSuspect``);
    /// misspellings are counted by ``misspelledWordCount(in:)``.
    public func suspiciousWordCount(in text: String) -> Int {
        segments(of: text).count { $0.reason?.isOCRSuspect == true }
    }

    /// The number of words in `text` that the dictionary does not know.
    public func misspelledWordCount(in text: String) -> Int {
        segments(of: text).count { $0.reason == .misspelled }
    }

    /// Corrections to offer for a flagged `word`, best first, at most five.
    ///
    /// An OCR suspect is fixed by swapping the look-alike character for the
    /// one the rest of the word uses (a Latin "o" in a Cyrillic word, a "0"
    /// for "о"); that needs no dictionary. A misspelling gets the
    /// dictionary's own guesses.
    public func suggestions(for word: String, reason: Reason) -> [String] {
        var result: [String] = []
        switch reason {
        case .misspelled:
            result = spellChecker?.suggestions(for: word, language: Self.language(of: word)) ?? []
        case .mixedScript, .digitInsideWord:
            if let fixed = Self.lookAlikeFix(of: word, reason: reason) {
                result = [fixed]
                if let spellChecker, spellChecker.isMisspelled(fixed, language: Self.language(of: fixed)) {
                    result += spellChecker.suggestions(for: fixed, language: Self.language(of: fixed))
                }
            }
        }
        var seen: Set<String> = [word]
        return Array(result.filter { seen.insert($0).inserted }.prefix(5))
    }

    private static func language(of word: String) -> SpellLanguage {
        word.unicodeScalars.contains { (0x400 ... 0x52F).contains($0.value) } ? .ukrainian : .english
    }

    /// Letters that look the same in both alphabets, as (Latin, Cyrillic).
    private static let lookAlikes: [(Character, Character)] = [
        ("a", "а"), ("c", "с"), ("e", "е"), ("i", "і"), ("o", "о"), ("p", "р"), ("x", "х"), ("y", "у"),
        ("A", "А"), ("B", "В"), ("C", "С"), ("E", "Е"), ("H", "Н"), ("I", "І"), ("K", "К"), ("M", "М"),
        ("O", "О"), ("P", "Р"), ("T", "Т"), ("X", "Х"), ("Y", "У"),
    ]
    private static let digitsAsCyrillic: [Character: Character] = ["0": "о", "1": "і", "3": "з", "6": "б"]
    private static let digitsAsLatin: [Character: Character] = ["0": "o", "1": "l", "5": "s"]

    private static func lookAlikeFix(of word: String, reason: Reason) -> String? {
        let cyrillic = word.unicodeScalars.count { (0x400 ... 0x52F).contains($0.value) }
        let latin = word.unicodeScalars.count { $0.properties.isAlphabetic && $0.value < 0x250 }
        // The script with more letters is taken for the word's own; a tie
        // goes to Cyrillic, the document's main alphabet.
        let toCyrillic = cyrillic >= latin
        let fixed = String(word.map { character -> Character in
            if reason == .digitInsideWord {
                return (toCyrillic ? digitsAsCyrillic : digitsAsLatin)[character] ?? character
            }
            let pair = lookAlikes.first { toCyrillic ? $0.0 == character : $0.1 == character }
            return pair.map { toCyrillic ? $0.1 : $0.0 } ?? character
        })
        return fixed != word && !(reason == .digitInsideWord && fixed.contains(where: \.isNumber)) ? fixed : nil
    }

    private static let apostrophes: Set<Character> = ["'", "’", "ʼ"]

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    private func reason(for word: Substring, atSentenceStart: Bool) -> Reason? {
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
        if word[firstLetter ..< lastLetter].contains(where: \.isNumber) {
            return .digitInsideWord
        }
        return isMisspelled(word, isCyrillic: hasCyrillic, atSentenceStart: atSentenceStart) ? .misspelled : nil
    }

    /// Asks the dictionary only about words it can judge. A capitalized word
    /// inside a sentence is taken for a name, and an all-capital one for an
    /// acronym; one- and two-letter words and anything with digits are
    /// skipped. Every skip trades a missed error for fewer false alarms,
    /// which would otherwise drown the real ones in a document full of names.
    private func isMisspelled(_ word: Substring, isCyrillic: Bool, atSentenceStart: Bool) -> Bool {
        guard let spellChecker, word.count(where: \.isLetter) >= 3,
              !word.contains(where: \.isNumber),
              word.allSatisfy({ $0.isLetter || Self.apostrophes.contains($0) })
        else { return false }
        if word.first?.isUppercase == true, !atSentenceStart || word == word.uppercased() {
            return false
        }
        return spellChecker.isMisspelled(String(word), language: isCyrillic ? .ukrainian : .english)
    }
}
