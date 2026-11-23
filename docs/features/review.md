# Review: the scan next to what was recognized

After a conversion, *Review…* (⌘R) on the summary screen shows the document
page by page: the page image on the left, the blocks recognized on it on
the right. It is for checking the result before saving and for
[correcting](corrections.md) it: changing a block's type, editing its text,
leaving it out.

For a scanned page, the page shown is the prepared one, cropped, cleaned and
levelled, because that is the image the blocks were found on; see
[scanned pages](scan-preprocessing.md).

## Usage

- **Pages**: the arrows in the toolbar, or ⌘[ and ⌘].
- **Blocks**: every block on the page is outlined on the scan and listed
  as a card, top to bottom: heading, paragraph or illustration (with the
  cropped picture and its caption). Clicking an outline or anywhere on a
  card, text included, puts that block in focus on both sides.
- **Blocks across pages**: a paragraph that runs onto the next page is
  shown on both pages. Each page outlines its own part; the card carries the
  whole text and says that it continues on the next page or from the
  previous one.
- **Notes**: the text of a linked note is shown on the page it is printed
  on, as a *Note N* card with its label, outlined in teal. (A note text that
  nothing refers to stays an ordinary paragraph in the document, and in review.)
- **Suspicious words** are highlighted in the text, and a block that has
  any is outlined in orange with a count on its card.
- **Text probably misrecognized**: a block whose words are largely unknown
  to the dictionary is outlined in red and says so on its card; the tooltip
  gives the numbers ("9 of 31 words are unknown"). See
  [below](#text-probably-misrecognized).
- **Page may contain text that was not recognized**: a page whose only
  content is an uncaptioned figure over the text area is flagged on the
  figure's card, outlined in red. See [below](#pages-that-may-have-lost-their-text).
- **Issues** are all three: blocks with suspicious words, misrecognized
  blocks and figures that may hide a page of text. The toolbar shows how many
  start on the page being viewed and how many there are in the document
  ("Issues: 1 on this page, 51 in the document"), or "Issue 2 of 51" while one is
  selected.
- **Next Issue** (⌘G) and **Previous Issue** (⇧⌘G) jump between issues,
  across pages, wrapping around at the ends. A block on two pages is one
  stop, shown on the page it starts on.
- **Corrections**: select a block to change its type, edit its text or
  ignore it, and use *Undo* (⌘Z) and *Redo* (⇧⌘Z; a new correction drops what could be redone; both are off while a text is being edited); the bar below offers the same change for
  similar blocks. See [corrections](corrections.md).
- **Styles** (⌃⌘S) shows the styles sidebar: every style the document was
  recognized with. See [below](#the-styles-sidebar).
- **Back to Summary** (Esc) returns to the numbers and *Save EPUB…*.

Linked note references appear as the note's label, raised and coloured.

## The styles sidebar

*Styles* in the toolbar (⌃⌘S) shows a sidebar on the left with every
[style](styles.md) of the document, so a rule that went wrong the same way on
many pages stands out without reading every page (design:
[proposal](../proposals/style-overview.md)). It is off every time the review
opens; while it is shown the window is at least 1180 pt wide. For a project
saved before styles were kept (format version 1) *Styles* is disabled, and its
help says to *Start over* to see them.

- **The list** groups styles by type: Heading 1, 2, 3…, paragraphs, figures
  and captions, note texts, page furniture (running headers and page
  numbers). Each row has the style's colour, its name (type and deciding
  rule, numbered when two styles share both: "Paragraph (2) · paragraph")
  and its number of blocks; the tooltip says what sets it apart. A style
  that is [probably wrong](styles.md#probably-wrong) has an orange warning
  triangle before its count, and its reason in the tooltip.
- **Styles describe recognition, not the corrections.** A retyped or
  ignored block stays in the style it was recognized with, so the list never
  reshuffles while you work.
- **Selecting a style** replaces the block list with the style: for a
  probably wrong one, first its warning ("Probably wrong. At the top or
  bottom edge of the page, on 4 pages: probably a running header taken for a
  heading."); then what sets it
  apart from body text ("1.6 × taller than the text, centred"), its deciding
  rule, the number of blocks and how many of them were corrected, the pages
  (as runs, "3–5, 9"), then six examples, crops of the page image with their
  page numbers. The examples come from pages spread across the document: with
  six pages or more, one from each of six pages evenly spaced from the first
  to the last; with fewer, one from every page in turn. *Show All N* shows a
  crop of every block. A corrected block's crop says *corrected*, an ignored
  one's *Ignored*. A block counts as corrected when a type, an edit, a merge
  or a split names it; a word replaced everywhere does not count.
- **On the scan** the style's blocks on the page in view are outlined in its
  colour, page furniture included; other outlines fade. Paging keeps the
  style.
- **Clicking a crop** goes to its page, selects its block (for a block
  merged into the one before, the merged block; for page furniture, nothing)
  and brings back the block list. The style is no longer selected.
- **A selected block** shows a button with its style's name; it opens the
  sidebar on that style. A block made by a split was never recognized, so it
  has none.
- While a style is shown, the issue and spelling controls are hidden: they
  act on the block list. Undo and redo stay.

`ReviewModel` (`AppModel`) groups the base conversion's block styles with
`StyleGrouping` once, when the review opens, and keeps the sidebar's state:
whether it is shown, the selected style, the examples, the outlines on the
page and the corrected blocks of each style (recomputed after every change).
The views only draw it.

## Quick fixes

A flagged word is a link: clicking it opens a row of suggestions inside the block's card (a popover
could not point at the clicked word), and
choosing one replaces the word as an ordinary text correction (undoable; if
the same word stands elsewhere, replacing it everywhere is offered). *Edit
Text…* in the row opens the whole block for editing, and *Ignore This Word*
stops flagging that word (in any case) everywhere in the document. Ignored words
are saved in the [project](projects.md) (`ignored-words.json`), apart from the
corrections: they are not undone and survive closing the app and converting again.

- For a mixed-script word the suggestion swaps look-alike letters for the
  word's own alphabet ("Журавeль" with a Latin "o" becomes "Журавель"); for a
  digit it offers the letter it resembles ("сл0во" becomes "слово"). These
  need no dictionary.
- For a misspelling the suggestions come from the system spell checker.
- Misspelled words are clickable only while *Spelling* is on.

A click anywhere on a block's card selects it. Text can be selected with the
mouse once the block is selected; a hovered card is lightly highlighted.

## What counts as suspicious

`SuspiciousWordDetector` (`TextReview` module) flags a word by two rules
that need no dictionary and a third that uses the system spell checker:

| Rule | Example | Typical cause |
|---|---|---|
| Latin and Cyrillic letters in one word | "Журавeль" with a Latin "o" | a look-alike letter from the wrong alphabet |
| A digit with letters on both sides | "сл0во" | a letter read as a digit |

| Not in the dictionary | "докмент", "wrod" | a letter lost or misread, with only plausible letters |

Digits at the edge of a word ("2nd", "3D", "1990-х") are left alone.

The first two rules point to an OCR misreading and have priority: they are
the **suspicious words**. The spelling rule is kept apart, because it is far
noisier (names, dialect, archaic words):

- Suspicious words are highlighted in orange, outlined, counted in the
  toolbar and visited by *Next Issue*; the summary lists them under *Needs
  attention*, and clicking the number opens the review at the first one.
- Misspelled words are off by default. The *Spelling* toggle in the toolbar
  marks them with a blue dotted underline and enables their own counter and
  *Next / Previous Misspelling* (⌥⌘G, ⇧⌥⌘G). They never change the issue
  count or the issue navigation. The summary shows their number in a
  separate *For a second pass* section; clicking the number turns *Spelling*
  on and opens the review at the first one.

The spelling rule picks the language per word by its script (Cyrillic is
checked as Ukrainian, Latin as English), so Ukrainian text with English
fragments works. It skips words of one or two letters, all-capital words,
and a capitalized word that does not begin a sentence (taken for a name).
See ADR 0007.

## Text probably misrecognized

On a poor scan OCR returns near-words ("thc", "rcady") throughout a block.
Each is only a misspelling, which the review keeps off by default, and
none is an OCR suspect, so word rules alone left such a document looking clean:
on a garbled scanned page the toolbar used to read "Suspicious words: 1" on
every page (the one OCR suspect in the whole document, while about a fifth of
all words were unknown to the dictionary).

The block rule counts, per block or note text, the words the spelling rule
judges (the same skips: short words, names, acronyms, words with digits) and
how many of them the dictionary does not know
(`SuspiciousWordDetector.SpellingTally`, `TextReview`). A block is
**probably misrecognized** when at least **8** words were judged and
**more than 20 %** of them are unknown. Only words in the document's own
language (`DocumentMetadata.language`: `en` or `uk`) are counted: a Ukrainian
document's German or English fragments are unknown by nature, not misread. A
word the user ignored counts as known. The rule needs a dictionary; without
one it never fires.

The threshold comes from measurements with the system dictionaries
(blocks with at least 8 judged words):

| Sample | Blocks | Median unknown share | Blocks above 20 % |
|---|---|---|---|
| Garbled English scanned document (23 pages) | 69 | 0.23 | 40 (58 %) |
| Clean English pages | 32 | 0.03 | 0 |
| Ukrainian clean-page document, mostly modern prose | 744 | 0.03 | 4 (0.5 %) after the language filter |
| Ukrainian clean-page document with dialect quotes and Russian references | 956 | 0.04 | 100 (7 %) after the language filter |

20 % catches most of the garbled blocks and none of the clean English ones;
a lower threshold adds many Ukrainian false alarms, a higher one loses half
the garbled blocks. The minimum of 8 words keeps short headings, where one
name is already a quarter of the words, out of it.

The summary lists *Blocks with text probably misrecognized* under *Needs
attention*; the number opens the review at the first issue.

## Pages that may have lost their text

When picture detection takes a whole scanned page for an illustration, its
text never reaches OCR and the document silently misses a page. A page is
flagged when its only content is one figure that has no caption and covers
at least **60 %** of the document's text area. The text area is where the
document's text blocks and notes lie: the 5th to 95th percentile of their
edges, so a scan with wide margins gets a small one; with fewer than three
text blocks it is the whole page. A lost text page on the garbled sample
covers 0.71 to 1.0 of it.

The summary lists *Pages that may have lost their text* under *Needs
attention*, and *Next Issue* stops at the figure. Giving the figure a
caption or ignoring it answers the warning. A real full-page illustration
without a caption is flagged too (two pages of 148 in one clean-page
document, five of 161 in another, one of which did hide a line of text).

## How it is built

Layout analysis records where each block comes from: `DocumentLayout.sources`
holds, for every block, the area it covers on each page it touches
(`BlockSource`: a starting `PageArea` and its continuations), and
`DocumentLayout.noteSources` does the same for the text of every linked note.
`Conversion` carries these and the page files to `ReviewModel`
(`AppModel`), which places every part on its page, splits the text into runs
with the detector, and owns the page, the selection and the list of stops
for *Next Issue*. Items are identified by `ItemID` (`.block(index)`,
`.note(id)` or `.ignored(index)`), the same on every page they appear on.
It takes a `ProjectModel`, which holds the base conversion and the
corrections, and rebuilds the pages from the corrected document after every
change, keeping the selection on the same block. The views in `App/` render
that state.

## Known limits

- A block on two pages shows its whole text on both cards: where the page
  break falls inside the text is not recorded. A suspicious word in the
  second part is reached through the block's stop on its first page.
- The spelling rule trusts the system dictionaries: dialect, archaic or
  invented words are flagged and a misread name is not. *Ignore This Word*
  helps with the noise. The rule is off for a language with no installed dictionary.
- *References without a note* and *Notes without a reference* on the summary
  are numbers only: layout analysis does not record where they are, so they
  cannot open the review at the problem yet.
- False positives are expected for formulas and codes ("H2O").
- The misrecognized-text rule flags blocks in another language written in
  the document's own script (Russian quotes in a Ukrainian document), dialect and
  archaic text: the dictionary cannot tell them from misreadings. Ignoring
  the words brings the block under the threshold. A garbled block with fewer
  than 8 judged words is not flagged.
- A full-page illustration without a caption is reported as a page that may
  have lost its text, and so is a scanned cover the converter did not take
  for the cover.
- The review itself is rebuilt each time it is opened; the corrections are
  kept in the [project](projects.md).

## Merging and splitting

A selected paragraph or heading offers *Merge with Next*; the editor offers
*Split at Cursor*. See [corrections](corrections.md) for what they do and
their limits. A merged block that covers several places is outlined in each
of them (areas on one page are drawn as one).
