import Conversion
import DocumentModel
import Foundation
import Importing
import Observation
import OCR

/// State behind the app's main window: pick a folder of page images, enter
/// the document's metadata, convert with progress, export the EPUB.
///
/// The model owns no conversion logic; it sequences a
/// ``ConversionPipeline`` and turns its outcomes into states a view can
/// render.
@MainActor
@Observable
public final class ConversionModel {
    /// Where the window is in the import-convert-export flow.
    public enum Phase: Sendable, Equatable {
        /// No folder chosen yet.
        case empty
        /// A folder is open and can be converted.
        case ready
        case converting(done: Int, total: Int)
        case finished(Conversion)
        case failed(Failure)
    }

    /// Why opening a folder or converting it failed. Kept as cases rather
    /// than text so the view can show a localized message.
    public enum Failure: Sendable, Equatable {
        case notAFolder
        case noImages
        /// Vision stopped answering on a page, after the engine's retries.
        case recognitionTimedOut
        /// Anything else, with the error's own description.
        case other(String)
    }

    /// The outcome of the last export of the current document.
    public enum ExportResult: Sendable, Equatable {
        case saved(URL)
        case failed(String)
    }

    public private(set) var phase: Phase = .empty
    /// The open folder; `nil` until one was opened successfully.
    public private(set) var folder: URL?
    /// The number of page images found in ``folder``.
    public var pageCount: Int {
        pages.count
    }

    public private(set) var exportResult: ExportResult?

    public var title = ""
    public var author = ""
    /// BCP 47 tag of the document's main language.
    public var language = "uk"

    /// The running conversion. Exposed to tests so they can wait for it.
    private(set) var conversionTask: Task<Void, Never>?

    private let pipeline: any ConversionPipeline
    private var pages: [URL] = []
    /// Identifies the current run, so that progress and results arriving
    /// from a cancelled run are dropped.
    private var run = 0

    public init(pipeline: any ConversionPipeline = LivePipeline()) {
        self.pipeline = pipeline
    }

    /// Whether ``start()`` would do anything.
    public var canStart: Bool {
        guard !pages.isEmpty, !trimmed(title).isEmpty else { return false }
        if case .converting = phase {
            return false
        }
        return true
    }

    /// Where to offer saving the EPUB: next to the folder, under its name.
    public var suggestedExportURL: URL? {
        folder.map { $0.deletingLastPathComponent().appendingPathComponent($0.lastPathComponent + ".epub") }
    }

    /// Opens `folder` as the document to convert, replacing whatever was open.
    ///
    /// The title is preset to the folder's name. A folder that cannot be
    /// used moves the model to ``Phase/failed(_:)`` with nothing open.
    public func open(folder: URL) {
        cancelRun()
        exportResult = nil
        do {
            pages = try pipeline.pageURLs(in: folder)
            self.folder = folder
            title = folder.lastPathComponent
            phase = .ready
        } catch {
            pages = []
            self.folder = nil
            phase = .failed(Self.failure(for: error))
        }
    }

    /// Starts converting the open folder. Does nothing when ``canStart`` is
    /// false.
    public func start() {
        guard canStart else { return }
        cancelRun()
        exportResult = nil
        let run = run
        let pages = pages
        let author = trimmed(author)
        let metadata = DocumentMetadata(
            title: trimmed(title), author: author.isEmpty ? nil : author, language: language
        )
        phase = .converting(done: 0, total: pages.count)
        let progress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in self?.report(done: done, total: total, run: run) }
        }
        conversionTask = Task { [pipeline] in
            let outcome: Phase
            do {
                outcome = try await .finished(pipeline.convert(pageURLs: pages, metadata: metadata, progress: progress))
            } catch {
                outcome = .failed(Self.failure(for: error))
            }
            guard run == self.run else { return }
            phase = outcome
        }
    }

    /// Stops the running conversion and returns to ``Phase/ready``.
    ///
    /// The state changes at once, although the pipeline only notices the
    /// cancellation after the page it is working on.
    public func cancel() {
        guard case .converting = phase else { return }
        cancelRun()
        phase = .ready
    }

    /// Writes the converted document to `url`; the outcome lands in
    /// ``exportResult``. Does nothing unless a conversion has finished.
    public func export(to url: URL) async {
        guard case let .finished(conversion) = phase else { return }
        do {
            try await pipeline.export(conversion.document, to: url)
            exportResult = .saved(url)
        } catch {
            exportResult = .failed(String(describing: error))
        }
    }

    private func cancelRun() {
        conversionTask?.cancel()
        conversionTask = nil
        run += 1
    }

    /// Progress callbacks hop to the main actor one by one and may land out
    /// of order or after the run ended, so only forward steps of the
    /// current run are taken.
    private func report(done: Int, total: Int, run: Int) {
        guard run == self.run, case let .converting(current, _) = phase, done > current else { return }
        phase = .converting(done: done, total: total)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func failure(for error: any Error) -> Failure {
        switch error {
        case ImportError.notADirectory: .notAFolder
        case ImportError.noImages: .noImages
        case OCRError.timedOut: .recognitionTimedOut
        default: .other(String(describing: error))
        }
    }
}
