import Conversion
import Corrections
import Foundation
import ProjectStore

/// What the app model needs from the disk to keep a project, as one seam,
/// so the models can be tested without touching files.
public protocol ProjectPersisting: Sendable {
    /// Whether `url` is a project folder rather than a folder of scans.
    func isProject(at url: URL) -> Bool

    /// Writes a new project for `conversion` next to `folder`, under a name
    /// that is not taken yet, and returns where it is.
    func createProject(for conversion: Conversion, nextTo folder: URL) throws -> URL

    func load(from url: URL) throws -> Project

    func save(_ corrections: CorrectionSet, to url: URL) throws

    /// Replaces the ignored words of the project at `url`.
    func save(ignoredWords: Set<String>, to url: URL) throws

    /// Replaces the conversion of the project at `url` and keeps its
    /// corrections.
    func replaceConversion(in url: URL, with conversion: Conversion) throws
}

/// The project on the real disk, in a `.scanproject` folder beside the folder
/// of scans.
public struct LiveProjectStorage: ProjectPersisting {
    private let store = ProjectStore()

    public init() {}

    public func isProject(at url: URL) -> Bool {
        store.isProject(at: url)
    }

    public func createProject(for conversion: Conversion, nextTo folder: URL) throws -> URL {
        let parent = folder.deletingLastPathComponent()
        let name = folder.lastPathComponent
        var attempt = 1
        while true {
            let suffix = attempt == 1 ? "" : " \(attempt)"
            let url = parent.appendingPathComponent("\(name)\(suffix).scanproject")
            do {
                try store.create(conversion, at: url)
                return url
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
