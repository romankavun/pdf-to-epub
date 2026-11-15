import DocumentModel
import EPUBExport
import Foundation
import Testing
import TestSupport

/// Elements of an XML document, with the attributes the invariants look at.
private final class Elements: NSObject, XMLParserDelegate {
    struct Element {
        var name: String
        var attributes: [String: String]
    }

    var elements: [Element] = []

    func parser(
        _: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?,
        attributes: [String: String]
    ) {
        elements.append(Element(name: name, attributes: attributes))
    }

    /// `nil` when the data is not well-formed XML.
    static func parse(_ data: Data) -> [Element]? {
        let parser = XMLParser(data: data)
        let delegate = Elements()
        parser.delegate = delegate
        return parser.parse() ? delegate.elements : nil
    }
}

private struct Package {
    /// Every file of the archive, relative to the archive root.
    var files: Set<String> = []
    var contents: [String: Data] = [:]

    init(exporting document: Document, in folder: URL) throws {
        let epub = folder.appendingPathComponent("document.epub")
        try EPUBExporter().export(document, to: epub)
        let listing = try run("/usr/bin/unzip", ["-Z1", epub.path])
        files = Set(listing.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") })
        let unpacked = folder.appendingPathComponent("unpacked")
        _ = try run("/usr/bin/unzip", ["-q", "-o", epub.path, "-d", unpacked.path])
        for file in files {
            contents[file] = try Data(contentsOf: unpacked.appendingPathComponent(file))
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PropertyViolation(description: "\(tool) failed: \(String(decoding: output, as: UTF8.self))")
        }
        return String(decoding: output, as: UTF8.self)
    }

    func elements(of path: String) throws -> [Elements.Element] {
        guard let data = contents[path] else { throw PropertyViolation(description: "\(path) is not in the archive") }
        guard let elements = Elements.parse(data)
        else { throw PropertyViolation(description: "\(path) is not well-formed XML") }
        return elements
    }
}

/// `reference` as a path in the archive, resolved against the document that holds it.
private func resolve(_ reference: String, from document: String) -> (path: String, fragment: String?) {
    let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let target = String(parts[0])
    let fragment = parts.count > 1 ? String(parts[1]) : nil
    guard !target.isEmpty else { return (document, fragment) }
    let directory = (document as NSString).deletingLastPathComponent
    let combined = directory.isEmpty ? target : directory + "/" + target
    return ((combined as NSString).standardizingPath, fragment)
}

@Suite("EPUB invariants")
struct EPUBInvariantTests {
    private let generator = DocumentGenerator(text: .wild, layout: .tidy, maximumBlocks: 16)

    @Test("every link, image, id and note of a generated document points at something that exists")
    func referencesResolve() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("epub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        Property.check("epub references", cases: 60) { random in
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let document = generator.document(&random)
            let package = try Package(exporting: document, in: folder)

            // Container and package document.
            let rootfile = try package.elements(of: "META-INF/container.xml").first { $0.name == "rootfile" }
            guard let packagePath = rootfile?.attributes["full-path"] else {
                throw PropertyViolation(description: "container.xml names no package document")
            }
            try Property.require(package.files.contains(packagePath), "package document \(packagePath) is missing")
            let opf = try package.elements(of: packagePath)
            let items = opf.filter { $0.name == "item" }
            let manifestPaths = items.compactMap { $0.attributes["href"].map { resolve($0, from: packagePath).path } }
            try Property.requireEqual(manifestPaths.count, items.count, "manifest items without href")
            try Property.requireEqual(Set(manifestPaths).count, manifestPaths.count, "manifest lists a file twice")
            let ids = items.compactMap { $0.attributes["id"] }
            try Property.requireEqual(Set(ids).count, items.count, "manifest ids are not unique")

            // Manifest and archive list the same files, apart from the container itself.
            let own: Set = ["mimetype", "META-INF/container.xml", packagePath]
            try Property.requireEqual(
                Set(manifestPaths),
                package.files.subtracting(own),
                "manifest versus files in the archive"
            )
            for idref in opf.filter({ $0.name == "itemref" }).compactMap({ $0.attributes["idref"] }) {
                try Property.require(ids.contains(idref), "spine refers to unknown item \(idref)")
            }

            try checkLinks(in: package, documents: manifestPaths.filter { $0.hasSuffix(".xhtml") })
        }
    }

    /// Every document is well-formed, has unique ids, and every reference in it resolves.
    private func checkLinks(in package: Package, documents: [String]) throws {
        var idsOf: [String: Set<String>] = [:]
        for document in documents {
            let elements = try package.elements(of: document)
            let own = elements.compactMap { $0.attributes["id"] }
            try Property.requireEqual(Set(own).count, own.count, "duplicate id in \(document)")
            idsOf[document] = Set(own)
        }
        for document in documents {
            for element in try package.elements(of: document) {
                for key in ["href", "src"] {
                    guard let reference = element.attributes[key] else { continue }
                    let target = resolve(reference, from: document)
                    try Property.require(
                        package.files.contains(target.path),
                        "\(document): \(key)=\(reference) points at a missing file"
                    )
                    if let fragment = target.fragment {
                        try Property.require(
                            idsOf[target.path]?.contains(fragment) == true,
                            "\(document): \(key)=\(reference) points at a missing id"
                        )
                    }
                }
            }
        }
    }

    @Test("every note reference has a footnote, every footnote a reference, and each links back")
    func notesPair() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("epub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        Property.check("epub notes", cases: 60) { random in
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let document = generator.document(&random)
            let package = try Package(exporting: document, in: folder)
            let chapters = package.files.filter { $0.contains("chapter-") }.sorted()
            try Property.requireEqual(chapters.count, document.chapters.count, "chapter files")

            for (index, chapter) in chapters.enumerated() {
                let elements = try package.elements(of: chapter)
                let noteTargets = elements.filter { $0.attributes["epub:type"] == "noteref" }
                    .compactMap { $0.attributes["href"] }
                let footnotes = elements.filter { $0.attributes["epub:type"] == "footnote" }
                    .compactMap { $0.attributes["id"] }
                let backLinks = elements.filter { $0.name == "a" && $0.attributes["epub:type"] == nil }
                    .compactMap { $0.attributes["href"] }

                let referenced = Set(document.chapters[index].blocks.flatMap(\.referencedNoteIDs))
                try Property.requireEqual(
                    noteTargets.count, document.chapters[index].blocks.flatMap(\.referencedNoteIDs).count,
                    "\(chapter): note references rendered"
                )
                try Property.requireEqual(
                    Set(noteTargets),
                    Set(referenced.map { "#note-\($0)" }),
                    "\(chapter): noteref targets"
                )
                try Property.requireEqual(
                    Set(footnotes),
                    Set(referenced.map { "note-\($0)" }),
                    "\(chapter): footnotes versus references"
                )
                try Property.requireEqual(footnotes.count, referenced.count, "\(chapter): a footnote appears twice")
                try Property.requireEqual(
                    Set(backLinks),
                    Set(referenced.map { "#ref-\($0)" }),
                    "\(chapter): back links"
                )
            }
        }
    }

    @Test("the table of contents has one working entry per chapter")
    func navigation() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("epub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        Property.check("epub navigation", cases: 40) { random in
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let document = generator.document(&random)
            let package = try Package(exporting: document, in: folder)
            let entries = try package.elements(of: "EPUB/nav.xhtml").filter { $0.name == "a" }
                .compactMap { $0.attributes["href"] }
            try Property.requireEqual(entries.count, document.chapters.count, "table of contents entries")
            for entry in entries {
                try Property.require(
                    package.files.contains(resolve(entry, from: "EPUB/nav.xhtml").path),
                    "entry \(entry) points nowhere"
                )
            }
        }
    }
}
