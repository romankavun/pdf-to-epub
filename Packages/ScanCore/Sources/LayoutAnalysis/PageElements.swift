import CoreGraphics
import OCR

/// A thing on a page that takes part in reading order.
enum PageElement {
    case row(Row)
    case picture(PagePicture)

    var top: CGFloat {
        switch self {
        case let .row(row): row.line.box.minY
        case let .picture(picture): picture.box.minY
        }
    }

    var row: Row? {
        if case let .row(row) = self {
            row
        } else {
            nil
        }
    }
}

/// One visual line of text with the note markers that sit on it.
struct Row {
    /// The text of the line. Its box includes a marker that opens the line,
    /// so that indentation is measured from where the line really starts.
    var line: TextLine
    /// Markers on the line from left to right, with their index among all
    /// markers of the document.
    var markers: [(index: Int, box: CGRect)] = []

    /// The marker standing before the first word, if any. A list number
    /// before it ("12. ") does not count as a word: endnotes are often set
    /// as a numbered list with the note's own label after the number.
    var leadingMarker: Int? {
        guard let first = markers.first, !isRemainder else { return nil }
        let before = wordsBefore(first.box)
        return before == 0 || (before == 1 && hasListNumber) ? first.index : nil
    }

    /// Whether the line is the end of the line above, reported as a line of
    /// its own: it opens with a marker followed by punctuation that closes
    /// a sentence or clause, which no note text starts with. The engine
    /// does this now and then right after an erased marker.
    var isRemainder: Bool {
        guard let first = markers.first, wordsBefore(first.box) == 0,
              let next = words.first(where: { $0.box.midX > first.box.midX })
        else { return false }
        return next.text.isClosingPunctuation || ["•", "·"].contains(next.text.first)
    }

    /// Whether the line opens with a list number followed by a marker.
    var opensListItem: Bool {
        guard let first = markers.first else { return false }
        return wordsBefore(first.box) == 1 && hasListNumber
    }

    /// Whether the first word is a list number such as "12." or "3)".
    ///
    /// Tolerant on purpose: on real pages the digits come back as
    /// look-alike letters and the full stop as a hyphen ("IO.", "39-").
    private var hasListNumber: Bool {
        words.first?.text.wholeMatch(of: /[0-9IlOoІОЗi|]{1,4}[.)\-]/) != nil
    }

    /// The line as text with references where its markers stand.
    ///
    /// - Parameter skippingLeadingMarker: Leaves out a marker that opens the
    ///   line, and a list number before it, for when the marker is the label
    ///   of a note rather than a reference.
    func pieces(skippingLeadingMarker: Bool) -> [Piece] {
        let isLabelled = skippingLeadingMarker && leadingMarker != nil
        let markers = isLabelled ? Array(markers.dropFirst()) : markers
        let words = isLabelled && opensListItem ? Array(words.dropFirst()) : words
        guard !markers.isEmpty || isLabelled else {
            return [.text(line.text.trimmingCharacters(in: .whitespaces))]
        }

        var pieces: [Piece] = []
        var text = ""
        var afterReference = false
        func closeText() {
            if !text.isEmpty {
                pieces.append(.text(text))
                text = ""
            }
        }
        let positions = markers.map { marker in
            (index: marker.index, wordsBefore: words.count { $0.box.midX < marker.box.midX })
        }
        for (wordIndex, word) in words.enumerated() {
            for marker in positions where marker.wordsBefore == wordIndex {
                closeText()
                pieces.append(.reference(marker.index))
                afterReference = true
            }
            // A full stop left on its own by an erased marker is read as a
            // bullet.
            let token = afterReference && ["•", "·"].contains(word.text) ? "." : word.text
            let isFirst = pieces.isEmpty && text.isEmpty
            text += (isFirst || (afterReference && token.isClosingPunctuation) ? "" : " ") + token
            afterReference = false
        }
        closeText()
        pieces += positions.filter { $0.wordsBefore >= words.count }.map { .reference($0.index) }
        return pieces
    }

    /// How many words of the line lie to the left of `box`.
    private func wordsBefore(_ box: CGRect) -> Int {
        words.count { $0.box.midX < box.midX }
    }

    /// The words of the line; estimated from the text when the engine did
    /// not report them, assuming characters of equal width.
    private var words: [TextWord] {
        guard line.words.isEmpty else { return line.words }
        let text = line.text
        guard !text.isEmpty else { return [] }
        let characterWidth = line.box.width / CGFloat(text.count)
        return text.split(separator: " ").map { word in
            let start = text.distance(from: text.startIndex, to: word.startIndex)
            return TextWord(text: String(word), box: CGRect(
                x: line.box.minX + CGFloat(start) * characterWidth, y: line.box.minY,
                width: CGFloat(word.count) * characterWidth, height: line.box.height
            ))
        }
    }
}

extension LayoutAnalyzer {
    /// The lines and pictures of a page from top to bottom, without the page
    /// number and without text or markers that lie inside a picture.
    ///
    /// - Parameter firstMarkerIndex: The index, among all markers of the
    ///   document, of the page's first marker.
    func elements(of page: PageContent, firstMarkerIndex: Int) -> [PageElement] {
        func isInPicture(_ box: CGRect) -> Bool {
            page.pictures.contains { $0.box.contains(CGPoint(x: box.midX, y: box.midY)) }
        }
        let lines = joiningPieces(page.lines.filter { !isInPicture($0.box) }).sorted { $0.box.minY < $1.box.minY }
        var rows = lines.map { Row(line: $0) }
        for (offset, marker) in page.markers.enumerated() where !isInPicture(marker.box) {
            // The line the marker stands on: the one whose height contains
            // the marker's centre, closest in height if several do.
            let onLine = rows.indices.filter { rows[$0].line.box.minY ... rows[$0].line.box.maxY ~= marker.box.midY }
            guard let index = onLine.min(by: {
                abs(rows[$0].line.box.midY - marker.box.midY) < abs(rows[$1].line.box.midY - marker.box.midY)
            }) else { continue }
            rows[index].markers.append((firstMarkerIndex + offset, marker.box))
        }
        rows = rows.map { row in
            var row = row
            row.markers.sort { $0.box.minX < $1.box.minX }
            if row.leadingMarker != nil, let first = row.markers.first {
                row.line.box = row.line.box.union(first.box)
            }
            return row
        }
        return (withoutPageNumber(rows).map(PageElement.row) + page.pictures.map(PageElement.picture))
            .sorted { $0.top < $1.top }
    }

    /// Joins boxes that sit side by side on one row into a single line.
    ///
    /// The OCR engine sometimes reports one visual line as two or more
    /// pieces. Left alone, a right-hand piece looks like an indented line and
    /// breaks the paragraph. Pieces share most of their height and do not
    /// overlap horizontally; lines above each other never satisfy both.
    private func joiningPieces(_ lines: [TextLine]) -> [TextLine] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.box.minX < $1.box.minX }) {
            let row = rows.firstIndex { row in
                row.allSatisfy { other in
                    let shared = min(line.box.maxY, other.box.maxY) - max(line.box.minY, other.box.minY)
                    return shared > 0.5 * min(line.box.height, other.box.height) && other.box.maxX <= line.box.minX
                }
            }
            if let row {
                rows[row].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.compactMap { row in
            guard var joined = row.first else { return nil }
            // Words are kept only if every piece has them; otherwise they
            // are estimated from the joined text.
            let haveWords = row.allSatisfy { !$0.words.isEmpty }
            for piece in row.dropFirst() {
                joined.text += " " + piece.text
                joined.box = joined.box.union(piece.box)
                joined.confidence = min(joined.confidence, piece.confidence)
                joined.words += piece.words
            }
            if !haveWords {
                joined.words = []
            }
            return joined
        }
    }

    /// Removes the last line when it looks like a page number: short, digits
    /// only, near the bottom of the page.
    private func withoutPageNumber(_ rows: [Row]) -> [Row] {
        guard let last = rows.last, last.line.box.minY > options.pageNumberZone else { return rows }
        let text = last.line.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 4, text.allSatisfy(\.isNumber) else { return rows }
        return Array(rows.dropLast())
    }
}
