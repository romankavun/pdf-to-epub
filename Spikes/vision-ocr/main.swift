// Vision spike: what does RecognizeDocumentsRequest return for a document page in
// Ukrainian with English fragments?
//
// Usage:
//   swift Spikes/vision-ocr/main.swift                # synthetic page
//   swift Spikes/vision-ocr/main.swift path/to/scan   # a real scan (png/jpg/tiff)
//
// Throwaway exploration code, not part of the product. Findings are recorded
// in docs/adr/0001-vision-document-recognition.md.

import AppKit
import Foundation
import Vision

// MARK: - Synthetic page

/// Renders a page that looks like a typeset document page: running header, centred
/// chapter heading, justified body with a footnote marker, a grey box standing
/// in for an illustration with a caption, a footnote, and a page number.
func renderSyntheticPage() -> CGImage {
    let width = 1654, height = 2339 // A4 at 200 dpi
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    func style(_ alignment: NSTextAlignment, indent: CGFloat = 0) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.firstLineHeadIndent = indent
        paragraph.hyphenationFactor = 1
        return paragraph
    }
    func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Times New Roman Bold" : "Times New Roman", size: size)!
    }
    func draw(_ text: NSAttributedString, y: CGFloat, height: CGFloat) {
        text.draw(in: NSRect(x: 200, y: y, width: CGFloat(width) - 400, height: height))
    }
    func plain(_ string: String, size: CGFloat, _ alignment: NSTextAlignment,
               bold: Bool = false, indent: CGFloat = 0) -> NSAttributedString
    {
        NSAttributedString(string: string, attributes: [
            .font: font(size, bold: bold), .foregroundColor: NSColor.black,
            .paragraphStyle: style(alignment, indent: indent),
            .languageIdentifier: "uk",
        ])
    }

    draw(plain("ІВАН ФРАНКО. ЗАХАР БЕРКУТ", size: 26, .center), y: 120, height: 40)
    draw(plain("Розділ третій", size: 64, .center, bold: true), y: 260, height: 90)

    let body = NSMutableAttributedString(attributedString: plain(
        "Сумно і непривітно тепер в нашій Тухольщині! Казкою видається повість про давні часи і давніх людей. "
            + "Старий Захар часто згадував слова мандрівника, який казав англійською: «The mountains remember "
            + "everything», і додавав, що громада",
        size: 38, .justified, indent: 50
    ))
    body.append(NSAttributedString(string: "1", attributes: [
        .font: font(22), .baselineOffset: 16, .foregroundColor: NSColor.black,
    ]))
    body.append(plain(
        " мусить пам'ятати свою минувшину так само міцно, як гори пам'ятають кожну бурю.\n"
            + "Непроглядні ліси покривали майже всю долину, крім високих полонин, де випасали худобу "
            + "влітку пастухи з навколишніх сіл; звідти відкривався краєвид на цілий Підкарпатський край, "
            + "і подорожні зупинялися там, щоб перепочити перед довгою дорогою.",
        size: 38, .justified, indent: 50
    ))
    draw(body, y: 420, height: 700)

    NSColor(white: 0.55, alpha: 1).setFill()
    NSRect(x: 427, y: 1150, width: 800, height: 500).fill()
    draw(plain("Рис. 4. Тухольська долина восени", size: 30, .center), y: 1670, height: 40)

    NSColor.black.setFill()
    NSRect(x: 200, y: 2020, width: 300, height: 2).fill()
    draw(plain("1 Громада — тут: сільська спільнота, що сама вирішувала свої справи (англ. community).",
               size: 28, .left), y: 2035, height: 90)
    draw(plain("47", size: 30, .center), y: 2180, height: 40)

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// MARK: - Reporting

func describe(_ rect: NormalizedRect) -> String {
    String(format: "x=%.2f y=%.2f w=%.2f h=%.2f", rect.origin.x, rect.origin.y, rect.width, rect.height)
}

/// Scales an image by an integer factor; used to test whether small type is
/// recognized better when enlarged.
func upscale(_ image: CGImage, by factor: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: image.width * factor, height: image.height * factor,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * factor, height: image.height * factor))
    return context.makeImage()!
}

/// Prints a structural summary. Text is truncated on purpose: the spike is
/// about structure and confidence, not about dumping document content.
func report(image: CGImage, languages: [String]?, verbose: Bool) async throws {
    var request = RecognizeDocumentsRequest()
    if let languages {
        request.textRecognitionOptions.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.automaticallyDetectLanguage = false
    } else {
        request.textRecognitionOptions.automaticallyDetectLanguage = true
    }
    request.textRecognitionOptions.useLanguageCorrection = true

    let start = Date()
    let observations = try await request.perform(on: image)
    let elapsed = Date().timeIntervalSince(start)
    guard let document = observations.first?.document else {
        print("  no document observation"); return
    }
    let lines = document.paragraphs.flatMap(\.lines)
    let confidences = lines.compactMap { $0.topCandidates(1).first?.confidence }
    print(String(
        format: "  %dx%d langs=%@ time=%.2fs paragraphs=%d lines=%d lists=%d tables=%d title=%@ conf min/avg=%.2f/%.2f",
        image.width,
        image.height,
        languages?.joined(separator: "+") ?? "auto",
        elapsed,
        document.paragraphs.count,
        lines.count,
        document.lists.count,
        document.tables.count,
        document.title == nil ? "no" : "yes",
        confidences.min() ?? 0,
        confidences.reduce(0, +) / Float(max(confidences.count, 1))
    ))
    guard verbose else { return }
    for (index, paragraph) in document.paragraphs.enumerated() {
        let alignment = paragraph.textAlignment.map { "\($0)" } ?? "nil"
        let heights = paragraph.lines.map(\.boundingBox.height)
        let lineConfidences = paragraph.lines.compactMap { $0.topCandidates(1).first?.confidence }
        print(String(format: "  #%02d [%@] align=%@ lines=%d lineH=%.4f conf=%.2f | %@",
                     index, describe(paragraph.boundingRegion.boundingBox), alignment, paragraph.lines.count,
                     heights.max() ?? 0, lineConfidences.min() ?? 0,
                     String(paragraph.transcript.prefix(48)).replacingOccurrences(of: "\n", with: " / ")))
    }
}

// MARK: - Coloured text (note references)

/// Fraction of "ink" pixels inside a normalized box that are distinctly blue.
/// clean pages render note references as blue links, so colour is a
/// candidate signal for finding them.
func blueInkFraction(in box: NormalizedRect, of image: CGImage, pixels: [UInt8]) -> Double {
    let rect = box.toImageCoordinates(CGSize(width: image.width, height: image.height), origin: .upperLeft)
    var ink = 0, blue = 0
    for y in max(0, Int(rect.minY)) ..< min(image.height, Int(rect.maxY)) {
        for x in max(0, Int(rect.minX)) ..< min(image.width, Int(rect.maxX)) {
            let offset = (y * image.width + x) * 4
            let (r, g, b) = (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
            if r + g + b < 540 {
                ink += 1
            }
            if b > r + 60, b > g + 40 {
                blue += 1
            }
        }
    }
    return ink == 0 ? 0 : Double(blue) / Double(ink)
}

func reportColouredWords(image: CGImage) async throws {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
        data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "uk-UA")]
    guard let document = try await request.perform(on: image).first?.document else { return }
    var hits: [String] = []
    for paragraph in document.paragraphs {
        for word in paragraph.words ?? [] {
            let fraction = blueInkFraction(in: word.boundingBox, of: image, pixels: pixels)
            if fraction > 0.05, let text = word.topCandidates(1).first?.string {
                hits.append(String(format: "%@(%.2f)", String(text.suffix(8)), fraction))
            }
        }
    }
    print("  words containing blue ink (last 8 chars, blue fraction): \(hits.joined(separator: " "))")
}

// MARK: - Entry point

let paths = CommandLine.arguments.dropFirst()
if paths.isEmpty {
    let image = renderSyntheticPage()
    print("synthetic page")
    try await report(image: image, languages: ["uk-UA", "en-US"], verbose: true)
    try await report(image: image, languages: ["uk-UA"], verbose: false)
    try await report(image: upscale(image, by: 2), languages: ["uk-UA", "en-US"], verbose: true)
}

for path in paths {
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: path))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fatalError("Cannot load image at \(path)")
    }
    print(path)
    try await report(image: image, languages: ["uk-UA", "en-US"], verbose: true)
    try await report(image: image, languages: ["uk-UA"], verbose: false)
    try await report(image: image, languages: nil, verbose: false)
    try await reportColouredWords(image: image)
}
