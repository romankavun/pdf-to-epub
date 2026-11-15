import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A page image drawn by code, for tests that need real pixels (marker
/// colour, illustration bands) and real OCR without using anyone's document.
///
/// A page is a list of ``Element``s placed from the top down on a white
/// canvas, like the clean pages the app is designed for: dark body
/// text, link-blue note markers, a centred heading, a grey illustration
/// band with a caption, a page number at the bottom.
public struct SyntheticPage: Sendable {
    /// One thing drawn on the page.
    public enum Element: Sendable {
        /// A line of body text. A leading `>` indents it (a paragraph
        /// start). `{label}` draws a note marker in link blue at that place,
        /// raised and smaller as a reference is; written at the start of a
        /// line it is the label that opens a note text, on the baseline.
        case line(String)
        /// Blank space of the given number of line heights.
        case gap(Double)
        /// A centred heading, `scale` times the body size and bold.
        case heading(String, scale: Double = 1.7)
        /// An illustration band, `height` as a fraction of the page height,
        /// with an optional caption in small centred italics under it,
        /// followed by the wide gap that marks it as a caption.
        case picture(height: Double, caption: String?)
        /// A thin horizontal rule across the text column.
        case rule
        /// A number centred at the bottom of the page.
        case pageNumber(String)
        /// Moves the drawing position to a fraction of the page height from
        /// the top, to place notes at the bottom of a page.
        case moveTo(Double)
    }

    /// Canvas size in pixels; a portrait page like a clean-page source clean page.
    public static let size = CGSize(width: 1200, height: 1700)

    private static let bodySize: CGFloat = 40
    private static let leftMargin: CGFloat = 120
    private static let indent: CGFloat = 48
    private static let linkBlue = CGColor(red: 0.42, green: 0.51, blue: 0.98, alpha: 1)

    public var elements: [Element]

    public init(_ elements: [Element]) {
        self.elements = elements
    }

    /// A page of `count` plain lines of prose that give the document a body
    /// margin: layout analysis measures it from the most common left edge,
    /// so a short page alone would have none. The first line is indented.
    public static func prose(lines count: Int = 16, seed: Int = 0) -> SyntheticPage {
        let words = ["river", "stone", "lantern", "winter", "orchard", "bridge", "morning", "harbour", "meadow", "violin"]
        var elements: [Element] = []
        for index in 0 ..< count {
            let text = (0 ..< 9).map { words[(index * 3 + $0 * 7 + seed) % words.count] }.joined(separator: " ")
            elements.append(.line(index == 0 ? "> " + text : text))
        }
        return SyntheticPage(elements)
    }

    /// Writes the page as a PNG file.
    public func writePNG(to url: URL) throws {
        let image = try render()
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: Drawing

    private func render() throws -> CGImage {
        let width = Int(Self.size.width), height = Int(Self.size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: Self.size))
        context.setShouldAntialias(true)

        // `top` is measured from the top edge; Core Graphics counts from the bottom.
        var top = Self.size.height * 0.07
        let pitch = Self.bodySize * 1.6
        for element in elements {
            switch element {
            case let .line(text):
                drawLine(text, size: Self.bodySize, top: top, in: context)
                top += pitch
            case let .gap(lines):
                top += pitch * lines
            case let .heading(text, scale):
                let size = Self.bodySize * scale
                let line = Self.line(text, size: size, bold: true, italic: false, color: CGColor(gray: 0, alpha: 1))
                draw(line, centredAtTop: top, size: size, in: context)
                top += size * 1.9
            case let .picture(heightFraction, caption):
                let band = CGRect(
                    x: Self.size.width * 0.18, y: Self.size.height - top - Self.size.height * heightFraction,
                    width: Self.size.width * 0.64, height: Self.size.height * heightFraction
                )
                context.setFillColor(CGColor(gray: 0.55, alpha: 1))
                context.fill(band)
                top += Self.size.height * heightFraction + Self.bodySize * 0.6
                if let caption {
                    let size = Self.bodySize * 0.75
                    let line = Self.line(caption, size: size, bold: false, italic: true, color: CGColor(gray: 0, alpha: 1))
                    draw(line, centredAtTop: top, size: size, in: context)
                    // Layout analysis attaches a caption by the wide step
                    // that follows it (ADR 0002), as sample sets have.
                    top += pitch * 3.8
                }
            case .rule:
                context.setFillColor(CGColor(gray: 0.3, alpha: 1))
                context.fill(CGRect(
                    x: Self.leftMargin, y: Self.size.height - top - 2,
                    width: Self.size.width - 2 * Self.leftMargin, height: 2
                ))
                top += pitch * 0.5
            case let .pageNumber(text):
                let size = Self.bodySize * 0.8
                let line = Self.line(text, size: size, bold: false, italic: false, color: CGColor(gray: 0, alpha: 1))
                draw(line, centredAtTop: Self.size.height * 0.95, size: size, in: context)
            case let .moveTo(fraction):
                top = Self.size.height * fraction
            }
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    private func drawLine(_ text: String, size: CGFloat, top: CGFloat, in context: CGContext) {
        var rest = Substring(text)
        var x = Self.leftMargin
        if rest.hasPrefix(">") {
            x += Self.indent
            rest = rest.dropFirst().drop { $0 == " " }
        }
        let black = CGColor(gray: 0, alpha: 1)
        for (index, (text, isMarker)) in Self.runs(of: rest).enumerated() {
            // A label that opens a line (a note text) sits on the baseline at
            // nearly body size, as in a clean-page source's note list; a reference
            // inside a line is smaller and raised.
            let opensLine = isMarker && index == 0
            let runSize = isMarker ? size * (opensLine ? 0.85 : 0.62) : size
            let line = Self.line(text, size: runSize, bold: false, italic: false, color: isMarker ? Self.linkBlue : black)
            // A marker is raised to the height of the capitals of the line.
            let lift = isMarker && !opensLine ? size * 0.38 : 0
            context.textPosition = CGPoint(x: x, y: Self.size.height - top - size + lift)
            CTLineDraw(line, context)
            x += CTLineGetTypographicBounds(line, nil, nil, nil)
        }
    }

    private func draw(_ line: CTLine, centredAtTop top: CGFloat, size: CGFloat, in context: CGContext) {
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: (Self.size.width - width) / 2, y: Self.size.height - top - size)
        CTLineDraw(line, context)
    }

    /// Splits a line at its `{label}` markers into text runs and marker
    /// runs, keeping the spaces that were around them.
    static func runs(of text: Substring) -> [(String, Bool)] {
        var runs: [(String, Bool)] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{", let close = text[index...].firstIndex(of: "}") {
                if !current.isEmpty { runs.append((current, false)) }
                current = ""
                runs.append((String(text[text.index(after: index) ..< close]), true))
                index = text.index(after: close)
            } else {
                current.append(text[index])
                index = text.index(after: index)
            }
        }
        if !current.isEmpty { runs.append((current, false)) }
        return runs
    }

    private static func line(_ text: String, size: CGFloat, bold: Bool, italic: Bool, color: CGColor) -> CTLine {
        let name = switch (bold, italic) {
        case (true, _): "TimesNewRomanPS-BoldMT"
        case (_, true): "TimesNewRomanPS-ItalicMT"
        default: "TimesNewRomanPSMT"
        }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
