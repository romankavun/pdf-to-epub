import Foundation

/// Why a folder could not be imported.
public enum ImportError: Error, Equatable, Sendable {
    /// The path does not exist or is not a folder.
    case notADirectory(URL)
    /// The folder contains no supported image files.
    case noImages(URL)
}

/// Finds the page images of a document stored as one image file per page.
public struct ImageFolderImporter: Sendable {
    /// File extensions treated as page images, lowercase.
    public static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic"]

    public init() {}

    /// The page images directly inside `folder`, in reading order.
    ///
    /// Order follows the file names the way Finder sorts them, so `page_2`
    /// comes before `page_10`. Hidden files and subfolders are ignored.
    public func pageURLs(in folder: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ImportError.notADirectory(folder)
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )
        let pages = contents
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !pages.isEmpty else { throw ImportError.noImages(folder) }
        return pages
    }
}
