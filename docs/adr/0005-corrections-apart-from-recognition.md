# ADR 0005: Corrections are kept apart from recognition and find their block by its place on the page

- Status: accepted
- Date: 2026-11-14

## Context

The user corrects the document by hand, which can take sessions, and may
convert the scans again later. `CLAUDE.md` requires corrections to survive
that. Blocks have no identifier that survives: their index changes when a
paragraph is merged or dropped, and note ids are recounted.

## Decisions

1. **Two layers.** The project keeps the pipeline's output (`base`) and a
   `CorrectionSet`. The document that is reviewed and exported is derived with
   `CorrectionSet.applying(to:)` after every change. Nothing in the base is
   edited, so undo is keeping an earlier set, and converting again replaces
   the base only.
2. **A correction names its block by `BlockAnchor`**: the page and the area
   where the block starts. A block is the same block if its start area is on
   the same page and overlaps the anchor by at least half of their union.
   That absorbs the pixel-level shifts of a re-run and does not confuse
   neighbouring lines. Rejected: the index (shifts), a hash of the text
   (changes with every OCR fix, and the corrections change text), a counter
   (shifts like the index).
3. **A text edit stores the recognized text it was made against.** If the
   recognized text has changed, the edit is stale and reported, not applied:
   silently putting an old fix over a better reading would lose the
   improvement. Stale and orphaned corrections are returned as `unapplied`
   and shown to the user.
4. **Text is edited by diff.** The change is the stretch between the common
   start and end of the old and new text, so emphasis and note references
   outside it stay. A note reference is one placeholder character in the
   compared text, so labels, which can change when converting again, play
   no part.
5. **Word replacement is a rule, not a list of edits.** "Replace this word
   everywhere" is one `replaceWord` correction applied to the base text of
   every block and note; it also reaches text read in a later conversion.
6. **Ignored blocks stay visible.** Ignoring removes a block from the document
   but the review keeps showing it (greyed), so the decision can be seen and
   reversed after reopening the project.
7. **Similarity for propagation is geometric** (height, left edge or
   centre), not textual, because that is how a reader tells headings apart;
   headings share no words. Matching blocks are offered, never applied
   silently, and ignoring is never offered.

## Consequences

- A re-run that moves a block by more than half its area orphans its
  corrections; they are counted rather than guessed at.
- `apply` is linear in blocks times corrections; for a 400-page document with a
  few hundred corrections it is instantaneous, and it runs on every change.
