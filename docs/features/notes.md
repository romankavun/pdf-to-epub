# Notes: references, note texts and linking

Footnotes and endnotes of the source document become EPUB pop-up footnotes: the
reference in the text is a link, and the note's text is written at the end
of the chapter that refers to it (see [EPUB export](epub-export.md)).

Nothing has to be switched on: `pagescan` and `DocumentConverter` do this for
every page. The design and the measurements behind it are in
[ADR 0003](../adr/0003-notes-by-colour-and-sequence.md) and, for documents with
two kinds of notes numbered apart, [ADR 0004](../adr/0004-two-numbering-systems.md).

## What counts as a note marker

The clean-page source the sample sets were captured from draws note markers as blue
links. `NoteMarkerDetector` (`LayoutAnalysis`) finds them from pixels:

- a pixel is link-coloured when blue exceeds red and green by more than 50;
- link-coloured pixels on one line form runs (gaps wider than 0.6 of the
  line's link ink height separate them);
- a run is a marker when it is at least 0.4% of the page height tall, at
  most four times wider than that ink height, and has dark, colourless text
  within one ink height to its left or right.

So a contents entry (blue, but with no dark text beside it) and a long blue
web address are left alone and stay ordinary text.

## How the text is read

1. Marker boxes are painted in the page colour before the page is
   recognized, so the words around a marker are read as if it were not
   there.
2. The labels are read separately: the markers are cut out, turned into
   dark-on-white, enlarged three times and laid out in a row (at most twelve
   per row); anything not read that way is retried alone.
3. Each recognized line carries word boxes. A marker is placed after the
   last word whose centre is to its left. Punctuation that follows a
   reference stays attached to it.

## Reference or note text

- A marker **before the first word of a line that starts a paragraph** makes
  that paragraph the text of a note. It leaves the body.
- Endnotes are often set as a **numbered list**: a list number, then the
  note's own label, then the text, with a hanging indent. A single list
  number before the marker (`12.`, `3)`, also misread as `IO.` or `39-`)
  does not count as a word and is dropped. In such a note the indented lines
  continue it, and it ends at the next marker or at an unindented line
  without one. At the top of a page, a list number followed by a marker
  always starts a note.
- Any other marker is a reference, including one that opens a line in the
  middle of a paragraph (it belongs to the last word of the line above).
- A marker that opens a line and is followed by `.`, `,` or another closing
  punctuation mark (or by a bullet, which is how a lone full stop is often
  read) is never a note label: no note starts that way. The engine
  sometimes reports the end of a line as a line of its own, starting right
  at the erased marker. Such a line continues the block above it.
- Markers inside pictures are ignored.

## Labels

Labels of note texts are repaired run by run (a run is a series of
consecutive note texts): the numbering kind (`1 2 3`, `I II III`, `a b c`)
and sequence that most readings agree on win, look-alikes are resolved
(`I0` is 10, Cyrillic `П` is `II`), unread labels are filled in, and a run
with nothing readable continues the previous run. When numbering restarts
inside a run, readings are kept and only gaps are filled.

## Linking

A reference is linked by its own label:

| The reference's label | Linked to |
|---|---|
| is the number of one note | that note |
| is the number of several notes, some after the reference | the reference's own note (see below); without one, the furthest of them |
| is the number of several notes, all before the reference | the one nearest to where the references before it have got to |
| could not be read, or no note carries it | the next note in order |

Several notes carry one number when numbering restarts in every chapter, or
when a document numbers two kinds of notes apart: explanatory notes after each
section, say, and a list of cited sources at the end of the document. A
reference's **own** note is the nearest note after it that

1. is in the first group of notes after the reference (notes with no
   reference between them; a note's later paragraphs between them do not
   count), or comes after the document's last reference, where notes collected
   at the end are; and
2. has no later reference before it with the same number: a note after a
   section is referred to just before it appears, so an earlier reference
   with that number cites something else.

A reference with no own note repeats an earlier citation, and those go to
the furthest note: the list cited again and again is the one at the end.

Linking by label is what makes documents that **cite sources** work: there the
same note is referred to several times and not in sequence. The fallback to
order suits notes referred to once each, in sequence, and is a guess
otherwise. This covers notes at the end of each section and notes collected
at the end of the document alike.

Nothing is dropped silently:

- a reference with no note left to link to stays in the text as its label;
- a note text nobody refers to stays in the body as a paragraph that starts
  with its label.

`pagescan` prints both counts, and `DocumentConverter.analyze` returns them in
`Conversion`.

## Results on the sample sets

| Document | Notes linked | References without a note | Notes without a reference |
|---|---|---|---|
| A (letters, notes at section ends) | 18 | 0 | 1 |
| B (roman numerals, notes at section ends) | 61 | 0 | 6 |
| C (numbers; explanatory notes after sections and sources listed at the end, numbered apart) | 500 | 10 | 8 |
| D | 1 | 0 | 0 |

All four outputs pass `epubcheck` with no messages. The links were not
checked one by one against the documents; the counts say how many were made, not
that each one is right. In document C, all 71 linked explanatory notes are
referred to from at most ten pages before them. Of its eight unlinked
notes, three are explanatory notes whose own reference was misread or merged
with a neighbouring marker; the rest are in the list of sources.

## Known limits

- **Colour only.** Markers must be drawn in a distinctly blue link colour.
  Paper scans and other reader themes are not handled.
- **Labels are short and OCR is weak on them.** The sequence repairs most
  errors, but a document whose notes are not numbered in sequence gets labels as
  read, or `*` where nothing was read.
- **Two numbering systems** are told apart only by where their notes are.
  Two lists with the same numbers collected in one place are not told
  apart, and when both systems start at the same number close together,
  the first references go to the nearer note.
- An explanatory note whose **own reference was misread** stays unlinked
  rather than taking a citation with the same number.
- **Two markers side by side** may be detected as one, whose label is both
  numbers run together (`21852`); neither note is linked to it.
- A reference label that is **misread as the number of another note** is
  linked to that other note. Nothing in the page tells the two apart.
- An unread reference label is linked to the next note in order, which is
  wrong when that reference was a repeated or out-of-sequence citation.
- A **note text of several paragraphs** keeps only its first paragraph; the
  rest stay in the body as ordinary paragraphs. (In a list with a hanging
  indent the paragraphs of one note are joined instead.)
- A bare marker at the very top of a page, on an unindented line, is read as
  a reference carried over from the previous page, not as a new note.
- A full stop directly after a reference is occasionally read as a bullet;
  it is turned back into a full stop only in that position.
- A reference placed before closing punctuation ends up before it even when
  the word box suggests otherwise; the order of a reference and the
  punctuation next to it is not guaranteed.
- A heading such as "Notes" above a list of endnotes stays in the document as a
  heading with nothing under it.
