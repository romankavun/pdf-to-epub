import DocumentModel
import Foundation

/// Hand-built documents used across the exporter tests. All content is invented.
enum Fixtures {
    /// Smallest valid PNG: one transparent pixel.
    static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    static let document = Document(
        metadata: DocumentMetadata(identifier: "urn:uuid:0f8fad5b-d9cb-469f-a165-70867728950e", title: "Salt & Stone", author: "Ada Example", language: "uk"),
        chapters: [
            Chapter(title: "First <steps>", blocks: [
                .heading(level: 1, content: ["First <steps>"]),
                .paragraph(["Plain & simple, ", .emphasis("stressed"), " and ", .strong("bold"), .noteReference("n1"), "."]),
                .figure(Figure(imageID: "fig1", alternativeText: "A \"quoted\" valley", caption: ["Fig. 1. Valley"])),
                .heading(level: 2, content: ["Details"]),
                .paragraph(["Again", .noteReference("n1"), " and more", .noteReference("n2"), "."]),
            ]),
            Chapter(title: "Second", blocks: [
                .heading(level: 1, content: ["Second"]),
                .paragraph(["No notes here."]),
                .figure(Figure(imageID: "fig1", alternativeText: "")),
            ]),
        ],
        notes: [
            Note(id: "n1", label: "1", content: ["First note with ", .emphasis("style"), "."]),
            Note(id: "n2", label: "b", content: ["Second note."]),
            Note(id: "unused", label: "9", content: ["Never referenced."]),
        ],
        images: [
            ImageResource(id: "cover", filename: "cover.png", mediaType: "image/png", data: pngData),
            ImageResource(id: "fig1", filename: "fig-001.png", mediaType: "image/png", data: pngData),
        ],
        coverImageID: "cover"
    )
}
