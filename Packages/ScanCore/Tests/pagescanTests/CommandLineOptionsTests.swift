@testable import pagescan
import Foundation
import Testing

@Suite("CommandLineOptions")
struct CommandLineOptionsTests {
    @Test("reads the input folder and every option")
    func full() throws {
        let options = try CommandLineOptions(arguments: [
            "/in/document", "--output", "/out/b.epub", "--title", "My Document", "--author", "A. B.", "--language", "en",
        ])
        #expect(options.input.path == "/in/document")
        #expect(options.output.path == "/out/b.epub")
        #expect(options.title == "My Document")
        #expect(options.author == "A. B.")
        #expect(options.language == "en")
    }

    @Test("defaults the title to the folder name, the output next to the folder, and the language to Ukrainian")
    func defaults() throws {
        let options = try CommandLineOptions(arguments: ["/in/my_document/"])
        #expect(options.title == "my_document")
        #expect(options.output.path == "/in/my_document.epub")
        #expect(options.author == nil)
        #expect(options.language == "uk")
    }

    @Test("rejects a missing input, an unknown option and an option without a value")
    func errors() {
        #expect(throws: CommandLineError.missingInput) { try CommandLineOptions(arguments: []) }
        #expect(throws: CommandLineError.unknownOption("--bogus")) { try CommandLineOptions(arguments: [
            "/in",
            "--bogus",
            "x",
        ]) }
        #expect(throws: CommandLineError.missingValue("--title")) {
            try CommandLineOptions(arguments: ["/in", "--title"])
        }
        #expect(throws: CommandLineError.unexpectedArgument("/second")) { try CommandLineOptions(arguments: [
            "/in",
            "/second",
        ]) }
    }

    @Test("a PDF input is named without its extension, for the title and the output")
    func pdfInput() throws {
        let options = try CommandLineOptions(arguments: ["/in/Sample.pdf"])
        #expect(options.inputIsPDF)
        #expect(options.title == "Sample")
        #expect(options.output.path == "/in/Sample.epub")
    }

    @Test("a folder is not taken for a PDF")
    func folderIsNotPDF() throws {
        #expect(try !CommandLineOptions(arguments: ["/in/Sample"]).inputIsPDF)
    }
}
