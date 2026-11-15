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
/// Parsed by hand: the tool has four options, which does not justify a
/// dependency on an argument-parsing package.
struct CommandLineOptions: Equatable {
    static let usage = """
    Usage: pagescan <folder-with-page-images | file.pdf> [--output <file.epub>]
                    [--title <title>] [--author <author>] [--language <bcp47-tag>]

    Defaults: output is <name>.epub next to the input, title is the name of the
    folder or of the PDF without its extension, language is uk.
    """

    var input: URL
    var output: URL
    var title: String
    var author: String?
    var language: String

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
            if argument.hasPrefix("--") {
                guard ["--output", "--title", "--author", "--language"].contains(argument) else {
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
    }
}
