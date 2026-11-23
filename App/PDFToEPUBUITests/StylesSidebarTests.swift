import XCTest

/// The styles sidebar of the review: shown and hidden, a style's examples in
/// place of the block list, an example back to its block, and a block back
/// to its style. Which styles Vision's lines make is not fixed, so the test
/// works with the first style and the first example.
final class StylesSidebarTests: XCTestCase {
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
    func testStyleExamplesLeadToBlocksAndBack() throws {
        let app = try launchReview()
        XCTAssertTrue(element("blockCard", in: app).waitForExistence(timeout: 30), "the review shows no blocks")
        let sidebar = element("styleSidebar", in: app)
        XCTAssertFalse(sidebar.exists, "the sidebar is shown before it was asked for")

        let toggle = element("stylesToggle", in: app)
        XCTAssertTrue(toggle.isEnabled, "Styles is disabled for a new conversion")
        toggle.click()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Styles showed no sidebar")

        let row = element("styleRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar lists no style")
        row.click()
        let example = element("styleExample", in: app)
        XCTAssertTrue(example.waitForExistence(timeout: 10), "a selected style shows no examples")
        XCTAssertFalse(element("issueCounter", in: app).exists, "issue controls stay while a style is shown")
        XCTAssertTrue(app.buttons["Undo"].exists, "undo is hidden while a style is shown")

        example.click()
        XCTAssertTrue(waitForDisappearance(example), "opening an example kept the style's blocks")
        let styleButton = element("blockStyleButton", in: app)
        XCTAssertTrue(styleButton.waitForExistence(timeout: 10), "the example's block is not selected")

        styleButton.click()
        XCTAssertTrue(example.waitForExistence(timeout: 10), "the block's style button did not show its style")

        toggle.click()
        XCTAssertTrue(waitForDisappearance(sidebar), "Styles did not hide the sidebar")
        XCTAssertTrue(element("blockCard", in: app).waitForExistence(timeout: 10), "the block list did not come back")
    }

    // MARK: Helpers

    @MainActor
    private func launchReview() throws -> XCUIApplication {
        let folder = try PageFolder.make(in: workDirectory)
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFolder", folder.path]
        app.launch()
        let convert = app.buttons["convertButton"]
        XCTAssertTrue(convert.waitForExistence(timeout: 30), "the folder was not opened")
        convert.click()
        let review = app.buttons["reviewButton"]
        XCTAssertTrue(review.waitForExistence(timeout: 420), "the conversion did not finish")
        review.click()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
