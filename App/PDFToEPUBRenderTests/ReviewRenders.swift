import AppKit
import AppModel
@testable import PDFToEPUB
import ProjectStore
import ScreenCaptureKit
import Styles
import SwiftUI
import XCTest

/// Draws the review screen of a saved project to PNG files, so a change to a
/// view can be looked at without the screen: no window comes forward, no
/// input is sent, and a locked screen does not stop it.
///
/// Not a regression test: it asserts nothing about the pictures. Run it with
/// `scripts/render-views.sh`, which sets the environment below
/// (`docs/testing.md`, *Looking at a view*).
///
/// - `RENDER_PROJECT`: the `.scanproject` to open; the test is skipped without it.
/// - `RENDER_OUTPUT`: the folder the PNG files go to.
/// - `RENDER_PAGE`: the page shown, counted from 1 (default 1).
/// - `RENDER_STYLE`: the style selected in the `style` picture, by its title
///   as the sidebar shows it (default: the first probably-wrong style, else
///   the first style).
final class ReviewRenders: XCTestCase {
    private static let size = CGSize(width: 1400, height: 870)

    @MainActor
    func testReviewScreen() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let projectPath = environment["RENDER_PROJECT"] else {
            throw XCTSkip("RENDER_PROJECT is not set; run scripts/render-views.sh")
        }
        let output = URL(filePath: environment["RENDER_OUTPUT"] ?? NSTemporaryDirectory() + "pdftoepub-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let project = try ProjectStore().load(from: URL(filePath: projectPath))
        // No location: nothing the pictures do is saved to the project.
        let model = ReviewModel(project: ProjectModel(
            base: project.conversion, corrections: project.corrections, ignoredWords: project.ignoredWords
        ))
        let page = Int(environment["RENDER_PAGE"] ?? "") ?? 1
        model.goToPage(max(0, min(page - 1, model.pages.count - 1)))

        try await render(model, name: "blocks", to: output)
        guard model.styles != nil else { return }
        model.showsStyles = true
        try await render(model, name: "styles", to: output)
        if let style = chosenStyle(in: model, title: environment["RENDER_STYLE"]) {
            model.selectStyle(style.id)
            try await render(model, name: "style", to: output)
        }
    }

    @MainActor
    private func chosenStyle(in model: ReviewModel, title: String?) -> Styles.Style? {
        let all = model.styleSections.flatMap(\.styles)
        if let title, !title.isEmpty {
            return all.first { $0.title == title }
        }
        return all.first { model.warning(of: $0) != nil } ?? all.first
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`.
    ///
    /// Captured through the window server, which draws the system's glass
    /// and materials that `NSView.cacheDisplay` leaves blank. The window is
    /// placed off every screen; a process may capture its own windows without
    /// the screen recording permission.
    @MainActor
    private func render(_ model: ReviewModel, name: String, to folder: URL) async throws {
        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: Self.size),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.appearance = NSAppearance(named: appearance)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ReviewScreen(model: model) {}.padding())
            window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            // Page images and example thumbnails load asynchronously.
            try await Task.sleep(for: .seconds(1.5))
            let file = folder.appendingPathComponent("\(name)-\(suffix).png")
            try await capture(window, to: file)
            print("RENDERED \(file.path)")
        }
    }

    @MainActor
    private func capture(_ window: NSWindow, to file: URL) async throws {
        let content = try await SCShareableContent.currentProcess
        let shareable = try XCTUnwrap(
            content.windows.first { $0.windowID == CGWindowID(window.windowNumber) },
            "the window is not capturable"
        )
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.width = Int(shareable.frame.width * scale)
        configuration.height = Int(shareable.frame.height * scale)
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: shareable), configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
