import DocumentModel

/// Builds the EPUB navigation document: the table of contents that reading
/// systems show in their own UI. One flat entry per chapter.
enum NavigationDocument {
    static func render(_ document: Document) -> String {
        let language = document.metadata.language.xmlEscaped
        let entries = document.chapters.enumerated().map { index, chapter in
            "<li><a href=\"\(EPUBLayout.chapterPath(index: index))\">\(chapter.title.xmlEscaped)</a></li>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
        <head>
        <meta charset="UTF-8"/>
        <title>\(document.metadata.title.xmlEscaped)</title>
        </head>
        <body>
        <nav epub:type="toc" id="toc">
        <h1>\(document.metadata.title.xmlEscaped)</h1>
        <ol>
        \(entries)
        </ol>
        </nav>
        </body>
        </html>

        """
    }
}
