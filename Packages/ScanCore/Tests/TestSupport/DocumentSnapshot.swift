import DocumentModel
import Foundation

/// The structure of a converted document, reduced to what a golden file asserts:
/// block kinds, heading levels, text and which notes each block refers to.
///
/// Ids and image bytes are left out because they carry no layout meaning and
/// would make every file noisy.
public struct DocumentSnapshot: Codable, Equatable, Sendable {
    public struct BlockEntry: Codable, Equatable, Sendable {
        /// `heading`, `paragraph` or `figure`.
        public var kind: String
        /// Heading level; absent for other kinds.
        public var level: Int?
        /// The text without formatting; a figure's caption.
        public var text: String
        /// Labels of the notes the block refers to, in order.
        public var notes: [String]?
    }

    public struct NoteEntry: Codable, Equatable, Sendable {
        public var label: String
        public var text: String
    }

    public var blocks: [BlockEntry]
    public var notes: [NoteEntry]
    public var unlinkedReferences: Int
    public var unlinkedNotes: Int

    public init(document: Document, unlinkedReferences: Int, unlinkedNotes: Int) {
        let labels = Dictionary(uniqueKeysWithValues: document.notes.map { ($0.id, $0.label) })
        blocks = document.chapters.flatMap(\.blocks).map { block in
            let references = block.referencedNoteIDs.map { labels[$0] ?? "?" }
            let notes = references.isEmpty ? nil : references
            switch block {
            case let .heading(level, content): return BlockEntry(kind: "heading", level: level, text: content.plainText, notes: notes)
            case let .paragraph(content): return BlockEntry(kind: "paragraph", text: content.plainText, notes: notes)
            case let .figure(figure): return BlockEntry(kind: "figure", text: figure.caption.plainText, notes: notes)
            }
        }
        self.notes = document.notes.map { NoteEntry(label: $0.label, text: $0.content.plainText) }
        self.unlinkedReferences = unlinkedReferences
        self.unlinkedNotes = unlinkedNotes
    }

    /// Differences from `expected`, one sentence each; empty when this
    /// snapshot matches. Kinds, levels, note links and counts must be equal;
    /// text only has to be `textThreshold` alike (see ``TextSimilarity``).
    public func differences(from expected: DocumentSnapshot, textThreshold: Double = 0.8) -> [String] {
        var found: [String] = []
        if blocks.count != expected.blocks.count {
            found.append("block count \(blocks.count), expected \(expected.blocks.count)")
        }
        for (index, pair) in zip(blocks, expected.blocks).enumerated() {
            let (actual, wanted) = pair
            if actual.kind != wanted.kind || actual.level != wanted.level {
                found.append("block \(index): \(actual.kind) \(actual.level ?? 0), expected \(wanted.kind) \(wanted.level ?? 0)")
            }
            if (actual.notes ?? []) != (wanted.notes ?? []) {
                found.append("block \(index): note references \(actual.notes ?? []), expected \(wanted.notes ?? [])")
            }
            if !TextSimilarity.matches(actual.text, wanted.text, threshold: textThreshold) {
                found.append("block \(index): text \"\(actual.text)\", expected \"\(wanted.text)\"")
            }
        }
        if notes.count != expected.notes.count {
            found.append("note count \(notes.count), expected \(expected.notes.count)")
        }
        for (index, pair) in zip(notes, expected.notes).enumerated() {
            let (actual, wanted) = pair
            if actual.label != wanted.label {
                found.append("note \(index): label \(actual.label), expected \(wanted.label)")
            }
            if !TextSimilarity.matches(actual.text, wanted.text, threshold: textThreshold) {
                found.append("note \(index): text \"\(actual.text)\", expected \"\(wanted.text)\"")
            }
        }
        if unlinkedReferences != expected.unlinkedReferences {
            found.append("unlinked references \(unlinkedReferences), expected \(expected.unlinkedReferences)")
        }
        if unlinkedNotes != expected.unlinkedNotes {
            found.append("unlinked notes \(unlinkedNotes), expected \(expected.unlinkedNotes)")
        }
        return found
    }
}

/// Reads and writes the expected snapshots under `Tests/Fixtures/golden/`.
public enum GoldenStore {
    /// Set to `1` to rewrite expectation files from the actual result
    /// instead of comparing; review the diff before committing.
    public static let recordVariable = "GOLDEN_RECORD"

    public static var isRecording: Bool {
        ProcessInfo.processInfo.environment[recordVariable] == "1"
    }

    /// The fixtures folder of this package, found from this file's location.
    public static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/golden", isDirectory: true)

    public static func url(for name: String) -> URL {
        directory.appendingPathComponent(name + ".json")
    }

    public static func load(_ name: String) throws -> DocumentSnapshot {
        try JSONDecoder().decode(DocumentSnapshot.self, from: Data(contentsOf: url(for: name)))
    }

    public static func save(_ snapshot: DocumentSnapshot, as name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url(for: name))
    }
}
