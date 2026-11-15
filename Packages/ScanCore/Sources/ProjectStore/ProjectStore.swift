import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis

/// A converted document together with what the user decided about it.
public struct Project: Sendable, Equatable {
    /// The pipeline's output, untouched by corrections.
    public var conversion: Conversion
    public var corrections: CorrectionSet
    /// Words the user told the review to stop flagging, lowercased.
    public var ignoredWords: Set<String>

    public init(
        conversion: Conversion, corrections: CorrectionSet = CorrectionSet(), ignoredWords: Set<String> = []
    ) {
        self.conversion = conversion
        self.corrections = corrections
        self.ignoredWords = ignoredWords
    }
}

public enum ProjectStoreError: Error, Equatable {
    /// Something already exists where a project was to be created.
    case alreadyExists
    /// The folder has no project file.
    case notAProject
    /// The project was written by a newer version of the app.
    case unsupportedVersion(Int)
    /// An image's file name would leave the project's `images` folder.
    case invalidImageName(String)
    /// A file of the project is missing or cannot be read.
    case damaged(String)
}

/// Reads and writes a project as a bundle folder:
///
/// ```
/// Name.scanproject/
///   project.json       the conversion without image bytes
///   images/            one file per image of the document
///   pages/             page images rendered from a PDF (optional)
///   corrections.json   the user's decisions
///   ignored-words.json words the review no longer flags (optional)
/// ```
///
/// Corrections have a file of their own because they change after every
/// edit and are small, while the conversion is large and changes only when
/// the document is converted again. Converting again replaces the conversion
/// and leaves the corrections alone.
public struct ProjectStore: Sendable {
    private static let formatVersion = 1
    private static let projectFile = "project.json"
    private static let correctionsFile = "corrections.json"
    private static let ignoredWordsFile = "ignored-words.json"
    private static let imagesFolder = "images"
    private static let pagesFolder = "pages"

    public init() {}

    /// Whether `url` is a project folder.
    public func isProject(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(Self.projectFile).path)
    }

    /// Writes a new project with no corrections at `url`, which must not
    /// exist yet. Nothing is left at `url` when writing fails.
    ///
    /// - Parameter movingPages: Whether the page images of `conversion`
    ///   belong to the project and are moved into its `pages` folder. That
    ///   is for pages rendered from a PDF, which exist nowhere else; scans
    ///   in a folder stay where they are and are only referred to.
    /// - Returns: `conversion` with its page URLs pointing at the moved
    ///   files; unchanged when nothing was moved.
    @discardableResult
    public func create(_ conversion: Conversion, at url: URL, movingPages: Bool = false) throws -> Conversion {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path) else { throw ProjectStoreError.alreadyExists }
        try Self.validateImageNames(of: conversion)
        // Written beside the destination and moved in one step, so a crash
        // cannot leave a half-written project that looks complete.
        let staging = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).partial")
        var movedFrom: [(from: URL, to: URL)] = []
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: false)
            var stored = conversion
            if movingPages {
                let pages = staging.appendingPathComponent(Self.pagesFolder)
                try manager.createDirectory(at: pages, withIntermediateDirectories: false)
                for page in conversion.pageURLs {
                    let target = pages.appendingPathComponent(page.lastPathComponent)
                    guard !manager.fileExists(atPath: target.path) else {
                        throw ProjectStoreError.invalidImageName(page.lastPathComponent)
                    }
                    try manager.moveItem(at: page, to: target)
                    movedFrom.append((page, target))
                }
                stored.pageURLs = conversion.pageURLs.map {
                    url.appendingPathComponent(Self.pagesFolder).appendingPathComponent($0.lastPathComponent)
                }
            }
            try Self.writeConversion(stored, in: staging, bundle: url)
            try Self.write(Stored.Corrections(corrections: CorrectionSet()), to: staging, name: Self.correctionsFile)
            try manager.moveItem(at: staging, to: url)
            return stored
        } catch {
            // Put moved pages back so a failed save loses nothing.
            for move in movedFrom {
                try? manager.moveItem(at: move.to, to: move.from)
            }
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    public func load(from url: URL) throws -> Project {
        guard isProject(at: url) else { throw ProjectStoreError.notAProject }
        do {
            let stored = try Self.read(Stored.Project.self, from: url, name: Self.projectFile)
            guard stored.formatVersion == Self.formatVersion else {
                throw ProjectStoreError.unsupportedVersion(stored.formatVersion)
            }
            var images: [ImageResource] = []
            for image in stored.images {
                let file = url.appendingPathComponent(Self.imagesFolder).appendingPathComponent(image.filename)
                try images.append(ImageResource(
                    id: image.id, filename: image.filename, mediaType: image.mediaType,
                    data: Data(contentsOf: file)
                ))
            }
            let document = Document(
                metadata: stored.metadata, chapters: stored.chapters, notes: stored.notes,
                images: images, coverImageID: stored.coverImageID
            )
            let conversion = Conversion(
                document: document,
                unlinkedReferences: stored.unlinkedReferences,
                unlinkedNotes: stored.unlinkedNotes,
                pageURLs: stored.pageURLs.map { Self.pageURL($0, in: url) },
                blockSources: stored.blockSources,
                noteSources: stored.noteSources
            )
            let corrections = try Self.read(Stored.Corrections.self, from: url, name: Self.correctionsFile)
            let ignored = try? Self.read(Stored.IgnoredWords.self, from: url, name: Self.ignoredWordsFile)
            return Project(
                conversion: conversion, corrections: corrections.corrections,
                ignoredWords: Set(ignored?.words ?? [])
            )
        } catch let error as ProjectStoreError {
            throw error
        } catch {
            throw ProjectStoreError.damaged(String(describing: error))
        }
    }

    /// Replaces the corrections of the project at `url`.
    public func save(_ corrections: CorrectionSet, to url: URL) throws {
        guard isProject(at: url) else { throw ProjectStoreError.notAProject }
        try Self.write(Stored.Corrections(corrections: corrections), to: url, name: Self.correctionsFile)
    }

    /// Replaces the ignored words of the project at `url`. They have a file
    /// of their own: they are not corrections of the document and are not undone.
    public func save(ignoredWords: Set<String>, to url: URL) throws {
        guard isProject(at: url) else { throw ProjectStoreError.notAProject }
        try Self.write(Stored.IgnoredWords(words: ignoredWords.sorted()), to: url, name: Self.ignoredWordsFile)
    }

    /// Replaces the conversion of the project at `url`, for a document converted
    /// again, and keeps its corrections.
    ///
    /// The new images are written first and swapped in, then the project
    /// file; a crash in between leaves a project that reports itself as
    /// damaged rather than one that silently mixes the two conversions.
    public func replaceConversion(in url: URL, with conversion: Conversion) throws {
        guard isProject(at: url) else { throw ProjectStoreError.notAProject }
        try Self.validateImageNames(of: conversion)
        let manager = FileManager.default
        let staging = url.appendingPathComponent(".images.\(UUID().uuidString).partial")
        do {
            try Self.writeImages(of: conversion.document, to: staging)
            let images = url.appendingPathComponent(Self.imagesFolder)
            try? manager.removeItem(at: images)
            try manager.moveItem(at: staging, to: images)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        try Self.write(
            Stored.Project(conversion, version: Self.formatVersion, bundle: url), to: url, name: Self.projectFile
        )
    }

    // MARK: - Files

    /// - Parameter bundle: Where the project will finally be, which may
    ///   differ from `folder`, where it is written first.
    private static func writeConversion(_ conversion: Conversion, in folder: URL, bundle: URL) throws {
        try writeImages(of: conversion.document, to: folder.appendingPathComponent(imagesFolder))
        try write(Stored.Project(conversion, version: formatVersion, bundle: bundle), to: folder, name: projectFile)
    }

    /// Pages in the bundle are stored relative to it, so the bundle can be
    /// moved or renamed; other pages are stored as absolute paths.
    static func storedPath(of page: URL, in bundle: URL) -> String {
        let prefix = bundle.resolvingSymlinksInPath().appendingPathComponent(pagesFolder).path + "/"
        let path = page.resolvingSymlinksInPath().path
        return path.hasPrefix(prefix) ? pagesFolder + "/" + path.dropFirst(prefix.count) : page.path
    }

    private static func pageURL(_ stored: String, in bundle: URL) -> URL {
        stored.hasPrefix("/")
            ? URL(fileURLWithPath: stored)
            : bundle.appendingPathComponent(stored)
    }

    private static func writeImages(of document: Document, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for image in document.images {
            try image.data.write(to: folder.appendingPathComponent(image.filename), options: .atomic)
        }
    }

    /// An image is written to `images/<filename>`, so the name must be one
    /// plain path component.
    private static func validateImageNames(of conversion: Conversion) throws {
        for image in conversion.document.images {
            let name = image.filename
            guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.hasPrefix("."),
                  !name.contains("/")
            else { throw ProjectStoreError.invalidImageName(name) }
        }
    }

    private static func write(_ value: some Encodable, to folder: URL, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, from folder: URL, name: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: folder.appendingPathComponent(name)))
    }
}

/// The JSON forms of what is stored.
private enum Stored {
    struct Image: Codable {
        var id: ImageResource.ID
        var filename: String
        var mediaType: String
    }

    struct Corrections: Codable {
        var formatVersion = 1
        var corrections: CorrectionSet
    }

    struct IgnoredWords: Codable {
        var formatVersion = 1
        var words: [String]
    }

    struct Project: Codable {
        var formatVersion: Int
        var metadata: DocumentMetadata
        var chapters: [Chapter]
        var notes: [Note]
        var images: [Image]
        var coverImageID: ImageResource.ID?
        var unlinkedReferences: Int
        var unlinkedNotes: Int
        /// Scans stay where they are and are stored as absolute paths; pages
        /// rendered from a PDF live in the bundle and are stored relative to it.
        var pageURLs: [String]
        var blockSources: [BlockSource]
        var noteSources: [BlockSource]

        init(_ conversion: Conversion, version: Int, bundle: URL) {
            let document = conversion.document
            formatVersion = version
            metadata = document.metadata
            chapters = document.chapters
            notes = document.notes
            images = document.images.map { Image(id: $0.id, filename: $0.filename, mediaType: $0.mediaType) }
            coverImageID = document.coverImageID
            unlinkedReferences = conversion.unlinkedReferences
            unlinkedNotes = conversion.unlinkedNotes
            pageURLs = conversion.pageURLs.map { ProjectStore.storedPath(of: $0, in: bundle) }
            blockSources = conversion.blockSources
            noteSources = conversion.noteSources
        }
    }
}
