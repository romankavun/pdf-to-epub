import Conversion
import DocumentModel
import TextReview

/// What a finished conversion produced, as numbers to show the user before
/// they export: enough to notice a document that came out with no chapters or
/// with half of its notes unlinked.
public struct ConversionSummary: Sendable, Equatable {
    public var chapters: Int
    public var headings: Int
    public var paragraphs: Int
    public var figures: Int
    public var notes: Int
    public var hasCover: Bool
    /// Note references left in the text as plain labels.
    public var unlinkedReferences: Int
    /// Note texts left in the body because nothing refers to them.
    public var unlinkedNotes: Int
    /// Words in the text, captions and notes that look like OCR misreadings
    /// (mixed alphabets, digits inside words). Zero unless counted with a
    /// detector (see ``init(_:detector:)``).
    public var suspiciousWords = 0
    /// Words the spell checker does not know: a noisier signal, kept apart
    /// from ``suspiciousWords``.
    public var misspelledWords = 0

    public init(
        chapters: Int,
        headings: Int,
        paragraphs: Int,
        figures: Int,
        notes: Int,
        hasCover: Bool,
        unlinkedReferences: Int,
        unlinkedNotes: Int
    ) {
        self.chapters = chapters
        self.headings = headings
        self.paragraphs = paragraphs
        self.figures = figures
        self.notes = notes
        self.hasCover = hasCover
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }

    /// Summarizes `conversion` and counts its suspicious words with
    /// `detector`, the same one the review uses, so the two numbers agree.
    /// Counting asks the spell checker about every word of the document, so do
    /// it off the main thread for a long document.
    public init(_ conversion: Conversion, detector: SuspiciousWordDetector) {
        self.init(conversion)
        let document = conversion.document
        var contents: [[Inline]] = document.notes.map(\.content)
        for block in document.blocks {
            switch block {
            case let .heading(_, content), let .paragraph(content): contents.append(content)
            case let .figure(figure): contents.append(figure.caption)
            }
        }
        let texts = contents.flatMap { content in
            content.compactMap { inline -> String? in
                switch inline {
                case let .text(text), let .emphasis(text), let .strong(text): text
                case .noteReference: nil
                }
            }
        }
        suspiciousWords = texts.reduce(0) { $0 + detector.suspiciousWordCount(in: $1) }
        misspelledWords = texts.reduce(0) { $0 + detector.misspelledWordCount(in: $1) }
    }

    public init(_ conversion: Conversion) {
        let document = conversion.document
        var headings = 0, paragraphs = 0, figures = 0
        for block in document.blocks {
            switch block {
            case .heading: headings += 1
            case .paragraph: paragraphs += 1
            case .figure: figures += 1
            }
        }
        self.init(
            chapters: document.chapters.count,
            headings: headings,
            paragraphs: paragraphs,
            figures: figures,
            notes: document.notes.count,
            hasCover: document.coverImageID != nil,
            unlinkedReferences: conversion.unlinkedReferences,
            unlinkedNotes: conversion.unlinkedNotes
        )
    }
}
