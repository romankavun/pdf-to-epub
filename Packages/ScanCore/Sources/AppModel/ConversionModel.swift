import Conversion
import Corrections
import DocumentModel
import Foundation
import Importing
import Observation
import OCR

/// State behind the app's main window: pick a folder of page images or a PDF, enter
/// the document's metadata, convert with progress, export the EPUB.
///
/// The model owns no conversion logic; it sequences a
/// ``ConversionPipeline`` and turns its outcomes into states a view can
/// render.
@MainActor
@Observable
public final class ConversionModel {
    /// Where the run is: nothing opened, converting, finished or failed.
    public private(set) var phase: Phase = .empty
    /// The open folder of scans, PDF or project; `nil` until one was opened
    /// successfully.
    public private(set) var input: URL?
    /// The number of pages of the open document: page images found in the folder
    /// or pages of the PDF.
    public var pageCount: Int {
        pdf != nil && pages.isEmpty ? pdfPageCount : pages.count
    }

    /// The outcome of the last EPUB export, if any.
    public private(set) var exportResult: ExportResult?

    /// The document being worked on, with the user's corrections, once a
    /// conversion has finished or a project was opened; `nil` before that.
    public private(set) var project: ProjectModel?
    /// Why the project could not be written beside the folder; the document is
    /// still there, but its corrections are kept in memory only.
    public private(set) var projectError: String?
    /// The project already saved for the open folder or PDF. While it is set,
    /// ``start()`` does nothing: it is opened or replaced (``startOver()``).
    public private(set) var existingProject: URL?
    /// Why the project replaced by ``startOver()`` could not be moved to the
    /// Trash; the new project was made under a name of its own.
    public private(set) var startOverError: String?

    /// The title written into the EPUB metadata.
    public var title = ""
    /// The author written into the EPUB metadata.
    public var author = ""
    /// BCP 47 tag of the document's main language.
    public var language = "uk"

    /// Whether the running or next conversion replaces ``existingProject``.
    var replacesExistingProject = false

    /// The running conversion. Exposed to tests so they can wait for it.
    private(set) var conversionTask: Task<Void, Never>?

    private let pipeline: any ConversionPipeline
    let storage: any ProjectPersisting
    private var pages: [URL] = []
    /// The PDF being converted; its pages are drawn into ``pages`` when the
    /// conversion starts, and those files belong to the project afterwards.
    private var pdf: URL?
    private var pdfPageCount = 0
    /// Where the pages of the PDF were drawn, and pages of scans prepared,
    /// until a project takes them over.
    private var stagingFolder: URL?
    /// Identifies the current run, so that progress and results arriving
    /// from a cancelled run are dropped.
    private var run = 0

    /// Creates a model that converts with `pipeline` and saves projects through `storage`.
    public init(
        pipeline: any ConversionPipeline = LivePipeline(),
        storage: any ProjectPersisting = LiveProjectStorage()
    ) {
        self.pipeline = pipeline
        self.storage = storage
    }

    /// The page the pipeline is working on while converting; `nil` in other
    /// phases and once every page is recognized and the document is assembled.
    ///
    /// Derived from the count of pages done rather than reported by the
    /// pipeline: pages are recognized one after another, so the next page
    /// starts as soon as the previous one is reported done.
    public var pageInProgress: PageInProgress? {
        guard case let .converting(done, _) = phase, pages.indices.contains(done) else { return nil }
        return PageInProgress(number: done + 1, url: pages[done])
    }

    /// Whether ``start()`` would do anything. An open project is never
    /// converted again under its corrections (ADR 0011).
    public var canStart: Bool {
        canConvert && (existingProject == nil || replacesExistingProject)
    }

    /// Whether a conversion could start now, leaving ``existingProject`` aside.
    var canConvert: Bool {
        guard project == nil, pageCount > 0, !trimmed(title).isEmpty else { return false }
        switch phase {
        case .converting, .rendering: return false
        default: return true
        }
    }

    /// Where to offer saving the EPUB: next to the input, under its name.
    public var suggestedExportURL: URL? {
        input.map { $0.deletingLastPathComponent().appendingPathComponent(Self.documentName(for: $0) + ".epub") }
    }

    /// Opens `url`, which is a project folder saved earlier, a PDF or a
    /// folder of page images, whichever it turns out to be.
    public func open(_ url: URL) {
        if storage.isProject(at: url) {
            openProject(at: url)
        } else if PDFImporter.isPDF(url), !Self.isDirectory(url) {
            open(pdf: url)
        } else {
            open(folder: url)
        }
    }

    /// Opens the PDF at `url` as the document to convert, replacing whatever was
    /// open. The title is preset to the file's name without its extension.
    /// A PDF that cannot be read or is locked moves the model to
    /// ``Phase/failed(_:)`` with nothing open.
    public func open(pdf url: URL) {
        reset()
        do {
            pdfPageCount = try pipeline.pdfPageCount(of: url)
            pdf = url
            input = url
            title = Self.documentName(for: url)
            existingProject = projectBeside(url)
            phase = .ready
        } catch {
            phase = .failed(Self.failure(for: error))
        }
    }

    /// Opens a project saved earlier: its document and corrections come from
    /// disk, nothing is converted. Scans the project does not hold are
    /// expected where they were.
    public func openProject(at url: URL) {
        reset()
        do {
            let loaded = try storage.load(from: url)
            let conversion = loaded.conversion
            let metadata = conversion.document.metadata
            pages = conversion.pageURLs
            // A project that holds its own pages came from a PDF or from
            // prepared scans; the document is then named after the project,
            // otherwise after the scans' folder.
            let holdsPages = conversion.pageURLs.first.map {
                $0.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                    == url.lastPathComponent
            } ?? false
            input = holdsPages ? url : conversion.pageURLs.first?.deletingLastPathComponent()
            title = metadata.title
            author = metadata.author ?? ""
            language = metadata.language
            project = ProjectModel(
                base: conversion, corrections: loaded.corrections, ignoredWords: loaded.ignoredWords,
                location: url, storage: storage
            )
            phase = .finished(conversion)
        } catch {
            pages = []
            input = nil
            project = nil
            phase = .failed(Self.failure(for: error))
        }
    }

    /// Opens `folder` as the document to convert, replacing whatever was open.
    ///
    /// The title is preset to the folder's name. A folder that cannot be
    /// used moves the model to ``Phase/failed(_:)`` with nothing open.
    public func open(folder: URL) {
        reset()
        do {
            pages = try pipeline.pageURLs(in: folder)
            input = folder
            title = folder.lastPathComponent
            existingProject = projectBeside(folder)
            phase = .ready
        } catch {
            phase = .failed(Self.failure(for: error))
        }
    }

    /// Forgets the open document and everything tied to it, before another is
    /// opened. A rendering left from a PDF is deleted.
    private func reset() {
        cancelRun()
        discardStaging()
        exportResult = nil
        project = nil
        projectError = nil
        existingProject = nil
        startOverError = nil
        replacesExistingProject = false
        pages = []
        pdf = nil
        pdfPageCount = 0
        input = nil
    }

    /// Starts converting the open folder. Does nothing when ``canStart`` is
    /// false.
    public func start() {
        guard canStart else { return }
        cancelRun()
        exportResult = nil
        let run = run
        let author = trimmed(author)
        let metadata = DocumentMetadata(
            title: trimmed(title), author: author.isEmpty ? nil : author, language: language
        )
        let renderFirst = pages.isEmpty ? pdf : nil
        phase = renderFirst == nil
            ? .converting(done: 0, total: pages.count)
            : .rendering(done: 0, total: pdfPageCount)
        let progress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in self?.report(done: done, total: total, run: run) }
        }
        conversionTask = Task { [pipeline] in
            let outcome: Phase
            do {
                if let renderFirst {
                    try await render(renderFirst, run: run)
                }
                let preparedFolder = try makePreparedFolder()
                outcome = try await .finished(
                    pipeline.convert(
                        pageURLs: pages, metadata: metadata, preparingPagesIn: preparedFolder, progress: progress
                    )
                )
            } catch {
                outcome = .failed(Self.failure(for: error))
            }
            guard run == self.run else { return }
            if case let .finished(conversion) = outcome {
                phase = .finished(adopt(conversion))
            } else {
                // A PDF that failed is drawn again on the next try.
                if pdf != nil {
                    pages = []
                }
                discardStaging()
                phase = outcome
            }
        }
    }

    /// Draws the pages of `pdf` into a folder of their own, which stays until
    /// a project takes the files over.
    private func render(_ pdf: URL, run: Int) async throws {
        let folder = try makeStagingFolder()
        let drawn = try await pipeline.renderPages(of: pdf, into: folder) { [weak self] done, total in
            Task { @MainActor in self?.report(rendered: done, total: total, run: run) }
        }
        guard run == self.run else { throw CancellationError() }
        pages = drawn
        phase = .converting(done: 0, total: drawn.count)
    }

    /// Stops the running conversion and returns to ``Phase/ready``.
    ///
    /// The state changes at once, although the pipeline only notices the
    /// cancellation after the page it is working on.
    public func cancel() {
        switch phase {
        case .converting, .rendering: break
        default: return
        }
        cancelRun()
        replacesExistingProject = false
        // A PDF that was only partly drawn is drawn again next time.
        if pdf != nil, stagingFolder != nil {
            pages = []
        }
        discardStaging()
        phase = .ready
    }

    /// Writes the converted document, with the user's corrections applied, to
    /// `url`; the outcome lands in ``exportResult``. Does nothing unless a
    /// conversion has finished.
    public func export(to url: URL) async {
        guard case let .finished(conversion) = phase else { return }
        do {
            try await pipeline.export(project?.conversion.document ?? conversion.document, to: url)
            exportResult = .saved(url)
        } catch {
            exportResult = .failed(String(describing: error))
        }
    }

    /// Puts a conversion that just finished into a new project written beside
    /// the folder of scans or the PDF, after moving the project it replaces
    /// to the Trash. Returns the conversion as it is now stored: pages drawn
    /// from a PDF are moved into the project.
    private func adopt(_ conversion: Conversion) -> Conversion {
        if replacesExistingProject, let existingProject {
            do {
                try storage.discardProject(at: existingProject)
            } catch {
                startOverError = String(describing: error)
            }
        }
        replacesExistingProject = false
        existingProject = nil
        var stored = conversion
        var location: URL?
        // Pages drawn from a PDF or prepared from scans exist only in the
        // staging folder and move into the project; scans read as they are
        // stay where the user keeps them.
        let movingPages = stagingFolder.map { staging in
            let prefix = staging.standardizedFileURL.path + "/"
            return conversion.pageURLs.allSatisfy { $0.standardizedFileURL.path.hasPrefix(prefix) }
        } ?? false
        if let input {
            do {
                let created = try storage.createProject(
                    for: conversion, named: Self.documentName(for: input),
                    in: input.deletingLastPathComponent(), movingPages: movingPages
                )
                location = created.location
                stored = created.conversion
                projectError = nil
                if movingPages {
                    pages = stored.pageURLs
                }
                discardStaging()
            } catch {
                projectError = String(describing: error)
            }
        }
        project = ProjectModel(base: stored, location: location, storage: storage)
        return stored
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

    /// Progress of drawing the pages of a PDF, with the same rules as
    /// ``report(done:total:run:)``.
    private func report(rendered done: Int, total: Int, run: Int) {
        guard run == self.run, case let .rendering(current, _) = phase, done > current else { return }
        phase = .rendering(done: done, total: total)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Staging

private extension ConversionModel {
    /// The temporary folder for files that become the project's, made once
    /// per conversion.
    func makeStagingFolder() throws -> URL {
        if let stagingFolder {
            return stagingFolder
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFToEPUB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        stagingFolder = folder
        return folder
    }

    /// Where scanned pages are prepared: inside the staging folder,
    /// apart from pages drawn from a PDF, which have the same names.
    func makePreparedFolder() throws -> URL {
        let folder = try makeStagingFolder().appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func discardStaging() {
        guard let stagingFolder else { return }
        try? FileManager.default.removeItem(at: stagingFolder)
        self.stagingFolder = nil
    }
}
