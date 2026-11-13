import Conversion
import DocumentModel

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
