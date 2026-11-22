import Foundation

/// Where the developer's own sample sets live, for tests that need real pages.
///
/// The sets are commercial material, so they sit in the git-ignored `Samples/`
/// folder at the repository root (one sub-folder per document), never in a
/// tracked path. `PAGESCAN_SAMPLES_DIR` overrides the location. Tests that
/// need samples are skipped when this is `nil`.
enum SampleSets {
    /// The folder holding one sub-folder per sample set, or `nil` when there is no set to test with.
    static let directory: URL? = {
        if let path = ProcessInfo.processInfo.environment["PAGESCAN_SAMPLES_DIR"] {
            return URL(fileURLWithPath: path)
        }
        // .../Packages/ScanCore/Tests/AppModelTests/SampleSets.swift -> repository root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let samples = root.appendingPathComponent("Samples")
        let sets = try? FileManager.default.contentsOfDirectory(
            at: samples, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        // An empty folder counts as no samples, so a fresh clone skips the tests.
        return sets?.contains(where: \.hasDirectoryPath) == true ? samples : nil
    }()
}
