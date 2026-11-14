/// A language the spelling of a word is checked in.
public enum SpellLanguage: Sendable, Equatable, Hashable {
    case ukrainian
    case english
}

/// A dictionary that tells whether a word is spelled correctly.
///
/// It is a protocol so that `TextReview` stays free of AppKit: the app
/// supplies an adapter over the system spell checker (see ADR 0006), and
/// tests supply a fake with a fixed vocabulary.
public protocol SpellChecking: Sendable {
    /// Whether `word`, a single word without punctuation, is not in the
    /// dictionary of `language`. A checker that has no dictionary for
    /// `language` answers `false`: it cannot judge, so it must not flag.
    func isMisspelled(_ word: String, language: SpellLanguage) -> Bool
}
