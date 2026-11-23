import Foundation
import Importing

/// A problem with the arguments given to `pagescan`.
enum CommandLineError: Error, Equatable {
    case missingInput
    case unknownOption(String)
    case missingValue(String)
    case unexpectedArgument(String)
}

/// Parsed `pagescan` arguments.
///
/// Parsed by hand: the tool has five options, which does not justify a
/// dependency on an argument-parsing package.
struct CommandLineOptions: Equatable {
    static let usage = """
    Usage: pagescan <folder-with-page-images | file.pdf> [--output <file.epub>]
                    [--title <title>] [--author <author>] [--language <bcp47-tag>]
                    [--prepared-pages <folder>] [--styles]

    Defaults: output is <name>.epub next to the input, title is the name of the
    folder or of the PDF without its extension, language is uk.
    --prepared-pages keeps the page images of scanned pages as they were
    prepared for recognition (cropped, cleaned, deskewed) in <folder>;
    without it they are deleted after the run.
    --styles prints the styles recognition found: each one's type, deciding
    rule, number of blocks and pages.
    """

    var input: URL
    var output: URL
    var title: String
    var author: String?
    var language: String
    /// Where to keep pages prepared for recognition; `nil` keeps them only
    /// for the run.
    var preparedPages: URL?
    /// Whether to print the document's styles after converting it.
    var printsStyles = false

    /// Whether the input is a PDF file rather than a folder of page images.
    var inputIsPDF: Bool {
        Self.isPDF(input)
    }

    private static func isPDF(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return PDFImporter.isPDF(url) && !(exists && isDirectory.boolValue)
    }

    /// - Parameter arguments: The arguments after the program name.
    init(arguments: [String]) throws {
        var input: URL?
        var values: [String: String] = [:]
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--styles" {
                printsStyles = true
            } else if argument.hasPrefix("--") {
                guard ["--output", "--title", "--author", "--language", "--prepared-pages"].contains(argument) else {
                    throw CommandLineError.unknownOption(argument)
                }
                guard let value = remaining.popFirst() else { throw CommandLineError.missingValue(argument) }
                values[argument] = value
            } else if input == nil {
                input = URL(fileURLWithPath: argument).standardizedFileURL
            } else {
                throw CommandLineError.unexpectedArgument(argument)
            }
        }
        guard let input else { throw CommandLineError.missingInput }
        self.input = input
        let name = Self.isPDF(input) ? input.deletingPathExtension().lastPathComponent : input.lastPathComponent
        output = values["--output"].map { URL(fileURLWithPath: $0) }
            ?? input.deletingLastPathComponent().appendingPathComponent(name + ".epub")
        title = values["--title"] ?? name
        author = values["--author"]
        language = values["--language"] ?? "uk"
        preparedPages = values["--prepared-pages"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
