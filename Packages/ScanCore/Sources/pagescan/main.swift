// pagescan: converts a folder of page images or a PDF into an EPUB from the command
// line. A thin wrapper over ScanCore, used for batch runs and for checking
// the pipeline without the app.

import Conversion
import DocumentModel
import EPUBExport
import Foundation
import Importing
import OCR
import Preprocessing

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let options: CommandLineOptions
do {
    options = try CommandLineOptions(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("pagescan: \(error)\n\n\(CommandLineOptions.usage)")
}

do {
    let pages: [URL]
    var renderedFolder: URL?
    if options.inputIsPDF {
        // The pages are drawn into a temporary folder that goes away with the
        // run; pagescan keeps nothing but the EPUB.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pagescan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        renderedFolder = folder
        print("Drawing the pages of \(options.input.lastPathComponent)...")
        pages = try await PDFImporter().renderPages(of: options.input, into: folder) { done, total in
            if done % 25 == 0 || done == total {
                print("  \(done)/\(total)")
            }
        }
    } else {
        pages = try ImageFolderImporter().pageURLs(in: options.input)
    }
    defer { renderedFolder.map { try? FileManager.default.removeItem(at: $0) } }
    // Pages of a paper scan are prepared (cropped, cleaned, deskewed) into
    // a folder of their own; clean pages are read as they are.
    let preparedFolder = options.preparedPages ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("pagescan-prepared-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: preparedFolder, withIntermediateDirectories: true)
    defer {
        if options.preparedPages == nil {
            try? FileManager.default.removeItem(at: preparedFolder)
        }
    }
    print("Recognizing \(pages.count) pages (the first one can take a minute while the model loads)...")
    let engine = VisionOCREngine(languages: options.language.hasPrefix("en") ? ["en-US"] : [options.language, "en-US"])
    let metadata = DocumentMetadata(title: options.title, author: options.author, language: options.language)
    let conversion = try await DocumentConverter(engine: engine, preparer: ScanPagePreparer(folder: preparedFolder))
        .analyze(pageURLs: pages, metadata: metadata) { done, total in
            if done % 25 == 0 || done == total {
                print("  \(done)/\(total)")
            }
        }
    let document = conversion.document
    let prepared = zip(pages, conversion.pageURLs).count { $0 != $1 }
    print("  pages prepared as a paper scan: \(prepared) of \(pages.count)")
    try EPUBExporter().export(document, to: options.output)

    var headings = 0, paragraphs = 0, figures = 0
    for block in document.blocks {
        switch block {
        case .heading: headings += 1
        case .paragraph: paragraphs += 1
        case .figure: figures += 1
        }
    }
    print("Wrote \(options.output.path)")
    print("  chapters: \(document.chapters.count), headings: \(headings), paragraphs: \(paragraphs), "
        + "figures: \(figures), cover: \(document.coverImageID == nil ? "no" : "yes")")
    print("  notes: \(document.notes.count), references without a note: \(conversion.unlinkedReferences), "
        + "notes without a reference: \(conversion.unlinkedNotes)")
} catch {
    fail("pagescan: \(error)")
}
