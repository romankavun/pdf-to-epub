# Backlog

Known defects and planned improvements that are not built yet. Each item
becomes a test first (see the TDD rule in `CLAUDE.md`) and is removed from here
when fixed. Page numbers are the printed numbers in the user's sample set
about Ukrainian folk demonology; do not copy its text here.

## Defects found by hand in the review screen

Found on 2026-11-13 while checking the first manual run. In the review screen
the area of every recognized block is outlined on the scan; the items below are
content that is on the page but has no outline, so it is most likely missing
from the result (to be confirmed against the model, not just the overlay).

1. **Paragraph at the top of a page is not captured** (printed pages 65, 66).
   The first lines of the page, a paragraph that continues from the previous
   page, have no block. Check whether the continuation is merged into the
   previous page's block (then only the overlay is wrong) or dropped.
2. **A list is not captured** (printed pages 62, 63). Items numbered `1)`,
   `2)`, `3)`, set in a narrower, indented column, have no blocks. Lists are in
   scope for v1 (`CLAUDE.md`) but layout analysis has no list rule yet.
3. **The first note under the rule is not captured** (printed page 57, note
   50). The notes after it on the same page are. Look at what separates the
   first note from the rule: the marker search, the note-start detection, or
   the strip of crops that reads the label.

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
