import XCTest

/// Short scenarios for the review screen and the failure screen. Each test
/// launches the app on its own folder and does not depend on another.
///
/// The review scenarios convert a folder of synthetic pages first (the first
/// Vision request of a launch can take over a minute). Which blocks Vision
/// finds is not fixed, so they assert on what a click does to the first block,
/// not on its text or the number of blocks.
final class ReviewScenarioTests: XCTestCase {
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

    // MARK: Failure screen

    @MainActor
    func testEmptyFolderShowsFailureScreen() throws {
        let empty = workDirectory.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFolder", empty.path]
        app.launch()

        // Whether the folder is refused on opening or on converting is the
        // model's business (unit tested); the screen must appear either way.
        let failure = element("failureScreen", in: app)
        if !failure.waitForExistence(timeout: 15) {
            let convert = app.buttons["convertButton"]
            XCTAssertTrue(convert.waitForExistence(timeout: 15), "the empty folder was neither refused nor opened")
            convert.click()
        }
        XCTAssertTrue(failure.waitForExistence(timeout: 60), "no failure screen for a folder without images")
        XCTAssertTrue(app.staticTexts["Could not convert the document"].exists)
        XCTAssertTrue(app.buttons["Choose Folder or PDF…"].exists, "the failure screen offers no way on")
    }

    // MARK: Review

    @MainActor
    func testIgnoreBlockAndUndo() throws {
        let app = try launchReview()
        select(firstCard(in: app), in: app)
        chooseType("typeIgnore", in: app)
        XCTAssertTrue(app.staticTexts["Ignored"].waitForExistence(timeout: 10), "the block was not ignored")
        XCTAssertTrue(app.buttons["Bring Back"].waitForExistence(timeout: 10), "an ignored block offers no way back")

        app.buttons["Undo"].click()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Ignored"]), "undo did not bring the block back")
    }

    /// Typing into the editor is not tested: synthesized key events did not
    /// reach the `TextEditor` in this setup (its value stayed unchanged), so
    /// saving edited text is covered by `ReviewEditingTests` instead.
    @MainActor
    func testEditorOpensAndCancels() throws {
        let app = try launchReview()
        select(firstCard(in: app), in: app)
        app.buttons["Edit Text"].click()
        let editor = element("blockEditor", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Edit Text opened no editor")
        XCTAssertTrue(app.buttons["Save Text"].exists)
        app.buttons["Cancel"].click()
        XCTAssertTrue(waitForDisappearance(editor), "the editor stayed open after Cancel")
        XCTAssertTrue(app.buttons["Edit Text"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testMergeWithNextAndUndo() throws {
        let app = try launchReview()
        let cards = app.descendants(matching: .any).matching(identifier: "blockCard")
        XCTAssertTrue(firstCard(in: app).waitForExistence(timeout: 30), "the review shows no blocks")
        let before = cards.count
        try XCTSkipIf(before < 2, "Vision found a single block on the first page: nothing to merge")
        select(cards.firstMatch, in: app)
        let merge = app.buttons["Merge with Next"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10))
        merge.click()
        XCTAssertTrue(waitFor { cards.count == before - 1 }, "merging did not leave one block fewer")
        app.buttons["Undo"].click()
        XCTAssertTrue(waitFor { cards.count == before }, "undo did not split the blocks back")
    }

    @MainActor
    func testTypeProposalCanBeDismissed() throws {
        let app = try launchReview()
        select(firstCard(in: app), in: app)
        chooseType("typeHeading3", in: app)
        // The offer appears only when similar blocks exist, which depends on
        // what Vision recognized.
        let notNow = app.buttons["Not Now"]
        try XCTSkipUnless(notNow.waitForExistence(timeout: 10), "no similar blocks, so no proposal")
        XCTAssertTrue(app.buttons["Apply to All"].exists)
        XCTAssertTrue(app.buttons["Choose…"].exists)
        notNow.click()
        XCTAssertTrue(waitForDisappearance(notNow), "the proposal stayed after Not Now")
        XCTAssertTrue(app.staticTexts["Heading 3"].exists, "dismissing the offer undid the change")
    }

    /// A page that became one picture with no caption is an issue: the
    /// counter includes it and Next Issue stops on it with the warning.
    @MainActor
    func testLostTextPageIsAnIssue() throws {
        let app = try launchReview(picturePage: true)
        let counter = element("issueCounter", in: app)
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "the review has no issue counter")
        let next = element("nextIssueButton", in: app)
        XCTAssertTrue(next.isEnabled, "Next Issue is disabled although a page lost its text")
        next.click()
        let warning = element("lostTextWarning", in: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "Next Issue did not reach the picture page's warning")
        XCTAssertTrue(
            waitFor { (counter.value as? String ?? counter.label).hasPrefix("Issue ") },
            "the counter does not show the issue's position: \(counter.label)"
        )
    }

    // MARK: Helpers

    /// Opens the review of a converted folder of synthetic pages.
    @MainActor
    private func launchReview(picturePage: Bool = false) throws -> XCUIApplication {
        let folder = try PageFolder.make(in: workDirectory, picturePage: picturePage)
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

    private func firstCard(in app: XCUIApplication) -> XCUIElement {
        element("blockCard", in: app)
    }

    @MainActor
    private func select(_ card: XCUIElement, in _: XCUIApplication) {
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the review shows no blocks")
        card.click()
    }

    @MainActor
    private func chooseType(_ itemIdentifier: String, in app: XCUIApplication) {
        let menu = element("typeMenu", in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "a selected block offers no type menu")
        menu.click()
        let item = element(itemIdentifier, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the type menu has no \(itemIdentifier)")
        item.click()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func waitFor(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}
