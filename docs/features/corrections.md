# Corrections: fixing the document in review

In [review](review.md) the user can change what the pipeline got wrong.
Nothing is overwritten: each correction is recorded on its own and applied
on top of the recognized document, so it can be undone, and it survives
[converting the document again](projects.md).

## Usage

Click a block (on the scan or in the list); buttons appear under its card.

- **Type** (paragraphs and headings): *Paragraph*, *Heading 1-3*, *Ignore*,
  or *Reset to Recognized Type*. A level 1 heading starts a new chapter in
  the EPUB, so the chapters change with it.
- **Ignore** leaves the block out of the document (a page decoration, a stray
  scan). It stays in the review, greyed and marked *Ignored*, with
  *Bring Back* to put it in again. A figure can only be ignored.
- **Edit Text** (paragraphs, headings, notes) and **Edit Caption**
  (figures) open the text in an editor; *Save Text* is ⌘Return, *Cancel* is
  Esc. A note reference is shown as its label in `⟦ ⟧` brackets: keep the
  brackets to keep the note, delete them to drop the reference.
- **Undo** (⌘Z, toolbar) takes back the last correction, one step at a time.
  The history lasts while the document is open.

### Merging and splitting blocks

- **Merge with Next** (paragraphs and headings) joins the next block into
  the selected one: one block with both texts, a space between, and the type
  of the selected block. Use it for a paragraph that the pipeline cut in two
  (a page break it did not recognize, a stray line gap). The next block has
  to be a paragraph or heading too. Edits made to either block are kept.
- **Split at Cursor** (in the editor of a paragraph or heading): put the
  cursor where the block should be cut and press it. The spaces at the cut
  go, each part keeps its emphasis and note references, and each part can
  then get its own type. The text has to be unchanged in the editor, and
  the block must not have been edited or touched by *Replace Everywhere*,
  because the cursor position is read in the recognized text. Save or undo
  the edit first.
- Both are steps of undo. A merged block is shown on all the pages it
  covers; the review marks it as continued like a paragraph across pages.
  To take back a merge later, split the block where the join is.

### Applying a correction to similar blocks

After a paragraph becomes a heading (or the other way round, or the level
changes), the bar below the review offers the same type for blocks that
look like it: *Apply to All*, *Choose…* (a list with a switch per block, with
page and the start of the text), or *Not Now*. One step of undo takes the
whole group back. Blocks the user already decided about are never offered.

"Looks like" is judged from the page only: the same height (within 25 %)
and the same left edge or centre line (within 2 % of the page width), among
blocks of the type the changed block had. Text is not compared. Ignoring is
never offered to other blocks, because a wrong match would drop text.

After a text edit that fixed exactly one word, and that word stands
elsewhere, the bar offers *Replace Everywhere*: every whole word (no letter,
digit or apostrophe against it) in blocks, captions and notes. It is
recorded as one rule and applies to the whole document, including text read
later if the document is converted again.

## How it is built

- `Corrections` module (pure, no UI): `CorrectionSet` holds the user's
  decisions as values (`retype`, `edit`, `replaceWord`) and applies them to
  a `Conversion`, giving the document to export, the ignored blocks and the
  corrections that found nothing to act on. `SimilarBlocks` finds
  candidates; `WordReplacement` recognizes a one-word fix.
- `merge` and `split` are corrections too and are applied first, in the
  order they were made ([ADR 0006](../adr/0006-merge-and-split-corrections.md));
  edits and types then see the blocks as they are after them.
- A correction finds its block by where it lies on the scan (`BlockAnchor`,
  [ADR 0005](../adr/0005-corrections-apart-from-recognition.md)).
- An edit stores the recognized text it was made against and the new text.
  Applying it replaces only the stretch between the common start and end of
  the two, so emphasis in the rest of the block and note references outside
  the change stay as they were.
- `ProjectModel` (`AppModel`) keeps the base conversion and the set, derives
  the corrected conversion after every change, keeps the undo history and
  saves; `ReviewModel` exposes the actions and the proposals to the views.

## Known limits

- Editing flattens nothing, but it cannot add formatting: new text takes the
  style of the text it replaces.
- A note reference typed in the editor has nothing to point to and is
  dropped; a deleted one is gone until the text is edited back.
- A note that loses its last reference (the block was ignored or edited) is
  left out of the EPUB.
- No redrawing of a block's region, no
  changing a note's type, no figure to paragraph. Page numbers and running
  headers still have to be ignored one by one (or are left in).
- Chapters follow level 1 headings only; there is no way yet to start a
  chapter elsewhere or merge two.
- Where a block is cut is estimated from the text's share of the block's
  area, so the second part's outline on the scan can be a little off; it
  snaps to the join when the cut is near the join of two merged blocks.
- Undo history is not saved; reopening a project starts with an empty one.
