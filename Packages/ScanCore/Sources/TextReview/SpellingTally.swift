public extension SpellLanguage {
    /// The dictionary for a document in `languageCode` (BCP 47 or POSIX style,
    /// such as "en-GB" or "uk_UA"); `nil` for a language the review has no
    /// rule for.
    init?(languageCode: String) {
        let primary = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        switch primary {
        case "en": self = .english
        case "uk": self = .ukrainian
        default: return nil
        }
    }
}

public extension SuspiciousWordDetector {
    /// How many words of a text the spelling rule judged, and how many of
    /// them the dictionary did not know.
    ///
    /// One unknown word is noise (a name, a rare word); a large share of
    /// them in one block means OCR read the block badly as a whole, which
    /// word-by-word flags fail to convey. See ``isProbablyMisrecognized``.
    struct SpellingTally: Sendable, Equatable, Hashable {
        /// Words the dictionary was asked about. Short words, names,
        /// acronyms and words with digits are skipped and not counted.
        public var checked: Int
        /// Of ``checked``, the words the dictionary does not know.
        public var misspelled: Int

        public init(checked: Int = 0, misspelled: Int = 0) {
            self.checked = checked
            self.misspelled = misspelled
        }

        /// Fewer judged words than this say nothing about a block: a
        /// four-word heading with one name in it would already be a quarter
        /// unknown.
        public static let minimumCheckedWords = 8

        /// The share of unknown words above which text is taken for
        /// misrecognized. Measured per block: clean clean-page source text in English
        /// stays under 0.05 and Ukrainian prose almost always under 0.15,
        /// while a garbled paper scan has a median of 0.23. See the review
        /// feature page for the numbers.
        public static let misrecognizedShare = 0.2

        /// Whether so many judged words are unknown that the text was
        /// probably misrecognized: at least ``minimumCheckedWords`` judged,
        /// and more than ``misrecognizedShare`` of them unknown.
        public var isProbablyMisrecognized: Bool {
            checked >= Self.minimumCheckedWords && Double(misspelled) > Self.misrecognizedShare * Double(checked)
        }

        public static func + (left: Self, right: Self) -> Self {
            Self(checked: left.checked + right.checked, misspelled: left.misspelled + right.misspelled)
        }
    }

    /// Counts the words of `text` that the spelling rule judges and the ones
    /// it flags, with the same skips as ``segments(of:)``.
    ///
    /// - Parameters:
    ///   - language: counts only words of this language (picked by script,
    ///     as the rule does); `nil` counts all. A document's own language is the
    ///     fair measure: fragments in another language that the review has
    ///     no dictionary for (German checked as English) are unknown by
    ///     nature, not misread.
    ///   - ignoredWords: lowercased words the user chose to ignore; they
    ///     count as judged and known.
    func spellingTally(
        of text: String, in language: SpellLanguage? = nil, ignoring ignoredWords: Set<String> = []
    ) -> SpellingTally {
        var tally = SpellingTally()
        forEachPiece(of: text) { piece, atSentenceStart in
            guard case let .word(word) = piece,
                  language == nil || Self.language(of: word) == language
            else { return }
            switch reason(for: word, atSentenceStart: atSentenceStart) {
            case .mixedScript?, .digitInsideWord?:
                return
            case .misspelled?:
                tally.checked += 1
                if !ignoredWords.contains(word.lowercased()) {
                    tally.misspelled += 1
                }
            case nil:
                if isJudged(word, atSentenceStart: atSentenceStart) {
                    tally.checked += 1
                }
            }
        }
        return tally
    }
}
