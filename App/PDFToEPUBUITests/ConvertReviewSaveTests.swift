import XCTest

/// The one end-to-end scenario: open a folder of pages, convert, correct a
/// block in the review, save the EPUB, and find the correction in the file.
///
/// The system file panels are skipped through launch arguments (see
/// `UITestHooks` in the app). The first Vision request of a launch can take
/// over a minute, hence the long timeouts.
final class ConvertReviewSaveTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFToEPUBUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    @MainActor
    func testConvertReviewCorrectAndSave() throws {
        let folder = try PageFolder.make(in: workDirectory)
        let epub = workDirectory.appendingPathComponent("Saved.epub")

        let app = XCUIApplication()
        app.launchArguments = ["-UITestFolder", folder.path, "-UITestOutput", epub.path]
        app.launch()

        // Convert.
        let convert = app.buttons["convertButton"]
        XCTAssertTrue(convert.waitForExistence(timeout: 30), "the folder was not opened")
        convert.click()
        let review = app.buttons["reviewButton"]
        XCTAssertTrue(review.waitForExistence(timeout: 420), "the conversion did not finish")

        // Review: select the first block and make it a level 3 heading.
        review.click()
        let firstCard = app.descendants(matching: .any).matching(identifier: "blockCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 30), "the review shows no blocks")
        firstCard.click()
        let typeMenu = app.descendants(matching: .any).matching(identifier: "typeMenu").firstMatch
        XCTAssertTrue(typeMenu.waitForExistence(timeout: 10), "a selected block offers no type menu")
        typeMenu.click()
        let heading3 = app.descendants(matching: .any).matching(identifier: "typeHeading3").firstMatch
        XCTAssertTrue(heading3.waitForExistence(timeout: 10))
        heading3.click()
        XCTAssertTrue(app.staticTexts["Heading 3"].waitForExistence(timeout: 10), "the block did not change type")

        // Save from the summary.
        app.buttons["Back to Summary"].click()
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "exportSaved").firstMatch
            .waitForExistence(timeout: 60), "the EPUB was not saved")

        // The file exists and holds the corrected heading.
        XCTAssertTrue(FileManager.default.fileExists(atPath: epub.path))
        let package = try Self.unzippedText(of: epub)
        XCTAssertTrue(package.contains("<h3"), "the level 3 heading is not in the EPUB")
    }

    /// The text of every entry of the ZIP, concatenated, read with the
    /// system `unzip`.
    private static func unzippedText(of zip: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .isoLatin1) ?? ""
    }
}
