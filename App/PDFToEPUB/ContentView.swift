import AppModel
import Corrections
import ImageIO
import SwiftUI
import TextReview
import UniformTypeIdentifiers

/// The main window: one screen per phase of ``ConversionModel``.
struct ContentView: View {
    @Bindable var model: ConversionModel
    /// Launch arguments of a UI test; ``UITestHooks/none`` otherwise.
    var hooks = UITestHooks.none
    @State private var isChoosingFolder = false
    /// The review of the finished conversion, while its screen is open.
    @State private var review: ReviewModel?
    /// Suspicious words in the corrected document, counted off the main thread;
    /// `nil` until counted.
    @State private var counted: ConversionSummary?
    /// One detector for the summary and the review, so their counts agree.
    private let detector = SuspiciousWordDetector(spellChecker: SystemSpellChecker())

    var body: some View {
        Group {
            switch model.phase {
            case .empty:
                emptyView
            case .ready:
                MetadataForm(model: model, chooseFolder: chooseFolder)
            case let .rendering(done, total):
                ProgressScreen(done: done, total: total, page: nil, isDrawing: true, cancel: model.cancel)
            case let .converting(done, total):
                ProgressScreen(done: done, total: total, page: model.pageInProgress, cancel: model.cancel)
            case let .finished(conversion):
                if let review {
                    ReviewScreen(model: review) { self.review = nil }
                } else {
                    // The summary counts the document as it will be exported, with
                    // the corrections applied.
                    let corrected = model.project?.conversion ?? conversion
                    ResultScreen(
                        model: model, hooks: hooks, summary: ConversionSummary(corrected), counted: counted,
                        chooseFolder: chooseFolder
                    ) { start in
                        let opened = model.project.map { ReviewModel(project: $0, detector: detector) }
                            ?? ReviewModel(conversion: conversion, detector: detector)
                        switch start {
                        case .top:
                            break
                        case .issue:
                            opened.goToNextIssue()
                        case .misspelledWord:
                            opened.showsSpelling = true
                            opened.goToNextMisspelling()
                        }
                        review = opened
                    }
                    .task(id: model.project?.corrections.corrections.count) {
                        counted = nil
                        let detector = detector
                        counted = await Task.detached {
                            ConversionSummary(corrected, detector: detector)
                        }.value
                    }
                }
            case let .failed(failure):
                FailureScreen(
                    failure: failure, canRetry: model.input != nil, retry: model.start, chooseFolder: chooseFolder
                )
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .task {
            if let folder = hooks.folder {
                model.open(folder)
            }
        }
        // A review belongs to one conversion; any change of phase ends it.
        .onChange(of: model.phase) { review = nil }
        // A folder of scans and a saved project are both folders; the model
        // tells them apart from each other and from a PDF.
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder, .pdf]) { result in
            if case let .success(url) = result {
                model.open(url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !isConverting else { return false }
            model.open(url)
            return true
        }
    }

    private var isConverting: Bool {
        switch model.phase {
        case .converting, .rendering: true
        default: false
        }
    }

    private func chooseFolder() {
        isChoosingFolder = true
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No document open", systemImage: "document.closed")
        } description: {
            Text("Choose a folder with one image per page, a PDF or a saved project, or drop it here.")
        } actions: {
            Button("Choose Folder or PDF…", action: chooseFolder)
                .keyboardShortcut("o")
        }
    }
}

/// Document metadata and the button that starts the conversion.
private struct MetadataForm: View {
    @Bindable var model: ConversionModel
    var chooseFolder: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Source") {
                    HStack {
                        Text(model.input?.path(percentEncoded: false) ?? "")
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button("Change…", action: chooseFolder)
                    }
                }
                LabeledContent("Pages", value: model.pageCount.formatted())
            }
            Section {
                TextField("Title", text: $model.title)
                TextField("Author", text: $model.author)
                Picker("Language", selection: $model.language) {
                    Text("Ukrainian").tag("uk")
                    Text("English").tag("en")
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Convert", action: model.start)
                    .accessibilityIdentifier("convertButton")
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

/// Page counter and the scan of the page being recognized, shown while the
/// pipeline runs. Only the scan is shown, never recognized text: nothing
/// here can be edited.
private struct ProgressScreen: View {
    var done: Int
    var total: Int
    var page: ConversionModel.PageInProgress?
    /// Whether the pages of a PDF are being drawn rather than recognized.
    var isDrawing = false
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            PagePreview(url: page?.url)
                .frame(maxHeight: .infinity)
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                // Once every page is recognized, layout analysis runs with
                // no page in progress.
                if isDrawing {
                    Text("Drawing the pages…")
                } else if page == nil {
                    Text("Assembling the document…")
                } else {
                    Text("Recognizing pages…")
                }
            } currentValueLabel: {
                Text("\(done) of \(total)")
            }
            .frame(maxWidth: 420)
            if done == 0, !isDrawing {
                Text("The first page can take about a minute while the recognition model loads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// A page scan scaled down to fit, loaded off the main actor.
///
/// The previous scan stays on screen until the next one is ready, so the
/// preview does not flash empty between pages. A page that is replaced
/// before it loads is skipped.
private struct PagePreview: View {
    var url: URL?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
                    .shadow(radius: 3)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url, let loaded = await Self.thumbnail(of: url), !Task.isCancelled else { return }
            image = loaded
        }
    }

    /// Big enough for a window filling a large display, small enough to
    /// decode quickly.
    @concurrent
    private static func thumbnail(of url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Where the review opens: at the first page, or at the first block with a
/// problem the summary counts.
enum ReviewStart {
    case top, issue, misspelledWord
}

/// What the conversion produced, and saving it as an EPUB.
private struct ResultScreen: View {
    var model: ConversionModel
    var hooks: UITestHooks
    var summary: ConversionSummary
    /// The summary with suspicious and misspelled words counted; `nil` until counted.
    var counted: ConversionSummary?
    var chooseFolder: () -> Void
    var review: (ReviewStart) -> Void

    var body: some View {
        Form {
            Section("Converted document") {
                LabeledContent("Chapters", value: summary.chapters.formatted())
                LabeledContent("Headings", value: summary.headings.formatted())
                LabeledContent("Paragraphs", value: summary.paragraphs.formatted())
                LabeledContent("Illustrations", value: summary.figures.formatted())
                LabeledContent("Notes", value: summary.notes.formatted())
                LabeledContent("Cover") {
                    Text(summary.hasCover ? "Yes" : "No")
                }
            }
            AttentionSection(summary: summary, counted: counted, review: review)
            if let counted, counted.misspelledWords > 0 {
                // Apart from "Needs attention": spelling is noisy and comes second.
                Section("For a second pass") {
                    LabeledContent("Words the dictionary does not know") {
                        Button(counted.misspelledWords.formatted()) { review(.misspelledWord) }
                            .buttonStyle(.link)
                            .help("Opens the review at the first one.")
                    }
                }
            }
            projectSection
        }
        .formStyle(.grouped)
        // Kept outside the scrolling form so saving is always in reach.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                exportStatus
                HStack {
                    Button("Choose Another Folder or PDF…", action: chooseFolder)
                    Spacer()
                    Button("Convert Again", action: model.start)
                        .disabled(!model.canStart)
                    Button("Review…") { review(.top) }
                        .accessibilityIdentifier("reviewButton")
                        .keyboardShortcut("r")
                    Button("Save EPUB…", action: save)
                        .accessibilityIdentifier("saveButton")
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    /// Where the project is saved, what its corrections amount to, and what
    /// could not be kept.
    @ViewBuilder private var projectSection: some View {
        if let project = model.project {
            Section("Project") {
                if let location = project.location {
                    LabeledContent("Saved as") {
                        HStack {
                            Text(location.lastPathComponent)
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([location])
                            }
                        }
                    }
                } else {
                    Label(
                        "The project could not be saved. Corrections are kept until you close the document.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    if let error = model.projectError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Corrections", value: project.corrections.corrections.count.formatted())
                if !project.unapplied.isEmpty {
                    LabeledContent("Corrections that no longer apply", value: project.unapplied.count.formatted())
                }
                if let error = project.saveError {
                    Label("Corrections could not be saved: \(error)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder private var exportStatus: some View {
        switch model.exportResult {
        case let .saved(url):
            HStack {
                Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("exportSaved")
                    .foregroundStyle(.green)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        case let .failed(description):
            Label("Could not save the EPUB: \(description)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    /// Uses `NSSavePanel` directly: `fileExporter` wants the whole document
    /// in memory as a `FileDocument`, while the exporter writes to a URL.
    private func save() {
        if let output = hooks.output {
            Task { await model.export(to: output) }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.epub]
        panel.canCreateDirectories = true
        if let suggestion = model.suggestedExportURL {
            panel.directoryURL = suggestion.deletingLastPathComponent()
            panel.nameFieldStringValue = suggestion.lastPathComponent
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.export(to: url) }
    }
}

#Preview {
    ContentView(model: ConversionModel())
}
