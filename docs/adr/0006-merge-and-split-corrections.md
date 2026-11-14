# ADR 0006: Merging and splitting blocks are corrections applied before edits

- Status: accepted
- Date: 2026-11-14

## Context

[ADR 0005](0005-corrections-apart-from-recognition.md) stores corrections
apart from recognition and finds blocks by `BlockAnchor`. Merging and
splitting change which blocks exist, so edits and types, which are anchored
to blocks, must know the blocks they refer to.

## Decisions

1. **Two new corrections**: `merge(first, with: second)` and
   `split(anchor, at: offset, of: text)`. They are applied first, in the
   order they were made, over the base conversion (`structured(from:)`);
   edits, types and word rules then apply to the resulting blocks.
2. **Identity after a merge**: the merged block is the first block, with the
   second block's areas added as further areas. Its anchor stays the first
   block's start area, so earlier types and edits of the first block still
   find it. Areas on one page are drawn as their union by the review.
3. **Identity after a split**: the cut position in the block's area is
   estimated by the text's share (line boxes are not kept), snapped to the
   join of areas when close. The first part keeps the start of the original
   area, the second starts where the cut falls; each part's anchor is its
   own start area, so each can be typed or edited. The same estimate is made
   when converting again, so anchors stay consistent.
4. **A split stores the text it was made against** and is stale (reported,
   not applied) if the recognized text changed, as edits are. The offset is
   a character offset in the canonical text.
5. **Edits through a merge**: edits of the two blocks are rewritten as one
   edit of the merged block (`from` and `to` joined by a space), so they
   survive. The absorbed block's type is dropped.
6. **A split drops the block's earlier edit and type, and is refused for an
   edited block**: the user's cursor is in the edited text, which cannot be
   mapped back to the recognized text in general.
7. Text edits made after a merge or split are checked against the structured
   text, which is what `ProjectModel` uses as the automatic text.

8. **A note text can be split**: the first part stays the note, the rest
   becomes a paragraph block inserted by its place on the page (page, then
   top edge). Notes themselves are not merged.

## Consequences

- Undo is keeping the earlier set, as before; the project file only gains
  two correction cases, so older projects still load.
- A re-run that moves a block more than half its area orphans the merge or
  split, which is then listed as unapplied.
- A merge that follows a split is not recognized as its inverse; both stay
  in the list.
