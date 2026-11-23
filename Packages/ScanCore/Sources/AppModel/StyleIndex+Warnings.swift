import DocumentModel
import Styles
import TextReview

extension StyleIndex {
    /// An unknown word in at least this many blocks of one style is taken
    /// for a real word the dictionary lacks. Tuned on the sample sets: a
    /// bibliography's archive abbreviations and titles in another language
    /// made 112 of 170 note texts look misrecognized, 9 without them.
    static let recurringWordBlocks = 3

    /// The recognized blocks and note texts of `styles` whose text was
    /// probably misrecognized, judged in the document's language as the
    /// summary does, except that an unknown word recurring in
    /// ``recurringWordBlocks`` blocks of the same style counts as known: OCR
    /// misreads words differently each time, while an abbreviation, a name
    /// or a word in another language comes back unchanged.
    static func misrecognized(
        in styles: [Styles.Style], document: Document, detector: SuspiciousWordDetector
    ) -> Set<StyleMember> {
        let language = SpellLanguage(languageCode: document.metadata.language)
        var members: Set<StyleMember> = []
        for style in styles {
            let contents = style.members.compactMap { member in content(of: member, in: document).map { (member, $0) } }
            var blocksWith: [String: Int] = [:]
            for (_, content) in contents {
                for word in Set(unknownWords(in: content, detector: detector)) {
                    blocksWith[word, default: 0] += 1
                }
            }
            let recurring = Set(blocksWith.filter { $0.value >= recurringWordBlocks }.keys)
            for (member, content) in contents
                where detector.spellingTally(of: content, in: language, ignoring: recurring).isProbablyMisrecognized
            {
                members.insert(member)
            }
        }
        return members
    }

    /// The text of a block or note text; `nil` for page furniture.
    private static func content(of member: StyleMember, in document: Document) -> [Inline]? {
        switch member {
        case let .block(index):
            guard document.blocks.indices.contains(index) else { return nil }
            return switch document.blocks[index] {
            case let .heading(_, content), let .paragraph(content): content
            case let .figure(figure): figure.caption
            }
        case let .note(index):
            return document.notes.indices.contains(index) ? document.notes[index].content : nil
        case .pageFurniture:
            return nil
        }
    }

    /// The words of `content` the dictionary does not know, lowercased.
    private static func unknownWords(in content: [Inline], detector: SuspiciousWordDetector) -> [String] {
        content.flatMap { inline -> [String] in
            switch inline {
            case let .text(text), let .emphasis(text), let .strong(text):
                detector.segments(of: text).filter { $0.reason == .misspelled }.map { $0.text.lowercased() }
            case .noteReference:
                []
            }
        }
    }
}
