# Review: the scan next to what was recognized

After a conversion, *Review…* (⌘R) on the summary screen shows the document
page by page: the page image on the left, the blocks recognized on it on
the right. It is for checking the result before saving and for
[correcting](corrections.md) it: changing a block's type, editing its text,
leaving it out.

## Usage

- **Pages**: the arrows in the toolbar, or ⌘[ and ⌘].
- **Blocks**: every block on the page is outlined on the scan and listed
  as a card, top to bottom: heading, paragraph or illustration (with the
  cropped picture and its caption). Clicking an outline or a card puts that
  block in focus on both sides.
- **Blocks across pages**: a paragraph that runs onto the next page is
  shown on both pages. Each page outlines its own part; the card carries the
  whole text and says that it continues on the next page or from the
  previous one.
- **Notes**: the text of a linked note is shown on the page it is printed
  on, as a *Note N* card with its label, outlined in teal. (A note text that
  nothing refers to stays an ordinary paragraph in the document, and in review.)
- **Suspicious words** are highlighted in the text, and a block that has
  any is outlined in orange with a count on its card. The toolbar shows how
  many there are in the document.
- **Next Issue** (⌘G) and **Previous Issue** (⇧⌘G) jump between blocks
  and note texts with suspicious words, across pages, wrapping around at the
  ends. A block on two pages is one stop, shown on the page it starts on.
- **Corrections**: select a block to change its type, edit its text or
  ignore it, and use *Undo* (⌘Z); the bar below offers the same change for
  similar blocks. See [corrections](corrections.md).
- **Back to Summary** (Esc) returns to the numbers and *Save EPUB…*.

Linked note references appear as the note's label, raised and coloured.

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
  attention*.
- Misspelled words are off by default. The *Spelling* toggle in the toolbar
  marks them with a blue dotted underline and enables their own counter and
  *Next / Previous Misspelling* (⌥⌘G, ⇧⌥⌘G). They never change the issue
  count or the issue navigation. The summary shows their number in a
  separate *For a second pass* section.

The spelling rule picks the language per word by its script (Cyrillic is
checked as Ukrainian, Latin as English), so Ukrainian text with English
fragments works. It skips words of one or two letters, all-capital words,
and a capitalized word that does not begin a sentence (taken for a name).
See ADR 0006.

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
  invented words are flagged, a misread name is not, and there is no ignore
  list yet. It is off for a language with no installed dictionary.
- False positives are expected for formulas and codes ("H2O").
- The review itself is rebuilt each time it is opened; the corrections are
  kept in the [project](projects.md).
