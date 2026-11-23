import Foundation

/// Opening a document that was converted before: its project, or starting
/// over (ADR 0011).
public extension ConversionModel {
    /// Whether ``startOver()`` would do anything.
    var canStartOver: Bool {
        canConvert && existingProject != nil
    }

    /// Opens ``existingProject`` instead of converting the open folder or PDF.
    func openExistingProject() {
        guard let existingProject else { return }
        openProject(at: existingProject)
    }

    /// Converts the open folder or PDF into a new project that replaces
    /// ``existingProject``, whose corrections are discarded with it. The old
    /// project goes to the Trash only once the conversion has finished, so
    /// a cancelled or failed run leaves it alone. Does nothing when
    /// ``canStartOver`` is false.
    func startOver() {
        guard canStartOver else { return }
        replacesExistingProject = true
        start()
    }
}

extension ConversionModel {
    /// The project a conversion of `source` would be saved as, if it exists.
    func projectBeside(_ source: URL) -> URL? {
        let url = source.deletingLastPathComponent()
            .appendingPathComponent(Self.documentName(for: source) + ".scanproject")
        return storage.isProject(at: url) ? url : nil
    }
}
