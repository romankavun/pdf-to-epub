import DocumentModel

/// Connects note references to note texts and produces the final blocks.
///
/// Note texts come in runs: at the end of a section or all together at the
/// end of the document. Within a run they are numbered in sequence, which is
/// used to repair their labels (``NoteNumbering``). A reference is then
/// linked by its own label:
///
/// - to the note that carries the same number; if several do (numbering
///   that restarts in every chapter), to the one nearest to where the
///   references before it have got to;
/// - when its label could not be read, or no note carries it, to the next
///   note in order. This is a guess that suits notes referred to once each,
///   in sequence.
///
/// Order alone is not enough: a document that cites sources refers to the same
/// note several times and not in sequence.
struct NoteLinker {
    let markers: [NoteMarker]

    /// A note text with its repaired label.
    private struct Body {
        var label: String
        var kind: NoteNumbering.Kind
        var value: Int?
        var content: [Piece]
        var isReferenced = false
    }

    func layout(of drafts: [DraftBlock]) -> DocumentLayout {
        var bodies = bodies(in: drafts)
        var cursor = 0
        var unlinkedReferences = 0
        // Markers to the index of the note they refer to.
        var links: [Int: Int] = [:]
        for marker in drafts.flatMap(references) {
            if let target = target(of: markers[marker].label, in: bodies, cursor: &cursor) {
                links[marker] = target
                bodies[target].isReferenced = true
            } else {
                unlinkedReferences += 1
            }
        }

        var blocks: [Block] = []
        var noteIndex = 0
        for draft in drafts {
            switch draft {
            case let .heading(pieces):
                blocks.append(.heading(level: 1, content: inlines(pieces, links: links)))
            case let .paragraph(pieces):
                blocks.append(.paragraph(inlines(pieces, links: links)))
            case let .figure(imageID, caption):
                let caption = inlines(caption, links: links)
                blocks.append(.figure(Figure(imageID: imageID, alternativeText: "", caption: caption)))
            case .note:
                let body = bodies[noteIndex]
                noteIndex += 1
                if !body.isReferenced {
                    blocks.append(.paragraph(inlines([.text(body.label + " ")] + body.content)))
                }
            }
        }
        let notes = bodies.enumerated().filter(\.element.isReferenced).map { index, body in
            // A reference inside a note stays text: notes do not nest.
            Note(id: Self.noteID(index), label: body.label, content: inlines(body.content))
        }
        return DocumentLayout(
            blocks: blocks, notes: notes, unlinkedReferences: unlinkedReferences,
            unlinkedNotes: bodies.count { !$0.isReferenced }
        )
    }

    /// Inline content for `pieces`. A marker becomes a reference to the
    /// note it is linked to, or its label as plain text.
    ///
    /// - Parameter links: Marker indices to the index of the note they
    ///   refer to.
    private func inlines(_ pieces: [Piece], links: [Int: Int] = [:]) -> [Inline] {
        var inlines: [Inline] = []
        for piece in pieces {
            let inline: Inline = switch piece {
            case let .text(text): .text(text)
            case let .reference(marker):
                links[marker].map { .noteReference(Self.noteID($0)) }
                    ?? .text(markers[marker].label.trimmingCharacters(in: .whitespaces))
            }
            if case let .text(text) = inline, case let .text(before) = inlines.last {
                inlines[inlines.count - 1] = .text(before + text)
            } else if inline != .text("") {
                inlines.append(inline)
            }
        }
        return inlines
    }

    private static func noteID(_ index: Int) -> Note.ID {
        "note-\(index + 1)"
    }

    /// The note texts in order, with labels repaired run by run.
    private func bodies(in drafts: [DraftBlock]) -> [Body] {
        var bodies: [Body] = []
        var run: [(marker: Int, content: [Piece])] = []
        var position: NoteNumbering.Position?
        func closeRun() {
            let numbering = NoteNumbering.labels(for: run.map { markers[$0.marker].label }, after: position)
            position = numbering.last
            for (index, note) in run.enumerated() {
                bodies.append(Body(
                    label: numbering.labels[index], kind: numbering.kind, value: numbering.values[index],
                    content: note.content
                ))
            }
            run = []
        }
        for draft in drafts {
            if case let .note(marker, content) = draft {
                run.append((marker, content))
            } else if !run.isEmpty {
                closeRun()
            }
        }
        closeRun()
        return bodies
    }

    /// The markers that are references, in reading order. Markers inside a
    /// note are not: notes do not refer to notes.
    private func references(in draft: DraftBlock) -> [Int] {
        let pieces: [Piece] = switch draft {
        case let .heading(pieces), let .paragraph(pieces), let .figure(_, pieces): pieces
        case .note: []
        }
        return pieces.compactMap { piece in
            if case let .reference(marker) = piece {
                marker
            } else {
                nil
            }
        }
    }

    /// The note a reference with the given label points to.
    ///
    /// - Parameter cursor: The note after the furthest one referred to so
    ///   far; moved past the note that is returned.
    private func target(of label: String, in bodies: [Body], cursor: inout Int) -> Int? {
        let matching = bodies.indices.filter { index in
            guard let value = bodies[index].value else { return false }
            return NoteNumbering.value(of: label, as: bodies[index].kind) == value
        }
        // Equally near notes before and after: the later one, since text
        // refers forward more often than back.
        let position = cursor
        let nearest = matching.min { (abs($0 - position), -$0) < (abs($1 - position), -$1) }
        guard let target = nearest ?? (cursor < bodies.count ? cursor : nil) else { return nil }
        cursor = max(cursor, target + 1)
        return target
    }
}
