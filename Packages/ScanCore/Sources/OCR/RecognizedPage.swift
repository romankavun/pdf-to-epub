import CoreGraphics
import Foundation

/// One word of a recognized line.
public struct TextWord: Sendable, Equatable, Codable {
    public var text: String
    /// Position on the page, in the same coordinates as ``TextLine/box``.
    /// Engines estimate it, so neighbouring words may overlap slightly.
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// One line of text found on a page.
public struct TextLine: Sendable, Equatable, Codable {
    public var text: String
    /// Position on the page in normalized coordinates: both axes run 0...1,
    /// with the origin at the **top-left** corner and y growing downwards.
    public var box: CGRect
    /// Engine confidence, 0...1. A weak signal with Vision (see ADR 0001).
    public var confidence: Float
    /// The words of ``text`` from left to right, used to place things that
    /// are located by position (note references) inside the line. Empty when
    /// the engine does not report words.
    public var words: [TextWord]

    public init(text: String, box: CGRect, confidence: Float = 1, words: [TextWord] = []) {
        self.text = text
        self.box = box
        self.confidence = confidence
        self.words = words
    }
}

/// The text recognized on one page image, before any layout analysis.
public struct RecognizedPage: Sendable, Equatable, Codable {
    /// Lines in the order the engine returned them; not necessarily sorted.
    public var lines: [TextLine]

    public init(lines: [TextLine]) {
        self.lines = lines
    }
}
