import Corrections
import DocumentModel
import Testing

@Suite("Editing the text of inline content")
struct InlineSpliceTests {
    private let placeholder = "\u{FFFC}"

    @Test("writes a note reference as one placeholder character")
    func canonicalText() {
        let content: [Inline] = ["Text", .noteReference("n1"), .emphasis(" end")]
        #expect(content.canonicalText == "Text\(placeholder) end")
    }

    @Test("writes note references with their labels for the editor")
    func editableText() {
        let content: [Inline] = ["Text", .noteReference("n1"), " end"]
        #expect(content.editableText(noteLabels: ["n1": "7"]) == "Text⟦7⟧ end")
        #expect(content.editableText(noteLabels: [:]) == "Text⟦?⟧ end")
    }

    @Test("turns the editor's note tokens back into placeholders")
    func canonicalFromEditor() {
        #expect(String(editorText: "A⟦7⟧ b⟦⟧ c") == "A\(placeholder) b\(placeholder) c")
    }

    @Test("a change inside an emphasized run keeps the emphasis")
    func keepsStyle() {
        let content: [Inline] = ["He read ", .emphasis("Журавeль"), " aloud."]
        let edited = content.replacingText(with: "He read Журавель aloud.")
        #expect(edited == ["He read ", .emphasis("Журавель"), " aloud."])
    }

    @Test("keeps note references the edit does not touch")
    func keepsReferences() {
        let content: [Inline] = ["Clean text", .noteReference("n1"), " goes on."]
        let edited = content.replacingText(with: "Clean text\(placeholder) continues.")
        #expect(edited == ["Clean text", .noteReference("n1"), " continues."])
    }

    @Test("deleting the placeholder drops the reference")
    func dropsReference() {
        let content: [Inline] = ["Clean text", .noteReference("n1"), " goes on."]
        #expect(content.replacingText(with: "Clean text goes on.") == ["Clean text goes on."])
    }

    @Test("a placeholder the editor added has no reference to point to and is dropped")
    func ignoresAddedPlaceholder() {
        let content: [Inline] = ["One"]
        #expect(content.replacingText(with: "One\(placeholder) two") == ["One two"])
    }

    @Test("an edit spanning two runs puts the new text in the first one")
    func spansRuns() {
        let content: [Inline] = ["ab ", .strong("cd"), " ef"]
        #expect(content.replacingText(with: "aXf") == ["aXf"])
        #expect(content.replacingText(with: "ab cXf") == ["ab ", .strong("cX"), "f"])
    }

    @Test("identical text changes nothing and text can grow from empty")
    func degenerate() {
        let content: [Inline] = ["a", .emphasis("b")]
        #expect(content.replacingText(with: "ab") == content)
        #expect(([] as [Inline]).replacingText(with: "new") == ["new"])
    }
}
