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
- **Quick fix**: clicking a flagged word in the review replaces it with a
  suggestion; this is recorded as an ordinary text edit (see
  [review](review.md#quick-fixes)).
- **Edit Text** (paragraphs, headings, notes) and **Edit Caption**
  (figures) open the text in an editor; *Save Text* is ⌘Return, *Cancel* is
  Esc. A note reference is shown as its label in `⟦ ⟧` brackets: keep the
  brackets to keep the note, delete them to drop the reference.
- **Undo** (⌘Z, toolbar) takes back the last correction, one step at a time.
  The history lasts while the document is open.

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
- No merging or splitting of blocks, no redrawing of a block's region, no
  changing a note's type, no figure to paragraph. Page numbers and running
  headers still have to be ignored one by one (or are left in).
- Chapters follow level 1 headings only; there is no way yet to start a
  chapter elsewhere or merge two.
- Undo history is not saved; reopening a project starts with an empty one.
