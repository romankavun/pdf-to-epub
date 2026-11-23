import XCTest

/// Opening a folder that was converted before offers its project or starting
/// over (ADR 0011), and never converts again under the corrections.
final class StartOverTests: XCTestCase {
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
    func testConvertedFolderOffersItsProjectOrStartOver() throws {
        let folder = try PageFolder.make(in: workDirectory)
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFolder", folder.path]

        // First launch: convert, which writes the project beside the folder.
        app.launch()
        let convert = app.buttons["convertButton"]
        XCTAssertTrue(convert.waitForExistence(timeout: 30), "the folder was not opened")
        convert.click()
        XCTAssertTrue(app.buttons["reviewButton"].waitForExistence(timeout: 420), "the conversion did not finish")
        XCTAssertFalse(app.buttons["Convert Again"].exists, "the summary still offers Convert Again")
        app.terminate()

        // Second launch on the same folder: the project is offered instead of Convert.
        app.launch()
        let openProject = app.buttons["openExistingProjectButton"]
        XCTAssertTrue(openProject.waitForExistence(timeout: 30), "the existing project is not offered")
        XCTAssertFalse(app.buttons["convertButton"].exists, "Convert is offered over an existing project")

        // Start over asks first; cancelling leaves everything as it was.
        app.buttons["startOverButton"].click()
        let confirm = app.buttons["Start Over"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Start over did not ask for confirmation")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(openProject.waitForExistence(timeout: 10))

        // Opening the project goes straight to its summary.
        openProject.click()
        XCTAssertTrue(app.buttons["reviewButton"].waitForExistence(timeout: 30), "the project did not open")
    }
}
