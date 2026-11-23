import DocumentModel
import LayoutAnalysis
import Testing
import TestSupport

@Suite("DocumentSnapshot")
struct DocumentSnapshotTests {
    private let document = Document(
        metadata: DocumentMetadata(title: "T", author: nil, language: "en"),
        chapters: [Chapter(title: "T", blocks: [.heading(level: 1, content: ["T"]), .paragraph(["Text."])])]
    )

    @Test("records each block's deciding rule and reports a different one")
    func rules() {
        let styles = BlockStyles(blocks: [BlockStyle(rule: .largerThanText), BlockStyle(rule: .paragraph)])
        let expected = DocumentSnapshot(document: document, unlinkedReferences: 0, unlinkedNotes: 0, styles: styles)
        #expect(expected.blocks.map(\.rule) == ["largerThanText", "paragraph"])

        let other = BlockStyles(blocks: [BlockStyle(rule: .bodySizeBold), BlockStyle(rule: .paragraph)])
        let actual = DocumentSnapshot(document: document, unlinkedReferences: 0, unlinkedNotes: 0, styles: other)
        #expect(actual.differences(from: expected) == ["block 0: rule bodySizeBold, expected largerThanText"])
        #expect(expected.differences(from: expected).isEmpty)
    }
}
