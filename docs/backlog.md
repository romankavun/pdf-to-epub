# Backlog

Known defects and planned improvements that are not built yet. Each item
becomes a test first (see the TDD rule in `CLAUDE.md`) and is removed from here
when fixed. Page numbers are the printed numbers in the user's sample set
about Ukrainian folk demonology; do not copy its text here.

## Defects found by hand in the review screen

Found on 2026-11-13 while checking the first manual run, then checked
against the layout of the whole document (a dump of lines, markers, blocks and
notes) the same day. Printed page N is page image N + 1. Other defects
found then are fixed: a paragraph at the top of a page and the first note
under the rule had no outline (review now shows a block on every page it
covers and the text of linked notes, and notes are linked within their own
numbering system, [ADR 0004](adr/0004-two-numbering-systems.md)), and a
paragraph was split in two where the engine reported a line as two pieces
whose boxes overlap slightly (now joined as one line). Defects 2 and 3 below
were found while fixing the last one. A short bold or centered heading at
body size that opened a page and was glued to the previous page's paragraph
is now a heading ([ADR 0006](adr/0006-body-size-headings.md)); checked on the
page in question. Defects 4 and 5 are not changed by it.

1. **A list is not captured** (printed pages 62, 63). *Not reproduced:* in
   the dump the items `1)`, `2)`, `3)` on printed pages 61-63 are separate
   paragraphs with their own areas, and the review model built from a full
   conversion lists them on review pages 63 and 64 with those areas. Lists
   still have no rule of their own (they come out as paragraphs, not
   `<ol>`). If the outlines are still missing on screen, the cause is in the
   view, not the model.
2. **Part of a line is missing from the OCR output** (printed page 58,
   second paragraph). The right-hand part of a line, from the dash
   onwards, is not among the lines the engine returns, so its words are
   lost from the document. Not yet investigated (engine, erased marker
   nearby, or a line filter).
3. **A dash is read twice where a line breaks into pieces** (printed page
   66): the left piece ends with "-" and the right piece starts with "—",
   so the joined text has "- —".

4. **The heading of the next page is taken into a note** (test document
   `test/weinachten`, review pages 16-18 of 31). Note XI starts at the bottom
   of review page 16 and continues on page 17, where the continuation is one
   word ("померлих."), alone on an otherwise empty page (printed page 18).
   The next page (18, printed 103) opens with a chapter heading, and the
   text of Note XI ends with that heading's text, so the heading is missing
   as a heading and the note is too long. Cause not investigated: probably
   the continuation of a note runs on into the next page's first block
   across an almost empty page. Expected: a note ends where its sentence
   ends; a heading never continues a note. Reproduce with synthetic pages:
   a note at the bottom of page 1, a page with one short line, then a page
   starting with a larger heading.

5. **Notes at the bottom of a page are not all recognized, and the rest
   become paragraphs** (test document `test/weinachten`, review pages 24-25 of
   31). On page 24 the first note under the rule is a note, but the next two
   (LXXVI, LXXVII) are paragraphs whose text starts with the marker label
   ("LXXVI Запис на..."). The last one continues on page 25 as a paragraph,
   and there the next note (LXXVIII) is a paragraph too, with the label in
   its text and the word that starts the next section heading ("Література")
   glued to its end. The markers are in the link colour in the scan, so the
   marker search missed them or did not link them to the references (the
   page-24 marker of the third note sits close to the end of the previous
   note). Not investigated; the same problem as defect 4 may be involved in
   the glued heading. Expected: every block under the rule that opens with a
   marker is a note, continued across the page break as one note.
   Reproduce with synthetic pages: four notes under a rule, the last one
   continuing on the next page, followed by a note and a heading.

## Improvements

### Review screen and summary (ideas from hands-on use, 2026-11-14)

- **Page context in the "Similar blocks" dialog.** When choosing among the
  similar blocks, show the scan page with the block outlined in its context,
  not only the text and the page number, so it is clear whether the block
  really is the same kind.
- **Clearer colour coding per block type.** Make the outline and label colour
  of each block type (headings by level, paragraph, note, illustration,
  ignored) easier to tell apart.
- **Split a block in two while editing.** Let the user split a block into two
  and give each part its own type. Part of "merging and splitting blocks"
  under Later.
- **Edit Text keeps the block's size.** The editor of a large block shrinks to
  a fixed height with its own scroll bar and the text jumps. It should keep
  the block's height (or grow with the text) so that nothing moves.
- **Section of manual changes in the review.** An optional section, not always
  visible (shown and hidden on request), listing every change made by hand
  (type changes, edited text, ignored blocks, applied fixes).
- **Suspicious words on the summary screen.** In "Needs attention" show how
  many suspicious words remain in the project (the review already shows
  "Issue N of M").
- **Clickable "Needs attention" items.** A click on an item (suspicious words,
  references without a note, notes without a reference) opens the review at
  the page and block where that problem is.
- **Edit notes and link them by hand.** Edit a note's text and connect a note
  to a reference, or detach it, by hand. Low priority.
- **Contents pages.** Detect pages that hold the contents and make them
  functional (entries become links to the headings). Low priority.

### Later

- **Preview with outlines.** Extend the page preview on the progress screen
  with the current stage (OCR, notes, illustrations) and the lines and blocks
  outlined on the scan as soon as the page is recognized.
- **Live review during conversion.** Review and correct the pages that are
  already converted while the rest are still being recognized. Layout analysis
  is wholfile (paragraphs continue across pages, note numbering is repaired
  from the sequence, notes are linked at the end, running headers are found by
  repetition), so earlier pages can change as later ones arrive. Needs
  corrections stored apart from OCR and layout output (project persistence,
  milestone 8) first. Postponed together with the next item.
- **Parallel page recognition.** OCR runs one page at a time. Postponed.
- **More corrections.** Merging and splitting blocks, redrawing a block's
  region, starting a chapter elsewhere, formatting (bold, italic) in the
  text editor, and a "set this and the following pages" way to drop page
  numbers and running headers. See [corrections](features/corrections.md)
  for what exists.
- **Copy the scans into the project** (or store a reference) so that a
  moved scan folder does not leave the review without page images.
- **Save the undo history** with the project.
