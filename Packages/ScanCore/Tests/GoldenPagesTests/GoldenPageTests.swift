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

private let shortProse = SyntheticPage.prose(lines: 8)

@Suite("Golden pages: coverage", .tags(.golden), .serialized)
struct GoldenCoverageTests {
    @Test("Ukrainian body with English fragments", .timeLimit(.minutes(10)))
    func bilingual() async throws {
        try await runGolden(GoldenCase(name: "bilingual", knownIssue: nil, pages: [
            shortProse,
            SyntheticPage([
                .heading("Розділ перший"), .gap(1),
                .line("> Вечір над садом був тихий, і хтось сказав: the old bridge is"),
                .line("quiet tonight, а потім додав, що завтра буде дощ."),
                .gap(0.5),
                .line("> У книжці він прочитав речення all roads lead to the harbour"),
                .line("і довго думав про нього."),
                .pageNumber("1"),
            ]),
        ]))
    }

    @Test("bulleted and numbered lists", .timeLimit(.minutes(10)))
    func lists() async throws {
        try await runGolden(GoldenCase(name: "lists", knownIssue: nil, pages: [
            shortProse,
            SyntheticPage([
                .heading("Packing list"), .gap(1),
                .line("> Take the following things on the journey:"),
                .line("> • a warm blanket for the cold nights"),
                .line("> • a lantern with spare candles"),
                .line("> • a small violin case"),
                .line("> Then follow these steps in order:"),
                .line("> 1. Close the shutters of the house."),
                .line("> 2. Lock the old gate behind you."),
                .line("> 3. Walk down to the harbour."),
                .pageNumber("1"),
            ]),
        ]))
    }

    @Test("headings of three levels", .timeLimit(.minutes(10)))
    func multiLevelHeadings() async throws {
        try await runGolden(GoldenCase(name: "multi-level-headings", knownIssue: "docs/backlog.md defect 8", pages: [
            shortProse,
            SyntheticPage([
                .heading("The Orchard", scale: 2.0), .gap(0.5),
                .heading("Early Years", scale: 1.5), .gap(0.5),
                .line("> The orchard was planted long ago by people who loved the"),
                .line("river and the stone wall."),
                .gap(0.5),
                .heading("The First Winter", scale: 1.25), .gap(0.5),
                .line("> That winter was cold and the lanterns burned late into the"),
                .line("night."),
                .gap(0.5),
                .heading("Later Years", scale: 1.5), .gap(0.5),
                .line("> Later the meadow was sold and the bridge was rebuilt."),
                .pageNumber("1"),
            ]),
        ]))
    }

    @Test("a contents page followed by the first chapter", .timeLimit(.minutes(10)))
    func contentsPage() async throws {
        try await runGolden(GoldenCase(name: "contents-page", knownIssue: "docs/backlog.md defect 9", pages: [
            shortProse,
            SyntheticPage([
                .heading("Contents"), .gap(1),
                .line("> The Orchard 3"),
                .line("> Early Years 7"),
                .line("> The First Winter 12"),
                .line("> Later Years 18"),
                .pageNumber("1"),
            ]),
            SyntheticPage([
                .heading("The Orchard"), .gap(1),
                .line("> The orchard was planted long ago by people who loved the"),
                .line("river and the stone wall."),
                .pageNumber("2"),
            ]),
        ]))
    }

    @Test("a picture-only first page is the cover and contributes no text", .timeLimit(.minutes(10)))
    func cover() async throws {
        try await runGolden(GoldenCase(name: "cover", knownIssue: nil, pages: [
            SyntheticPage([.picture(height: 0.7, caption: nil)]),
            shortProse,
            SyntheticPage([
                .heading("The Orchard"), .gap(1),
                .line("> The orchard was planted long ago by people who loved the"),
                .line("river and the stone wall."),
                .pageNumber("2"),
            ]),
        ]))
    }

    @Test("a page that is only an illustration with a caption", .timeLimit(.minutes(10)))
    func pictureOnlyPage() async throws {
        try await runGolden(GoldenCase(name: "picture-page", knownIssue: "docs/backlog.md defect 10", pages: [
            shortProse,
            SyntheticPage([
                .line("> The last paragraph before the full page picture ends here."),
                .pageNumber("1"),
            ]),
            SyntheticPage([
                .gap(2), .picture(height: 0.5, caption: "The harbour at night"),
                .pageNumber("2"),
            ]),
            SyntheticPage([
                .line("> The next paragraph starts after the picture page and runs on."),
                .pageNumber("3"),
            ]),
        ]))
    }

    @Test("the basic document drawn into a PDF and imported", .timeLimit(.minutes(10)))
    func pdfInput() async throws {
        try await runGolden(GoldenCase(name: "pdf-basic", knownIssue: nil, pages: [
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
        ], viaPDF: true))
    }
}
