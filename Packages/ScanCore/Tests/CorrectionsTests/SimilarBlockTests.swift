import Conversion
import Corrections
import DocumentModel
import Foundation
import LayoutAnalysis
import Testing

@Suite("Similar blocks")
struct SimilarBlockTests {
    /// Three one-line paragraphs of the same height and left edge, one of a
    /// different height, one centred, one that runs onto the next page.
    private func conversion() -> Conversion {
        let blocks: [Block] = [
            .paragraph(["Heading-like"]),
            .paragraph(["Another like it"]),
            .paragraph(["Tall"]),
            .paragraph(["Centred"]),
            .heading(level: 2, content: ["Real heading"]),
            .paragraph(["Third like it"]),
            .figure(Figure(imageID: "f", alternativeText: "")),
        ]
        func source(page: Int, x: Double, y: Double, width: Double, height: Double) -> BlockSource {
            BlockSource(page: page, box: CGRect(x: x, y: y, width: width, height: height))
        }
        var runsOn = source(page: 3, x: 0.1, y: 0.1, width: 0.3, height: 0.04)
        runsOn.add(CGRect(x: 0.1, y: 0.0, width: 0.3, height: 0.04), onPage: 4)
        var sources = [
            source(page: 0, x: 0.1, y: 0.1, width: 0.3, height: 0.04),
            source(page: 1, x: 0.1, y: 0.5, width: 0.5, height: 0.045),
            source(page: 1, x: 0.1, y: 0.2, width: 0.8, height: 0.12),
            source(page: 2, x: 0.3, y: 0.1, width: 0.4, height: 0.04),
            source(page: 2, x: 0.1, y: 0.3, width: 0.4, height: 0.04),
            source(page: 2, x: 0.1, y: 0.6, width: 0.2, height: 0.04),
            source(page: 2, x: 0.1, y: 0.7, width: 0.4, height: 0.3),
        ]
        sources[5] = runsOn
        return Conversion(
            document: Document(
                metadata: DocumentMetadata(identifier: "x", title: "T", author: nil, language: "uk"),
                chapters: [Chapter(title: "T", blocks: blocks)]
            ),
            blockSources: sources
        )
    }

    @Test("finds blocks of the same type with a similar height and the same left edge or centre")
    func finds() {
        let conversion = conversion()
        let found = SimilarBlocks.anchors(like: conversion.blockSources[0], ofType: .paragraph, in: conversion)
        // Block 1 matches (same height, same left edge). The tall one, the
        // heading, the figure and the block that runs onto a second page do
        // not; the centred one differs in both left edge and centre.
        #expect(found == [BlockAnchor(conversion.blockSources[1])])
    }

    @Test("a centred block matches another centred block")
    func centred() {
        var conversion = conversion()
        conversion.blockSources[1] = BlockSource(
            page: 1, box: CGRect(x: 0.35, y: 0.5, width: 0.3, height: 0.04)
        )
        let found = SimilarBlocks.anchors(like: conversion.blockSources[3], ofType: .paragraph, in: conversion)
        #expect(found == [BlockAnchor(conversion.blockSources[1])])
    }

    @Test("only blocks of the given type are candidates, and the reference is not one")
    func typeFilter() {
        let conversion = conversion()
        #expect(SimilarBlocks.anchors(like: conversion.blockSources[4], ofType: .heading(level: 3), in: conversion)
            .isEmpty)
        let found = SimilarBlocks.anchors(like: conversion.blockSources[0], ofType: .paragraph, in: conversion)
        #expect(!found.contains(BlockAnchor(conversion.blockSources[0])))
    }
}
