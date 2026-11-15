import Testing
import TestSupport

private let prose = SyntheticPage.prose()

@Suite("Golden pages", .tags(.golden), .serialized)
struct GoldenPageTests {
    @Test("heading, paragraphs, illustration with caption and a linked note", .timeLimit(.minutes(10)))
    func basic() async throws {
        try await runGolden(GoldenCase(name: "basic", knownIssue: nil, pages: [
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

    @Test(
        "a note runs across an almost empty page and the next page's heading stays a heading",
        .timeLimit(.minutes(10))
    )
    func noteBeforeHeading() async throws {
        try await runGolden(GoldenCase(name: "note-before-heading", knownIssue: nil, pages: [
            prose,
            SyntheticPage([
                .line("> The morning harbour was quiet and the old bridge{1} stood empty"),
                .line("above the water until the evening came and the lamps were lit."),
                .moveTo(0.82), .rule,
                .line("> {1} The note begins at the bottom of the page and its sentence only"),
                .line("finishes with"),
                .pageNumber("1"),
            ]),
            SyntheticPage([.line("one word."), .pageNumber("2")]),
            SyntheticPage([
                .heading("Chapter Two"), .gap(1),
                .line("> The second chapter opens with a paragraph of ordinary prose that"),
                .line("runs over a few lines and then ends."),
                .pageNumber("3"),
            ]),
        ]))
    }

    @Test("several notes at the bottom of a page are all notes and the last continues", .timeLimit(.minutes(10)))
    func bottomNotes() async throws {
        try await runGolden(GoldenCase(name: "bottom-notes", knownIssue: nil, pages: [
            prose,
            SyntheticPage([
                .line("> The orchard{1} keeps its secrets{2} in winter and the meadow{3} waits"),
                .line("while the violin{4} plays on and the lantern{5} burns low."),
                .moveTo(0.70), .rule,
                .line("> {1} First note, a short one."),
                .line("> {2} Second note, also short."),
                .line("> {3} Third note that is a little longer than the others and"),
                .line("fills two lines."),
                .line("> {4} Fourth note whose sentence does not end on this page but"),
                .pageNumber("1"),
            ]),
            SyntheticPage([
                .line("continues here at the top of the next page."),
                .line("> {5} Fifth note, short."),
                .gap(1),
                .heading("Literature"), .gap(1),
                .line("> The next section opens with a paragraph of ordinary prose that"),
                .line("runs over two lines."),
                .pageNumber("2"),
            ]),
        ]))
    }

    @Test(
        "roman labels and Ukrainian text: a note across an almost empty page, then a heading",
        .timeLimit(.minutes(10))
    )
    func noteBeforeHeadingRoman() async throws {
        try await runGolden(GoldenCase(name: "note-before-heading-roman", knownIssue: nil, pages: [
            prose,
            SyntheticPage([
                .line("> Старий міст над річкою стояв порожній{IX} до самого вечора, коли"),
                .line("запалили ліхтарі{X} і вітер стих над садом{XI} знову."),
                .moveTo(0.78), .rule,
                .line("> {IX} Перша примітка, коротка."),
                .line("> {X} Друга примітка, теж коротка."),
                .line("> {XI} Третя примітка починається внизу сторінки і її речення"),
                .line("закінчується лише"),
                .pageNumber("1"),
            ]),
            SyntheticPage([.line("одним словом."), .pageNumber("2")]),
            SyntheticPage([
                .heading("Розділ другий"), .gap(1),
                .line("> Другий розділ починається абзацом звичайного тексту, який"),
                .line("займає кілька рядків і потім закінчується."),
                .pageNumber("3"),
            ]),
        ]))
    }

    @Test(
        "roman labels and Ukrainian text: tightly set notes at the bottom, one continuing, then a heading",
        .timeLimit(.minutes(10))
    )
    func bottomNotesRoman() async throws {
        try await runGolden(GoldenCase(name: "bottom-notes-roman", knownIssue: "docs/backlog.md defect 5", pages: [
            prose,
            SyntheticPage([
                .line("> Сад{LXXV} береже свої таємниці{LXXVI} взимку, а луг{LXXVII} чекає,"),
                .line("поки скрипка{LXXVIII} грає далі."),
                .moveTo(0.66), .rule,
                .line("> {LXXV} Перша примітка, коротка."),
                .line("> {LXXVI} Запис на одному рядку який доходить майже до правого краю"),
                .line("> {LXXVII} Третя примітка, трохи довша за інші і займає два"),
                .line("рядки повністю."),
                .line("> {LXXVIII} Четверте речення не закінчується на цій сторінці але"),
                .pageNumber("1"),
            ]),
            SyntheticPage([
                .line("продовжується тут, нагорі наступної сторінки."),
                .line("> {LXXIX} П'ята примітка."),
                .heading("Література"), .gap(1),
                .line("> Наступний розділ починається абзацом звичайного тексту, який"),
                .line("займає два рядки."),
                .pageNumber("2"),
            ]),
        ]))
    }
}
