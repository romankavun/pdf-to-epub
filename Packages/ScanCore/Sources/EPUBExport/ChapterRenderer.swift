import DocumentModel

/// Turns one chapter into an EPUB 3 XHTML content document.
///
/// Notes referenced by the chapter are written at its end as
/// `epub:type="footnote"` asides in the same file. Reading systems that
/// support pop-up footnotes (Apple Documents among them) only do so reliably when
/// the note lives in the same document as its reference; others show the
/// notes as a list after the chapter, with links back to the text.
struct ChapterRenderer {
    let document: Document

    func render(_ chapter: Chapter) throws -> String {
        var state = NoteState()
        var body = ""
        for block in chapter.blocks {
            body += try render(block, state: &state) + "\n"
        }
        if !state.order.isEmpty {
            body += "<section class=\"notes\" epub:type=\"footnotes\">\n"
            for id in state.order {
                // Presence was checked when the reference was rendered.
                guard let note = document.note(withID: id) else { throw EPUBExportError.missingNote(id: id) }
                var noteState = NoteState()
                let content = try render(note.content, state: &noteState)
                body += "<aside id=\"note-\(id.xmlEscaped)\" epub:type=\"footnote\">"
                    + "<p><a href=\"#ref-\(id.xmlEscaped)\">\(note.label.xmlEscaped)</a> \(content)</p></aside>\n"
            }
            body += "</section>\n"
        }
        let language = document.metadata.language.xmlEscaped
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
        <head>
        <meta charset="UTF-8"/>
        <title>\(chapter.title.xmlEscaped)</title>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
        \(body)</body>
        </html>

        """
    }

    /// Tracks which notes a chapter has referenced so far.
    private struct NoteState {
        /// Note identifiers in order of first reference.
        var order: [Note.ID] = []
    }

    private func render(_ block: Block, state: inout NoteState) throws -> String {
        switch block {
        case let .heading(level, content):
            let tag = "h\(min(max(level, 1), 6))"
            return try "<\(tag)>\(render(content, state: &state))</\(tag)>"
        case let .paragraph(content):
            return try "<p>\(render(content, state: &state))</p>"
        case let .figure(figure):
            guard let image = document.image(withID: figure.imageID) else {
                throw EPUBExportError.missingImage(id: figure.imageID)
            }
            var html = "<figure><img src=\"\(EPUBLayout.imagePath(image).xmlEscaped)\" "
                + "alt=\"\(figure.alternativeText.xmlEscaped)\"/>"
            if !figure.caption.isEmpty {
                html += try "<figcaption>\(render(figure.caption, state: &state))</figcaption>"
            }
            return html + "</figure>"
        }
    }

    private func render(_ content: [Inline], state: inout NoteState) throws -> String {
        var html = ""
        for inline in content {
            switch inline {
            case let .text(text):
                html += text.xmlEscaped
            case let .emphasis(text):
                html += "<em>\(text.xmlEscaped)</em>"
            case let .strong(text):
                html += "<strong>\(text.xmlEscaped)</strong>"
            case let .noteReference(id):
                guard let note = document.note(withID: id) else { throw EPUBExportError.missingNote(id: id) }
                // Only the first reference gets an id: ids must be unique, and
                // the note's back link can only point at one place.
                var idAttribute = ""
                if !state.order.contains(id) {
                    state.order.append(id)
                    idAttribute = " id=\"ref-\(id.xmlEscaped)\""
                }
                html += "<a class=\"noteref\" epub:type=\"noteref\"\(idAttribute) "
                    + "href=\"#note-\(id.xmlEscaped)\">\(note.label.xmlEscaped)</a>"
            }
        }
        return html
    }
}
