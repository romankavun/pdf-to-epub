import Conversion
import Foundation

public extension ConversionModel {
    /// Where the window is in the import-convert-export flow.
    enum Phase: Sendable, Equatable {
        /// No folder chosen yet.
        case empty
        /// A folder or PDF is open and can be converted.
        case ready
        /// The pages of a PDF are being drawn as images, the step before
        /// recognition.
        case rendering(done: Int, total: Int)
        case converting(done: Int, total: Int)
        case finished(Conversion)
        case failed(Failure)
    }

    /// Why opening a folder or converting it failed. Kept as cases rather
    /// than text so the view can show a localized message.
    enum Failure: Sendable, Equatable {
        case notAFolder
        case noImages
        /// The file is not a PDF the system can read.
        case pdfUnreadable
        /// The PDF is protected by a password.
        case pdfPasswordRequired
        case pdfNoPages
        /// Vision stopped answering on a page, after the engine's retries.
        case recognitionTimedOut
        /// Anything else, with the error's own description.
        case other(String)
    }

    /// The outcome of the last export of the current document.
    enum ExportResult: Sendable, Equatable {
        case saved(URL)
        case failed(String)
    }

    /// A page image being recognized, for the progress screen to show.
    struct PageInProgress: Sendable, Equatable {
        /// One-based position of the page in the document.
        public var number: Int
        public var url: URL

        public init(number: Int, url: URL) {
            self.number = number
            self.url = url
        }
    }
}
