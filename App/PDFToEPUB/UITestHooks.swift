import Foundation

/// Launch arguments that let a UI test drive the app without the system
/// file panels, which XCUITest cannot operate reliably.
///
/// `-UITestFolder <path>` opens that folder of page images as soon as the
/// window appears; `-UITestOutput <path>` makes "Save EPUB…" write there
/// without asking. Both exist only in Debug builds, so a release build has no
/// way to skip the panels.
struct UITestHooks {
    /// The folder to open at launch.
    var folder: URL?
    /// Where "Save EPUB…" writes, instead of asking.
    var output: URL?

    /// No hooks: the normal behaviour.
    static let none = UITestHooks()

    /// The hooks named by this process's launch arguments.
    static var current: UITestHooks {
        #if DEBUG
            let defaults = UserDefaults.standard
            return UITestHooks(
                folder: defaults.string(forKey: "UITestFolder").map { URL(filePath: $0, directoryHint: .isDirectory) },
                output: defaults.string(forKey: "UITestOutput").map { URL(filePath: $0) }
            )
        #else
            return .none
        #endif
    }
}
