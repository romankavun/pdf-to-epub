import Conversion
import CoreGraphics
import DocumentModel
import Foundation
import LayoutAnalysis

/// Generates random but valid documents for property tests.
///
/// "Valid" means what the pipeline guarantees: note and image identifiers are
/// unique, references point at existing notes, figures at existing images,
/// chapters are cut at level 1 headings, and blocks, notes and their sources
/// are aligned. Everything else (text, sizes, how many of each kind) is left
/// to the generator, so a property sees shapes no hand-written fixture has.
public struct DocumentGenerator: Sendable {
    public enum TextStyle: Sendable {
        /// A small Ukrainian and English vocabulary, so that words repeat
        /// and word replacement and similar-block search find something.
        case tidy
        /// Adds the characters that break naive code: markup, quotes,
        /// emoji, combining marks, newlines, controls, right-to-left text.
        case wild
    }

    public enum Layout: Sendable {
        /// Blocks stacked down the pages without overlapping, as a real
        /// page does, so that a block can be found again by its place.
        case tidy
        /// Arbitrary boxes and continuations; for persistence only.
        case wild
    }

    public var text: TextStyle
    public var layout: Layout
    /// The most blocks in a document.
    public var maximumBlocks: Int

    public init(text: TextStyle = .tidy, layout: Layout = .tidy, maximumBlocks: Int = 14) {
        self.text = text
        self.layout = layout
        self.maximumBlocks = maximumBlocks
    }

    // MARK: - Text

    private static let words = [
        "Журавель", "мов", "їжак", "ґанок", "Київ", "ліс", "дорога", "слово", "документ", "вітер", "Коваленко",
        "the", "document", "road", "naïve", "light", "and", "Chapter", "river", "world", "він", "вона",
    ]
    private static let punctuation = [".", ",", ";", ":", "!", "?", "…", "—", "»", "“", "’"]
    private static let wildFragments = [
        "<b>", "&amp;", "a & b", "\"quoted\"", "it's", "😀", "👨‍👩‍👧", "e\u{301}", "é", "שלום", "مرحبا", "日本語",
        "line\nbreak", "tab\there", "\u{1}ctrl", "\u{FFFC}", "\u{200B}", "]]>", "\\", "/", "..", "%20",
    ]

    /// A run of words, not empty.
    public func words(_ generator: inout SeededGenerator, count: ClosedRange<Int> = 1 ... 8) -> String {
        var result = ""
        for index in 0 ..< generator.int(count) {
            if index > 0 {
                result += " "
            }
            if text == .wild, generator.chance(0.25) {
                result += generator.pick(Self.wildFragments)
            } else {
                result += generator.pick(Self.words)
            }
            if generator.chance(0.15) {
                result += generator.pick(Self.punctuation)
            }
        }
        return result
    }

    private func label(_ generator: inout SeededGenerator) -> String {
        let labels = ["1", "2", "12", "*", "†", "a", "b", "LXXVIII", "⁷"]
        if text == .wild, generator.chance(0.3) {
            return words(&generator, count: 1 ... 1)
        }
        return generator.pick(labels)
    }

    private func inlines(_ generator: inout SeededGenerator, noteIDs: [Note.ID]) -> [Inline] {
        (0 ..< generator.int(1 ... 5)).map { _ in
            switch generator.int(0 ... 9) {
            case 0 ..< 5: .text(words(&generator))
            case 5, 6: .emphasis(words(&generator, count: 1 ... 3))
            case 7: .strong(words(&generator, count: 1 ... 3))
            default:
                if noteIDs.isEmpty {
                    .text(words(&generator))
                } else {
                    .noteReference(generator.pick(noteIDs))
                }
            }
        }
    }

    // MARK: - Documents

    /// A document with chapters cut from its blocks, notes and images.
    public func document(_ generator: inout SeededGenerator) -> Document {
        document(&generator).document
    }

    /// A conversion: a document with page references for every block and note.
    public func conversion(_ generator: inout SeededGenerator) -> Conversion {
        document(&generator).conversion
    }

    private func document(_ generator: inout SeededGenerator) -> (document: Document, conversion: Conversion) {
        let notes = (0 ..< generator.int(0 ... 5)).map { index in
            Note(id: "note-\(index + 1)", label: label(&generator), content: [])
        }
        let noteIDs = notes.map(\.id)
        let images = (0 ..< generator.int(0 ... 3)).map { index in
            ImageResource(
                id: "figure-\(index + 1)", filename: "figure-\(index + 1).png", mediaType: "image/png",
                data: Data((0 ..< generator.int(1 ... 64)).map { _ in UInt8.random(in: 0 ... 255, using: &generator) })
            )
        }
        let blocks = blocks(&generator, noteIDs: noteIDs, images: images)
        let filledNotes = notes.map { note in
            var note = note
            note.content = inlines(&generator, noteIDs: [])
            return note
        }
        let metadata = DocumentMetadata(
            identifier: "urn:uuid:\(generator.int(0 ... 999_999))", title: words(&generator, count: 1 ... 4),
            author: generator.chance(0.7) ? words(&generator, count: 1 ... 3) : nil,
            language: generator.pick(["uk", "en", "uk-UA"])
        )
        let document = Document(
            metadata: metadata,
            chapters: Chapter.chapters(from: blocks, fallbackTitle: metadata.title),
            notes: filledNotes, images: images,
            coverImageID: images.isEmpty || generator.chance(0.5) ? nil : generator.pick(images).id
        )
        let places = layout == .tidy ? tidyPlaces(of: blocks, noteCount: notes.count, &generator)
            : wildPlaces(blockCount: blocks.count, noteCount: notes.count, &generator)
        let conversion = Conversion(
            document: document,
            unlinkedReferences: layout == .wild ? generator.int(0 ... 9) : 0,
            unlinkedNotes: layout == .wild ? generator.int(0 ... 9) : 0,
            pageURLs: (0 ..< places.pages).map { page in
                let name = text == .wild && generator.chance(0.5) ? "сторінка \(page) é" : String(page)
                return URL(fileURLWithPath: "/scans/document/\(name).png")
            },
            blockSources: places.blocks,
            noteSources: places.notes,
            // A project made before styles were kept has none.
            styles: generator.chance(0.2) ? nil : styles(for: places, &generator)
        )
        return (document, conversion)
    }

    /// A style for every block and note of `places` and a little page furniture.
    private func styles(for places: Places, _ generator: inout SeededGenerator) -> BlockStyles {
        BlockStyles(
            blocks: places.blocks.map { _ in style(&generator) },
            notes: places.notes.map { _ in style(&generator) },
            pageFurniture: (0 ..< generator.int(0 ... 3)).map { _ in
                PageFurniture(
                    area: PageArea(page: generator.int(0 ... max(0, places.pages - 1)), box: CGRect(
                        x: generator.double(0 ... 0.5), y: generator.double(0 ... 1), width: 0.3, height: 0.02
                    )),
                    text: words(&generator, count: 1 ... 3), style: style(&generator)
                )
            }
        )
    }

    /// A style with features anywhere in their range.
    private func style(_ generator: inout SeededGenerator) -> BlockStyle {
        BlockStyle(
            rule: generator.pick(DecidingRule.allCases),
            lineHeight: generator.double(0 ... 3),
            ink: generator.chance(0.3) ? nil : generator.double(0.5 ... 2),
            alignment: generator.pick([.margin, .indented, .centered, .right]),
            width: generator.double(0 ... 1.2),
            zone: generator.pick([.top, .body, .bottom]),
            lineCount: generator.int(0 ... 30),
            spaceAbove: generator.chance(0.3) ? nil : generator.double(0 ... 10),
            spaceBelow: generator.chance(0.3) ? nil : generator.double(0 ... 10),
            isUnderPicture: generator.chance(0.2),
            opensWithNoteLabel: generator.chance(0.2)
        )
    }

    private func blocks(_ generator: inout SeededGenerator, noteIDs: [Note.ID], images: [ImageResource]) -> [Block] {
        var blocks: [Block] = []
        for index in 0 ..< generator.int(1 ... maximumBlocks) {
            switch generator.int(0 ... 9) {
            case 0 ... 2:
                let level = index == 0 ? 1 : generator.int(1 ... 4)
                blocks.append(.heading(level: level, content: inlines(&generator, noteIDs: noteIDs)))
            case 3 where !images.isEmpty:
                let caption = generator.chance(0.6) ? inlines(&generator, noteIDs: noteIDs) : []
                blocks.append(.figure(Figure(
                    imageID: generator.pick(images).id, alternativeText: generator.chance(0.5) ? words(&generator) : "",
                    caption: caption
                )))
            default:
                blocks.append(.paragraph(inlines(&generator, noteIDs: noteIDs)))
            }
        }
        return blocks
    }

    // MARK: - Places

    private struct Places {
        var pages: Int
        var blocks: [BlockSource]
        var notes: [BlockSource]
    }

    /// Blocks one under another, a new page when the next does not fit, notes
    /// in a strip at the bottom. No two areas overlap, so each is the only
    /// match for its own anchor.
    private func tidyPlaces(of blocks: [Block], noteCount: Int, _ generator: inout SeededGenerator) -> Places {
        var page = 0
        var top = 0.05
        var sources: [BlockSource] = []
        for block in blocks {
            let isHeading = if case .heading = block {
                true
            } else {
                false
            }
            let height = isHeading ? generator.double(0.03 ... 0.04) : generator.double(0.05 ... 0.12)
            if top + height > 0.85 {
                page += 1
                top = 0.05
            }
            let box = isHeading
                ? CGRect(x: generator.pick([0.1, 0.3]), y: top, width: 0.4, height: height)
                : CGRect(x: 0.05, y: top, width: 0.9, height: height)
            sources.append(BlockSource(page: page, box: box))
            top += height + 0.04
        }
        var slots: [Int: Int] = [:]
        let notes = (0 ..< noteCount).map { _ in
            let notePage = generator.int(0 ... page)
            let slot = slots[notePage, default: 0]
            slots[notePage] = slot + 1
            return BlockSource(
                page: notePage,
                box: CGRect(x: 0.05, y: 0.86 + 0.02 * Double(slot), width: 0.9, height: 0.01)
            )
        }
        return Places(pages: page + 1, blocks: sources, notes: notes)
    }

    private func wildPlaces(blockCount: Int, noteCount: Int, _ generator: inout SeededGenerator) -> Places {
        let pages = generator.int(1 ... 6)
        func source(_ generator: inout SeededGenerator) -> BlockSource {
            func area(_ generator: inout SeededGenerator) -> CGRect {
                CGRect(
                    x: generator.double(0 ... 0.5), y: generator.double(0 ... 0.9),
                    width: generator.double(0.001 ... 0.5), height: generator.double(0.001 ... 0.1)
                )
            }
            var source = BlockSource(page: generator.int(0 ... pages - 1), box: area(&generator))
            for _ in 0 ..< generator.int(0 ... 2) {
                source.continuations.append(PageArea(page: generator.int(0 ... pages - 1), box: area(&generator)))
            }
            return source
        }
        return Places(
            pages: pages, blocks: (0 ..< blockCount).map { _ in source(&generator) },
            notes: (0 ..< noteCount).map { _ in source(&generator) }
        )
    }
}
