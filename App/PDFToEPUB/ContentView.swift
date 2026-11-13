import AppModel
import SwiftUI
import UniformTypeIdentifiers

/// The main window: one screen per phase of ``ConversionModel``.
struct ContentView: View {
    @Bindable var model: ConversionModel
    @State private var isChoosingFolder = false

    var body: some View {
        Group {
            switch model.phase {
            case .empty:
                emptyView
            case .ready:
                MetadataForm(model: model, chooseFolder: chooseFolder)
            case let .converting(done, total):
                ProgressScreen(done: done, total: total, cancel: model.cancel)
            case let .finished(conversion):
                ResultScreen(model: model, summary: ConversionSummary(conversion), chooseFolder: chooseFolder)
            case let .failed(failure):
                failureView(failure)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                model.open(folder: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !isConverting else { return false }
            model.open(folder: url)
            return true
        }
    }

    private var isConverting: Bool {
        if case .converting = model.phase {
            true
        } else {
            false
        }
    }

    private func chooseFolder() {
        isChoosingFolder = true
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No document open", systemImage: "document.closed")
        } description: {
            Text("Choose a folder with one image per page, or drop it here.")
        } actions: {
            Button("Choose Folder…", action: chooseFolder)
                .keyboardShortcut("o")
        }
    }

    private func failureView(_ failure: ConversionModel.Failure) -> some View {
        ContentUnavailableView {
            Label("Could not convert the document", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message(for: failure))
        } actions: {
            if model.folder != nil {
                Button("Try Again", action: model.start)
            }
            Button("Choose Folder…", action: chooseFolder)
        }
    }

    private func message(for failure: ConversionModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .notAFolder: "This is not a folder."
        case .noImages: "The folder has no page images (PNG, JPEG, TIFF or HEIC)."
        case .recognitionTimedOut: "Text recognition stopped responding. Try again."
        case let .other(description): "Unexpected error: \(description)"
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
                LabeledContent("Folder") {
                    HStack {
                        Text(model.folder?.path(percentEncoded: false) ?? "")
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
            Section {
                HStack {
                    Spacer()
                    Button("Convert", action: model.start)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canStart)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Page counter shown while the pipeline runs.
private struct ProgressScreen: View {
    var done: Int
    var total: Int
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Recognizing pages…")
            } currentValueLabel: {
                Text("\(done) of \(total)")
            }
            if done == 0 {
                Text("The first page can take about a minute while the recognition model loads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: 420)
    }
}

/// What the conversion produced, and saving it as an EPUB.
private struct ResultScreen: View {
    var model: ConversionModel
    var summary: ConversionSummary
    var chooseFolder: () -> Void

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
            if summary.unlinkedReferences > 0 || summary.unlinkedNotes > 0 {
                Section("Needs attention") {
                    LabeledContent("References without a note", value: summary.unlinkedReferences.formatted())
                    LabeledContent("Notes without a reference", value: summary.unlinkedNotes.formatted())
                }
            }
            Section {
                exportStatus
                HStack {
                    Button("Choose Another Folder…", action: chooseFolder)
                    Spacer()
                    Button("Save EPUB…", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var exportStatus: some View {
        switch model.exportResult {
        case let .saved(url):
            HStack {
                Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
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
