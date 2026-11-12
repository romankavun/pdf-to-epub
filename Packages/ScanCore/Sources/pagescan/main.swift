// pagescan: converts a folder of page images into an EPUB from the command
// line. A thin wrapper over ScanCore, used for batch runs and for checking
// the pipeline without the app.

import Conversion
import DocumentModel
import EPUBExport
import Foundation
import Importing
import OCR

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
    let pages = try ImageFolderImporter().pageURLs(in: options.input)
    print("Recognizing \(pages.count) pages (the first one can take a minute while the model loads)...")
    let engine = VisionOCREngine(languages: options.language.hasPrefix("en") ? ["en-US"] : [options.language, "en-US"])
    let metadata = DocumentMetadata(title: options.title, author: options.author, language: options.language)
    let document = try await DocumentConverter(engine: engine).convert(pageURLs: pages, metadata: metadata) { done, total in
        if done % 25 == 0 || done == total {
            print("  \(done)/\(total)")
        }
    }
    try EPUBExporter().export(document, to: options.output)

    let headings = document.blocks.count {
        if case .heading = $0 {
            true
        } else {
            false
        }
    }
    print("Wrote \(options.output.path)")
    print("  chapters: \(document.chapters.count), headings: \(headings), paragraphs: \(document.blocks.count - headings)")
} catch {
    fail("pagescan: \(error)")
}
