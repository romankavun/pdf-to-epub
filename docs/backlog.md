# Backlog

Known defects and planned improvements that are not built yet. Each item
becomes a test first (see the TDD rule in `CLAUDE.md`) and is removed from here
when fixed. Page numbers are the printed numbers in the user's sample set
about Ukrainian folk demonology; do not copy its text here.

## Defects found by hand in the review screen

Found on 2026-11-13 while checking the first manual run, then checked
against the layout of the whole document (a dump of lines, markers, blocks and
notes) the same day. Printed page N is page image N + 1.

1. **Paragraph at the top of a page is not outlined** (printed pages 65,
   66). *Diagnosed:* no text is lost. The continuation is merged into the
   paragraph from the previous page, as designed, and review shows a block
   only on the page where it starts. Fix in review: show the block on every
   page it covers.
2. **A list is not captured** (printed pages 62, 63). *Not reproduced:* in
   the dump the items `1)`, `2)`, `3)` on printed pages 61-63 are separate
   paragraphs with their own areas. Lists still have no rule of their own
   (they come out as paragraphs, not `<ol>`). Needs the exact page from the
   user before anything else.
3. **The first note under the rule is not outlined** (printed page 57, note
   50). *Diagnosed, two causes:*
   - Note 50 is recognized and linked. Review does not show the text of a
     linked note at all, only unlinked note texts (as paragraphs), so the
     page shows exactly the notes that failed. Fix in review: show note
     texts on their page.
   - The document has two numbering systems: footnotes under a rule at the
     bottom of some pages, and a list of sources at the end of the document.
     Both use the same numbers, so linking mixes them: on printed page 57
     notes 52-54, and on page 66 notes 55-58, stay unlinked. This is the
     known limit "two numbering systems in one document" ([notes](features/notes.md)).
4. **A paragraph is split in two where a line starts with a dash or is
   read in pieces** (printed pages 58, 61, 62, 66). Found in the same dump.
   A line that starts with "—" right after a line that ended short of the
   margin begins a new paragraph, and a line that the OCR engine reported
   as two pieces at slightly different heights becomes two overlapping
   paragraphs instead of one line.

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
