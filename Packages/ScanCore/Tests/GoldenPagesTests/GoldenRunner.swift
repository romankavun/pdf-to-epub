import Conversion
import DocumentModel
import Foundation
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
}

/// Renders the pages, converts them with the real pipeline and compares the
/// result with `Tests/Fixtures/golden/<name>.json`, or rewrites that file
/// when `GOLDEN_RECORD=1`.
func runGolden(_ golden: GoldenCase) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let urls = try golden.pages.enumerated().map { index, page in
        let url = folder.appendingPathComponent(String(format: "page_%03d.png", index + 1))
        try page.writePNG(to: url)
        return url
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
