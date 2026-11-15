# Layout analysis

Turns the text lines recognized on each page into headings and paragraphs
(`LayoutAnalyzer` in the `LayoutAnalysis` module). It works on line and
picture positions only, never on pixels, and measures everything relative to
the document's own typical line, so page size and resolution do not matter.
Pictures and their captions are described in
[illustrations](illustrations.md), note references and note texts in
[notes](notes.md).

## Rules

| Decision | Rule |
|---|---|
| Body margin | The most common left edge among long lines in the whole document |
| New paragraph | The line starts to the right of the margin (first-line indent), **or** the vertical step from the previous line is more than 1.5 typical steps (a blank line) |
| Paragraph across pages | A page whose first line is not indented continues the last paragraph of the previous page |
| Heading | A line at least 1.5 times taller than the median line, whose box does not overlap a line above or below it by more than 10% of its height (a body line that the OCR engine measured two lines high does). Consecutive tall lines directly below each other form one heading. Always level 1 |
| Line in pieces | Boxes side by side on one row (sharing over half their height and overlapping horizontally by at most half the narrower box; the engine often starts a piece that opens with a dash slightly inside the piece before it) are joined into one line, left to right |
| Text inside a picture | Dropped |
| Note text in a list | A paragraph that opens with a note marker at the margin has a hanging indent: its indented lines continue it, and an unindented line without a marker ends it |
| Heading at body size | A single line, at most 70% of the page wide, not ending in `. , ; : …`, with a blank line (or the page edge) above it and either **bold** (ink density at least 1.15 times the document's typical line; the text below may follow closely) or **centered** with at most 8 words (which also needs a blank line, the page edge or a picture below). Level 2, or level 1 when the document has no larger headings. A line right under a picture, or carrying a note marker, never qualifies. Ink is measured from the page image during conversion; without measurements only centering is used. See [ADR 0006](../adr/0006-body-size-headings.md) |
| Page number | The last line of a page, if it is in the bottom 15%, at most four characters, digits only. Dropped |
| Running header, footer, page number by repetition | A line in the top 10% or bottom 12% of the page whose text, with digits replaced by `#` (a lone Arabic or Roman numeral is always `#`), recurs at the same height (within 2% of the page) on at least 3 pages and 10% of all pages. Dropped on those pages. A header that alternates between left and right pages recurs on every other page, which suffices. Lines without letters or digits (an ornament) are kept |
| Line joining | Lines are joined with a space; a line ending in a letter plus hyphen is joined without one, keeping the hyphen |

Thresholds live in `LayoutAnalyzer.Options`.

## Where each block comes from

Besides the blocks, `DocumentLayout` records their origin for the review
screen: `sources` gives, for every block, the area it covers on each page it
touches (a `BlockSource` is the area on the page it starts on plus one per
page it runs onto), and `noteSources` does the same for the text of every
linked note, which is not among the blocks. A caption widens the area of
its figure.

## Known limits

- Headings at body size need blank space above them (and below, unless bold); one that wraps onto
  two lines, or one that is not set apart, comes out as a paragraph. A bold
  one-line paragraph with space around it is read as a heading. Italic is not
  detected. Only two heading levels are produced.
- A paragraph that starts at the top of a page without an indent is merged
  into the previous page's paragraph.
- Hyphens at line ends are always kept. This suits clean pages,
  which do not hyphenate; printed documents with soft hyphenation will get stray
  hyphens.
- Running headers need a few repetitions: in a document or excerpt shorter than
  about three pages with the same header, nothing is removed. A header whose
  text changes on every page (the chapter title is the same, the page's first
  word is not) is not recognized.
- Lists are not recognized. Items set in a narrower, indented column may be
  missing from the result (see [backlog](../backlog.md), defect 2).
- Single-column pages only. Because pieces on one row are joined, a table
  or two columns of text are read across, row by row.
- No inline formatting (italic, bold) is recovered.
