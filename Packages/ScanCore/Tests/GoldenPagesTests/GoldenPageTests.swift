import Testing
import TestSupport

private let prose = SyntheticPage.prose()

@Suite("Golden pages", .tags(.golden), .serialized)
struct GoldenPageTests {
    @Test("heading, paragraphs, illustration with caption and a linked note", .timeLimit(.minutes(10)))
    func basic() async throws {
        try await runGolden(GoldenCase(name: "basic", pages: [
            prose,
            SyntheticPage([
                .heading("The Orchard"), .gap(1),
                .line("> Morning came over the harbour and the old{1} bridge"),
                .line("was quiet until the violin began to play."),
                .picture(height: 0.2, caption: "The bridge at dawn"),
                .line("> A second paragraph follows the picture and"),
                .line("ends here."),
                .moveTo(0.82), .rule,
                .line("> {1} A note about the bridge."),
                .pageNumber("2"),
            ]),
        ]))
    }
}
