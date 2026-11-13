import DocumentModel

/// Connects note references to note texts and produces the final blocks.
///
/// Note texts come in runs: at the end of a section or all together at the
/// end of the document. Within a run they are numbered in sequence, which is
/// used to repair their labels (``NoteNumbering``). A reference is then
/// linked by its own label:
///
/// - to the note that carries the same number; if several do (numbering
///   that restarts in every chapter, or two kinds of notes numbered apart),
///   to the one the reference most likely belongs to (see
///   ``target(of:among:in:cursor:)``);
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
        /// Index of the note's draft block, which places it in reading order.
        var position: Int
        var isReferenced = false
    }

    /// A marker and the index of the draft block it stands in.
    private struct Reference {
        var marker: Int
        var position: Int
    }

    /// - Parameter sources: The origin of each block of `drafts`.
    func layout(of drafts: [DraftBlock], sources: [BlockSource]) -> DocumentLayout {
        var bodies = bodies(in: drafts)
        let references = drafts.enumerated().flatMap { position, draft in
            references(in: draft).map { Reference(marker: $0, position: position) }
        }
        var cursor = 0
        var unlinkedReferences = 0
        // Markers to the index of the note they refer to.
        var links: [Int: Int] = [:]
        for index in references.indices {
            if let target = target(of: index, among: references, in: bodies, cursor: &cursor) {
                links[references[index].marker] = target
                bodies[target].isReferenced = true
            } else {
                unlinkedReferences += 1
            }
        }

        var blocks: [Block] = []
        var kept: [BlockSource] = []
        var noteIndex = 0
        for (draft, source) in zip(drafts, sources) {
            defer {
                // A linked note leaves the flow of blocks, and its source with it.
                if kept.count < blocks.count {
                    kept.append(source)
                }
            }
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
            blocks: blocks, sources: kept, notes: notes, unlinkedReferences: unlinkedReferences,
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
        // The marker that opens each note, where it stands, and the text.
        var run: [(opening: Reference, content: [Piece])] = []
        var position: NoteNumbering.Position?
        func closeRun() {
            let numbering = NoteNumbering.labels(for: run.map { markers[$0.opening.marker].label }, after: position)
            position = numbering.last
            for (index, note) in run.enumerated() {
                bodies.append(Body(
                    label: numbering.labels[index], kind: numbering.kind, value: numbering.values[index],
                    content: note.content, position: note.opening.position
                ))
            }
            run = []
        }
        for (draftIndex, draft) in drafts.enumerated() {
            if case let .note(marker, content) = draft {
                run.append((Reference(marker: marker, position: draftIndex), content))
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

    /// The note that `references[index]` points to.
    ///
    /// Notes are printed after the text that refers to them. When several
    /// notes ahead carry the reference's number (notes after each section
    /// and a list of sources at the end, numbered apart), the reference's
    /// own note is the nearest one that
    ///
    /// - lies in the first group of notes after the reference (notes with
    ///   no reference between them), or after the last reference of the
    ///   document, where notes collected at the end are; and
    /// - has no later reference before it that carries the same number. A
    ///   note after a section is referred to just before it appears, so an
    ///   earlier reference with that number cites something else.
    ///
    /// Without such a note the reference repeats an earlier citation and
    /// takes the furthest note ahead: the list a document refers to again and
    /// again is the one collected at its end. With no note ahead (a
    /// reference back) it takes the matching note nearest to where the
    /// references have got to, and with no matching note at all the next
    /// note in order.
    ///
    /// - Parameter cursor: The note after the furthest one referred to so
    ///   far; moved past the note that is returned.
    private func target(
        of index: Int, among references: [Reference], in bodies: [Body], cursor: inout Int
    ) -> Int? {
        let reference = references[index]
        func carries(_ marker: Int, _ body: Body) -> Bool {
            body.value != nil && NoteNumbering.value(of: markers[marker].label, as: body.kind) == body.value
        }
        let matching = bodies.indices.filter { carries(reference.marker, bodies[$0]) }
        let ahead = matching.filter { bodies[$0].position > reference.position }
        let later = references[(index + 1)...]
        let groupStart = bodies.first { $0.position > reference.position }?.position
        let lastReference = references.last?.position ?? 0
        let own = ahead.first { candidate in
            let note = bodies[candidate]
            let isNear = groupStart.map { start in
                !later.contains { (start ..< note.position).contains($0.position) }
            } ?? false
            return (isNear || note.position > lastReference)
                && !later.contains { $0.position < note.position && carries($0.marker, note) }
        }
        let position = cursor
        // Equally near notes before and after the cursor: the later one,
        // since text refers forward more often than back.
        let nearest = own ?? ahead.last
            ?? matching.min { (abs($0 - position), -$0) < (abs($1 - position), -$1) }
        guard let target = nearest ?? (cursor < bodies.count ? cursor : nil) else { return nil }
        cursor = max(cursor, target + 1)
        return target
    }
}
