import CoreGraphics
import Foundation
import ImageIO
import Vision

/// OCR backed by Apple Vision's document recognition. Runs on device.
///
/// Only lines are taken from Vision; its paragraph grouping and title
/// detection are unreliable on document pages (ADR 0001).
public struct VisionOCREngine: OCREngine {
    /// BCP 47 tags of the languages to recognize, most likely first.
    public let languages: [String]
    /// How long one Vision request may take, in seconds.
    public let requestTimeout: TimeInterval
    /// How many times a request is started before giving up.
    public let attempts: Int

    /// - Parameters:
    ///   - languages: Set explicitly rather than auto-detected: detection
    ///     changed results for the worse on test pages.
    ///   - requestTimeout: Generous by default, because the first request
    ///     in a process loads the model, which has taken up to 90 seconds.
    ///     A request that exceeds it is abandoned and started again: Vision
    ///     occasionally never answers.
    ///   - attempts: Requests that keep timing out fail with
    ///     ``OCRError/timedOut(_:)``.
    public init(languages: [String] = ["uk-UA", "en-US"], requestTimeout: TimeInterval = 180, attempts: Int = 3) {
        self.languages = languages
        self.requestTimeout = requestTimeout
        self.attempts = attempts
    }

    public func recognize(imageAt url: URL, erasing regions: [CGRect]) async throws -> RecognizedPage {
        var image = try Self.loadImage(at: url)
        if !regions.isEmpty {
            guard let raster = Raster(image), let erased = raster.erasing(regions) else {
                throw OCRError.unreadableImage(url)
            }
            image = erased
        }

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await withDeadline(for: url) { [request, image] in
            try await request.perform(on: image)
        }
        let lines = observations.flatMap(\.document.text.lines).compactMap { line -> TextLine? in
            guard let best = line.topCandidates(1).first else { return nil }
            let box = Self.topLeftBox(line.boundingBox)
            let text = best.string
            let words = text.split(separator: " ").map { word in
                // Vision has no word list for a line; the box of a character
                // range is the closest thing. The line box stands in when
                // even that is missing, so `words` always spells `text`.
                let wordBox = best.boundingBox(for: word.startIndex ..< word.endIndex)
                    .map { Self.topLeftBox($0.boundingBox) } ?? box
                return TextWord(text: String(word), box: wordBox)
            }
            return TextLine(text: text, box: box, confidence: best.confidence, words: words)
        }
        return RecognizedPage(lines: lines)
    }

    /// Labels are read from a synthetic image: the regions cut out, turned
    /// into dark-on-white, enlarged and laid out in a row. Recognized where
    /// it stands in the page, a marker is fused into the word before it;
    /// recognized alone, a single character is often not found at all. In a
    /// row with others it is read far more reliably. What is still missing
    /// is retried one region at a time.
    public func readLabels(inImageAt url: URL, regions: [CGRect]) async throws -> [String] {
        guard !regions.isEmpty else { return [] }
        guard let raster = try Raster(Self.loadImage(at: url)) else { throw OCRError.unreadableImage(url) }
        let crops = regions.map(raster.label)

        var labels = [String](repeating: "", count: regions.count)
        for start in stride(from: 0, to: crops.count, by: Self.labelsPerStrip) {
            let indices = start ..< min(start + Self.labelsPerStrip, crops.count)
            guard let strip = LabelStrip(crops: Array(crops[indices]), scale: 3, gap: 60) else { continue }
            for (offset, label) in try await readStrip(strip, of: url).enumerated() {
                labels[start + offset] = label
            }
        }
        for index in labels.indices where labels[index].isEmpty {
            guard let single = LabelStrip(crops: [crops[index]], scale: 4, gap: 32) else { continue }
            labels[index] = try await readStrip(single, of: url).first ?? ""
        }
        return labels
    }

    /// A very wide image is recognized less well, so long rows are split.
    private static let labelsPerStrip = 12

    private func withDeadline<Value: Sendable>(
        for url: URL, _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await Deadline.run(
            seconds: requestTimeout, attempts: attempts, onTimeout: OCRError.timedOut(url), operation
        )
    }

    private func readStrip(_ strip: LabelStrip, of url: URL) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Labels are not words: correction would "fix" them.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]

        var labels = [String](repeating: "", count: strip.spans.count)
        let observations = try await withDeadline(for: url) { [request, image = strip.image] in
            try await request.perform(on: image)
        }
        for observation in observations {
            guard let best = observation.topCandidates(1).first else { continue }
            let text = best.string
            for word in text.split(separator: " ") {
                guard let box = best.boundingBox(for: word.startIndex ..< word.endIndex)?.boundingBox else { continue }
                let centre = Double(box.origin.x + box.width / 2)
                if let index = strip.spans.firstIndex(where: { $0.contains(centre) }) {
                    labels[index] += word
                }
            }
        }
        return labels
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw OCRError.unreadableImage(url) }
        return image
    }

    /// Vision's origin is bottom-left; ours is top-left.
    private static func topLeftBox(_ box: NormalizedRect) -> CGRect {
        CGRect(x: box.origin.x, y: 1 - box.origin.y - box.height, width: box.width, height: box.height)
    }
}
