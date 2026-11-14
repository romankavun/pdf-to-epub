# ADR 0006: The spell checker sits behind a protocol; the system adapter lives in the app

- Status: accepted
- Date: 2026-11-14

## Context

The review should flag words made of plausible letters that are not words
("докмент"). The only free, on-device Ukrainian and English dictionaries are
the system's, reached through `NSSpellChecker`, which is AppKit. `ScanCore`
must not import AppKit, and `TextReview` has no dependencies.

## Decisions

1. **`SpellChecking` protocol in `TextReview`**:
   `isMisspelled(_:language:)`. `SuspiciousWordDetector` takes it as an
   optional dependency; without one the rule is off. Tests use a fake with
   a fixed vocabulary, so no test depends on the OS dictionaries.
2. **The adapter is `SystemSpellChecker` in `App/`.** The rule "ScanCore
   never imports AppKit" stays literal, and the adapter is a few lines that
   would need the app to test anyway. It hops to the main thread (where
   `NSSpellChecker` belongs) and caches answers per word.
3. **Language per word, by script**: a word with Cyrillic letters is checked
   as Ukrainian, a Latin one as English. This handles Ukrainian text with
   English fragments without asking the user or detecting the language of
   a sentence. A language with no installed dictionary never flags.
4. **Noise is cut on purpose.** Not checked: words under three letters,
   all-capital words, words with digits, and a capitalized word that does not
   start a sentence (taken for a name). This misses a misread name or a
   capitalized error mid-sentence; a document full of names would otherwise
   bury the real findings.
5. **Spelling is kept apart from OCR suspects.** Trying it showed that the
   dictionary rule is much noisier than mixed-script and digit rules, while
   OCR suspects are what needs fixing first. `Reason.isOCRSuspect` tells
   them apart; the review keeps separate counts, separate navigation and a
   toggle (off by default), and the summary shows them separately.
6. **One detector for the review and the summary**, counted off the main
   thread, so the numbers agree.

## Consequences

- Correct but unusual words (dialect, archaic spelling, coinages) are
  flagged; there is no per-project ignore list yet.
- Counting a long document takes time on the first run because every distinct
  word makes a main-thread call; repeats come from the cache.
