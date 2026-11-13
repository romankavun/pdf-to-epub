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
were found while fixing the last one.

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
   lost from the document. Not yet investigated (engine, erased marker nearby, or a line filter).
3. **A dash is read twice where a line breaks into pieces** (printed page
   66): the left piece ends with "-" and the right piece starts with "—",
   so the joined text has "- —".

## Improvements

### Next

- **Page preview on the progress screen.** While converting, show the scan of
  the page being processed with its number and a "page N of M" counter. Purely
  visual: no recognized data is shown, nothing can be edited, so nothing can be
  overwritten. Needs a new progress event "starting page N" that carries the
  page image. Skip intermediate pages if they go faster than they can be read.

### Later

- **Preview with outlines.** Extend the page preview with the current stage
  (OCR, notes, illustrations) and the lines and blocks outlined on the scan as
  soon as the page is recognized.
- **Live review during conversion.** Review and correct the pages that are
  already converted while the rest are still being recognized. Layout analysis
  is wholfile (paragraphs continue across pages, note numbering is repaired
  from the sequence, notes are linked at the end, running headers are found by
  repetition), so earlier pages can change as later ones arrive. Needs
  corrections stored apart from OCR and layout output (project persistence,
  milestone 8) first. Postponed together with the next item.
- **Parallel page recognition.** OCR runs one page at a time. Postponed.
- **Manual corrections in review.** Postponed; see milestone 7 and 8 in
  `CLAUDE.md`.
