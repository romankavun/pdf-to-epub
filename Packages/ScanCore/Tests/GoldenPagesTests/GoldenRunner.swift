import Conversion
import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Importing
import OCR
import Testing
import TestSupport

extension Tag {
    /// Golden-page tests run real Vision OCR and take minutes on the first
    /// run; filter with `--filter` or `--skip` on the suite name.
    @Tag static var golden: Self
}

/// A synthetic document and the name of its expectation file.
struct GoldenCase: Sendable {
    var name: String
    /// Backlog item that makes this case fail today; the comparison is then
    /// wrapped in `withKnownIssue` so the suite stays green until it is fixed.
    var knownIssue: String?
    var pages: [SyntheticPage]
    /// Draw the pages into one PDF and convert that through ``PDFImporter``
    /// instead of converting the page images directly.
    var viaPDF = false
}

/// Draws each page image as one page of a PDF, as a scanner would.
private func writePDF(from images: [URL], to url: URL) throws {
    var box = CGRect(origin: .zero, size: SyntheticPage.size)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
    for imageURL in images {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
    }
    context.closePDF()
}

/// Renders the pages, converts them with the real pipeline and compares the
/// result with `Tests/Fixtures/golden/<name>.json`, or rewrites that file
/// when `GOLDEN_RECORD=1`.
func runGolden(_ golden: GoldenCase) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var urls = try golden.pages.enumerated().map { index, page in
        let url = folder.appendingPathComponent(String(format: "page_%03d.png", index + 1))
        try page.writePNG(to: url)
        return url
    }
    if golden.viaPDF {
        let pdf = folder.appendingPathComponent("document.pdf")
        try writePDF(from: urls, to: pdf)
        let rendered = folder.appendingPathComponent("rendered", isDirectory: true)
        try FileManager.default.createDirectory(at: rendered, withIntermediateDirectories: true)
        urls = try await PDFImporter().renderPages(of: pdf, into: rendered)
    }
    let metadata = DocumentMetadata(
        identifier: "urn:uuid:\(UUID().uuidString)",
        title: golden.name,
        author: nil,
        language: "en"
    )
    let conversion = try await DocumentConverter(engine: VisionOCREngine()).analyze(pageURLs: urls, metadata: metadata)
    let actual = DocumentSnapshot(
        document: conversion.document, unlinkedReferences: conversion.unlinkedReferences,
        unlinkedNotes: conversion.unlinkedNotes
    )

    if GoldenStore.isRecording {
        try GoldenStore.save(actual, as: golden.name)
        return
    }
    let expected = try GoldenStore.load(golden.name)
    let differences = actual.differences(from: expected)
    if let issue = golden.knownIssue {
        withKnownIssue("Known defect: \(issue)") {
            #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
        }
    } else {
        #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
    }
}
