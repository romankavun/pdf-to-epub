import AppKit
import Foundation
import os
import TextReview

/// The system dictionaries (`NSSpellChecker`) behind ``SpellChecking``.
///
/// It lives in the app rather than in `ScanCore` because AppKit is off
/// limits there (ADR 0007). `NSSpellChecker` belongs to the main thread, so
/// a call from elsewhere hops there; answers are cached per word because a
/// document repeats its words and the hop is the slow part.
final class SystemSpellChecker: SpellChecking, Sendable {
    private struct Key: Hashable {
        var word: String
        var language: SpellLanguage
    }

    private let cache = OSAllocatedUnfairLock(initialState: [Key: Bool]())

    func isMisspelled(_ word: String, language: SpellLanguage) -> Bool {
        let key = Key(word: word, language: language)
        if let cached = cache.withLock({ $0[key] }) {
            return cached
        }
        let answer = if Thread.isMainThread {
            MainActor.assumeIsolated { Self.ask(word, language) }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { Self.ask(word, language) } }
        }
        cache.withLock { $0[key] = answer }
        return answer
    }

    func suggestions(for word: String, language: SpellLanguage) -> [String] {
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.guesses(word, language) }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { Self.guesses(word, language) } }
        }
    }

    @MainActor private static func installedLanguage(_ language: SpellLanguage) -> String? {
        let code = switch language {
        case .ukrainian: "uk"
        case .english: "en"
        }
        return NSSpellChecker.shared.availableLanguages.first { $0 == code || $0.hasPrefix(code + "_") }
    }

    @MainActor private static func guesses(_ word: String, _ language: SpellLanguage) -> [String] {
        guard let installed = installedLanguage(language) else { return [] }
        return NSSpellChecker.shared.guesses(
            forWordRange: NSRange(location: 0, length: word.utf16.count), in: word,
            language: installed, inSpellDocumentWithTag: 0
        ) ?? []
    }

    @MainActor private static func ask(_ word: String, _ language: SpellLanguage) -> Bool {
        let checker = NSSpellChecker.shared
        // No dictionary for the language: cannot judge, so do not flag.
        guard let installed = installedLanguage(language) else { return false }
        let range = checker.checkSpelling(
            of: word, startingAt: 0, language: installed, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location != NSNotFound
    }
}
