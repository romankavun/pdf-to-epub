import DocumentModel

/// File names and locations inside the EPUB container. Paths other than
/// ``contentDirectory`` are relative to it, which is also where every content
/// document lives, so they can be used directly in `href` and `src`.
enum EPUBLayout {
    static let contentDirectory = "EPUB"
    static let packageDocument = "package.opf"
    static let navigationDocument = "nav.xhtml"
    static let stylesheet = "style.css"

    /// `chapter-001.xhtml` for index 0, and so on.
    static func chapterPath(index: Int) -> String {
        let number = String(index + 1)
        return "chapter-" + String(repeating: "0", count: max(0, 3 - number.count)) + number + ".xhtml"
    }

    static func imagePath(_ image: ImageResource) -> String {
        "images/" + image.filename
    }
}
