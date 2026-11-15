import Conversion
import Corrections
import Foundation
import ProjectStore

/// What the app model needs from the disk to keep a project, as one seam,
/// so the models can be tested without touching files.
public protocol ProjectPersisting: Sendable {
    /// Whether `url` is a project folder rather than a folder of scans.
    func isProject(at url: URL) -> Bool

    /// Writes a new project for `conversion` in `parent`, as `name` followed
    /// by `.scanproject` or, when that is taken, by a number, and returns
    /// where it is with the conversion as stored.
    ///
    /// - Parameter movingPages: Whether the page images of `conversion` were
    ///   rendered for this project and are to be moved into it; the returned
    ///   conversion then points at the moved files.
    func createProject(
        for conversion: Conversion, named name: String, in parent: URL, movingPages: Bool
    ) throws -> (location: URL, conversion: Conversion)

    func load(from url: URL) throws -> Project

    func save(_ corrections: CorrectionSet, to url: URL) throws

    /// Replaces the ignored words of the project at `url`.
    func save(ignoredWords: Set<String>, to url: URL) throws

    /// Replaces the conversion of the project at `url` and keeps its
    /// corrections.
    func replaceConversion(in url: URL, with conversion: Conversion) throws
}

/// The project on the real disk, in a `.scanproject` folder beside the folder
/// of scans or the PDF.
public struct LiveProjectStorage: ProjectPersisting {
    private let store = ProjectStore()

    public init() {}

    public func isProject(at url: URL) -> Bool {
        store.isProject(at: url)
    }

    public func createProject(
        for conversion: Conversion, named name: String, in parent: URL, movingPages: Bool
    ) throws -> (location: URL, conversion: Conversion) {
        var attempt = 1
        while true {
            let suffix = attempt == 1 ? "" : " \(attempt)"
            let url = parent.appendingPathComponent("\(name)\(suffix).scanproject")
            do {
                return try (url, store.create(conversion, at: url, movingPages: movingPages))
            } catch ProjectStoreError.alreadyExists {
                attempt += 1
            }
        }
    }

    public func load(from url: URL) throws -> Project {
        try store.load(from: url)
    }

    public func save(_ corrections: CorrectionSet, to url: URL) throws {
        try store.save(corrections, to: url)
    }

    public func save(ignoredWords: Set<String>, to url: URL) throws {
        try store.save(ignoredWords: ignoredWords, to: url)
    }

    public func replaceConversion(in url: URL, with conversion: Conversion) throws {
        try store.replaceConversion(in: url, with: conversion)
    }
}
