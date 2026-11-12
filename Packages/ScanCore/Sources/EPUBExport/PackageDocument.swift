import DocumentModel
import Foundation

/// Builds the EPUB package document (`.opf`): metadata, the manifest of every
/// file in the publication, and the spine that sets reading order.
enum PackageDocument {
    /// - Parameter modified: Written as `dcterms:modified`, which EPUB 3
    ///   requires. Passed in rather than read from the clock so that exports
    ///   are reproducible.
    static func render(_ document: Document, modified: Date) -> String {
        let metadata = document.metadata
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"pub-id\" "
                + "xml:lang=\"\(metadata.language.xmlEscaped)\">",
            "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">",
            "<dc:identifier id=\"pub-id\">\(metadata.identifier.xmlEscaped)</dc:identifier>",
            "<dc:title>\(metadata.title.xmlEscaped)</dc:title>",
            "<dc:language>\(metadata.language.xmlEscaped)</dc:language>",
        ]
        if let author = metadata.author {
            lines.append("<dc:creator>\(author.xmlEscaped)</dc:creator>")
        }
        lines.append("<meta property=\"dcterms:modified\">\(modified.formatted(.iso8601))</meta>")
        lines.append("</metadata>")

        lines.append("<manifest>")
        lines.append(item(
            id: "nav",
            href: EPUBLayout.navigationDocument,
            mediaType: "application/xhtml+xml",
            properties: "nav"
        ))
        lines.append(item(id: "style", href: EPUBLayout.stylesheet, mediaType: "text/css"))
        let chapterIDs = document.chapters.indices.map { index in
            EPUBLayout.chapterPath(index: index).replacingOccurrences(of: ".xhtml", with: "")
        }
        for (index, id) in chapterIDs.enumerated() {
            lines.append(item(id: id, href: EPUBLayout.chapterPath(index: index), mediaType: "application/xhtml+xml"))
        }
        for (index, image) in document.images.enumerated() {
            lines.append(item(
                id: "image-\(index + 1)", href: EPUBLayout.imagePath(image), mediaType: image.mediaType,
                properties: image.id == document.coverImageID ? "cover-image" : nil
            ))
        }
        lines.append("</manifest>")

        lines.append("<spine>")
        lines += chapterIDs.map { "<itemref idref=\"\($0)\"/>" }
        lines.append("</spine>")
        lines.append("</package>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func item(id: String, href: String, mediaType: String, properties: String? = nil) -> String {
        let propertiesAttribute = properties.map { " properties=\"\($0)\"" } ?? ""
        // swiftlint:disable:next line_length
        return "<item id=\"\(id)\" href=\"\(href.xmlEscaped)\" media-type=\"\(mediaType.xmlEscaped)\"\(propertiesAttribute)/>"
    }
}
