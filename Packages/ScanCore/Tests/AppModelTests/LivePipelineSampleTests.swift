@testable import AppModel
import Foundation
import Testing

/// The folder of sample sets, when the developer has one; see CLAUDE.md.
private let samplesDirectory = ProcessInfo.processInfo.environment["PAGESCAN_SAMPLES_DIR"]
    .map { URL(fileURLWithPath: $0) }

@MainActor
@Suite("ConversionModel with the live pipeline")
struct LivePipelineSampleTests {
    /// Drives the model the way the window does, against real pages and
    /// Vision. Only the first pages of one document are used to keep it short.
    @Test("opens, converts and exports the start of a sample set", .enabled(if: samplesDirectory != nil))
    func convertsSample() async throws {
        let files = FileManager.default
        let samples = try #require(samplesDirectory)
        let document = try #require(
            try files.contentsOfDirectory(at: samples, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter(\.hasDirectoryPath)
                .min { $0.lastPathComponent < $1.lastPathComponent }
        )
        let scratch = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = scratch.appendingPathComponent("Sample")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        for page in try LivePipeline().pageURLs(in: document).prefix(6) {
            try files.copyItem(at: page, to: folder.appendingPathComponent(page.lastPathComponent))
        }

        let model = ConversionModel()
        model.open(folder: folder)
        #expect(model.pageCount == 6)
        #expect(model.title == "Sample")

        model.start()
        await model.conversionTask?.value
        guard case let .finished(conversion) = model.phase else {
            Issue.record("conversion ended as \(model.phase)")
            return
        }
        #expect(!conversion.document.chapters.isEmpty)

        let destination = try #require(model.suggestedExportURL)
        await model.export(to: destination)
        #expect(model.exportResult == .saved(destination))
        let size = try #require(try files.attributesOfItem(atPath: destination.path)[.size] as? Int)
        #expect(size > 0)
    }
}
