import Foundation

/// Locates `epubcheck` and decides whether a missing one is an error.
///
/// Locally a missing epubcheck only skips the conformance test (loudly); CI
/// sets `REQUIRE_EPUBCHECK=1` so that the check can never be skipped silently.
enum EPUBCheck {
    enum Resolution: Equatable {
        case found(String)
        case skip(String)
        case fail(String)
    }

    static let defaultLocations = ["/opt/homebrew/bin/epubcheck", "/usr/local/bin/epubcheck"]

    /// Resolution against the real environment and file system.
    static var current: Resolution {
        resolve(
            environment: ProcessInfo.processInfo.environment,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    /// Looks for the launcher in `EPUBCHECK_PATH`, the Homebrew locations and
    /// `PATH`, in that order.
    static func resolve(environment: [String: String], isExecutable: (String) -> Bool) -> Resolution {
        let pathDirectories = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/epubcheck" }
        let candidates = [environment["EPUBCHECK_PATH"]].compactMap(\.self) + defaultLocations + pathDirectories
        if let path = candidates.first(where: isExecutable) {
            return .found(path)
        }
        let required = !["", "0", "false"].contains(environment["REQUIRE_EPUBCHECK"] ?? "")
        if required {
            return .fail("epubcheck is not installed but REQUIRE_EPUBCHECK is set (brew install epubcheck).")
        }
        return .skip(
            "EPUB NOT VALIDATED: epubcheck is not installed (brew install epubcheck). "
                + "Set REQUIRE_EPUBCHECK=1 to make this an error."
        )
    }
}
