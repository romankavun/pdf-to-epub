import DocumentModel

/// The character that stands for a note reference in the text a user edits
/// and in the text a correction records (U+FFFC, the object replacement
/// character). A reference is one unit, so a diff never splits it, and it
/// carries no label: labels can change when a document is converted again.
let notePlaceholder: Character = "\u{FFFC}"

public extension String {
    /// The recorded form of text typed in the editor, where a note
    /// reference is shown as its label in `⟦` `⟧` brackets: every bracketed
    /// token becomes the placeholder.
    init(editorText: String) {
        var result = ""
        var inToken = false
        for character in editorText {
            switch (character, inToken) {
            case ("⟦", false): inToken = true
            case ("⟧", true):
                inToken = false
                result.append(notePlaceholder)
            case (_, true): break
            default: result.append(character)
            }
        }
        // An unclosed bracket was ordinary text.
        self = inToken ? editorText : result
    }
}

public extension [Inline] {
    /// The text without formatting, with each note reference as one
    /// placeholder character. This is what corrections compare and diff.
    var canonicalText: String {
        map { inline in
            switch inline {
            case let .text(text), let .emphasis(text), let .strong(text): text
            case .noteReference: String(notePlaceholder)
            }
        }.joined()
    }

    /// The text as the editor shows it: each note reference is its label in
    /// `⟦` `⟧` brackets, `?` when the label is unknown.
    func editableText(noteLabels: [Note.ID: String]) -> String {
        map { inline in
            switch inline {
            case let .text(text), let .emphasis(text), let .strong(text): text
            case let .noteReference(id): "⟦\(noteLabels[id] ?? "?")⟧"
            }
        }.joined()
    }

    /// The content after its canonical text was changed to `newText`.
    ///
    /// The change is found as the stretch between the longest common start
    /// and end, so a fixed word keeps the emphasis of the run it was in and
    /// the references outside the stretch stay where they are. New text takes
    /// the style of the first character it replaces (of the one before it
    /// when nothing is replaced). A reference inside the stretch is dropped,
    /// and a placeholder in `newText` has nothing to point to and is
    /// dropped too.
    func replacingText(with newText: String) -> [Inline] {
        var units = flattened
        let old = units.map(\.character)
        let new = [Character](newText)
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] {
            start += 1
        }
        var end = 0
        while end < old.count - start, end < new.count - start,
              old[old.count - 1 - end] == new[new.count - 1 - end]
        {
            end += 1
        }
        let removed = start ..< old.count - end
        let inserted = new[start ..< new.count - end].filter { $0 != notePlaceholder }
        let style = units.insertionStyle(at: start, replacing: !removed.isEmpty)
        units.replaceSubrange(removed, with: inserted.map { Unit.text($0, style) })
        return units.regrouped
    }

    /// The content cut in two after `offset` characters of its canonical
    /// text, with the whitespace at the cut dropped. Each part keeps the
    /// style of its text and the note references it holds. `nil` when
    /// `offset` is outside the text or a part would be empty.
    func splitting(atCanonicalOffset offset: Int) -> (first: [Inline], second: [Inline])? {
        let units = flattened
        guard offset > 0, offset < units.count else { return nil }
        var head = [Unit](units[..<offset])
        var tail = [Unit](units[offset...])
        while head.last?.isWhitespace == true {
            head.removeLast()
        }
        while tail.first?.isWhitespace == true {
            tail.removeFirst()
        }
        guard !head.isEmpty, !tail.isEmpty else { return nil }
        return (head.regrouped, tail.regrouped)
    }

    /// The two contents joined by one space, as the text of a merged block.
    /// Formatting does not cross the space.
    func joined(with other: [Inline]) -> [Inline] {
        self + [.text(" ")] + other
    }

    private var flattened: [Unit] {
        flatMap { inline -> [Unit] in
            switch inline {
            case let .text(text): text.map { Unit.text($0, .plain) }
            case let .emphasis(text): text.map { Unit.text($0, .emphasis) }
            case let .strong(text): text.map { Unit.text($0, .strong) }
            case let .noteReference(id): [.reference(id)]
            }
        }
    }
}

/// One character of inline content, or one note reference.
private enum Unit {
    enum Style { case plain, emphasis, strong }

    case text(Character, Style)
    case reference(Note.ID)

    var character: Character {
        if case let .text(character, _) = self {
            character
        } else {
            notePlaceholder
        }
    }

    var isWhitespace: Bool {
        character.isWhitespace
    }

    var style: Style? {
        if case let .text(_, style) = self {
            style
        } else {
            nil
        }
    }
}

private extension [Unit] {
    /// The style for text inserted at `position`: that of the character it
    /// replaces, or of the one before it for a pure insertion, falling back
    /// to the neighbour on the other side and then to plain text.
    func insertionStyle(at position: Int, replacing: Bool) -> Unit.Style {
        let after = indices.contains(position) ? self[position].style : nil
        let before = position > 0 ? self[position - 1].style : nil
        return (replacing ? after ?? before : before ?? after) ?? .plain
    }

    /// Runs of equal style joined back into inline values.
    var regrouped: [Inline] {
        var result: [Inline] = []
        var run = ""
        var runStyle: Unit.Style = .plain
        func flush() {
            guard !run.isEmpty else { return }
            let inline: Inline = switch runStyle {
            case .plain: .text(run)
            case .emphasis: .emphasis(run)
            case .strong: .strong(run)
            }
            result.append(inline)
            run = ""
        }
        for unit in self {
            switch unit {
            case let .text(character, style):
                if style != runStyle {
                    flush()
                    runStyle = style
                }
                run.append(character)
            case let .reference(id):
                flush()
                result.append(.noteReference(id))
            }
        }
        flush()
        return result
    }
}
