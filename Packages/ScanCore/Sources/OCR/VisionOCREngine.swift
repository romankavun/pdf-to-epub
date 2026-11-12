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

    /// - Parameter languages: Set explicitly rather than auto-detected:
    ///   detection changed results for the worse on test pages.
    public init(languages: [String] = ["uk-UA", "en-US"]) {
        self.languages = languages
    }

    public func recognize(imageAt url: URL) async throws -> RecognizedPage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw OCRError.unreadableImage(url) }

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: image)
        let lines = observations.flatMap(\.document.text.lines).compactMap { line -> TextLine? in
            guard let best = line.topCandidates(1).first else { return nil }
            let box = line.boundingBox
            // Vision's origin is bottom-left; ours is top-left.
            return TextLine(
                text: best.string,
                box: CGRect(x: box.origin.x, y: 1 - box.origin.y - box.height, width: box.width, height: box.height),
                confidence: best.confidence
            )
        }
        return RecognizedPage(lines: lines)
    }
}
