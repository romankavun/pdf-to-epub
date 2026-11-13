# Review: the scan next to what was recognized

After a conversion, *Review…* (⌘R) on the summary screen shows the document
page by page: the page image on the left, the blocks recognized on it on
the right. It is for checking the result before saving; it does not change
the document yet.

## Usage

- **Pages**: the arrows in the toolbar, or ⌘[ and ⌘].
- **Blocks**: every block that starts on the page is outlined on the scan
  and listed as a card: heading, paragraph or illustration (with the
  cropped picture and its caption). Clicking an outline or a card puts that
  block in focus on both sides.
- **Suspicious words** are highlighted in the text, and a block that has
  any is outlined in orange with a count on its card. The toolbar shows how
  many there are in the document.
- **Next Issue** (⌘G) and **Previous Issue** (⇧⌘G) jump between blocks
  with suspicious words, across pages, wrapping around at the ends.
- **Back to Summary** (Esc) returns to the numbers and *Save EPUB…*.

Linked note references appear as the note's label, raised and coloured.

## What counts as suspicious

`SuspiciousWordDetector` (`TextReview` module) flags a word by two rules
that need no dictionary:

| Rule | Example | Typical cause |
|---|---|---|
| Latin and Cyrillic letters in one word | "Журавeль" with a Latin "o" | a look-alike letter from the wrong alphabet |
| A digit with letters on both sides | "сл0во" | a letter read as a digit |

Digits at the edge of a word ("2nd", "3D", "1990-х") are left alone.

## How it is built

Layout analysis records where each block comes from: `DocumentLayout.sources`
holds, for every block, the page it starts on and the area it covers there
(`BlockSource`). `Conversion` carries these and the page files to
`ReviewModel` (`AppModel`), which groups blocks by page, splits their text
into runs with the detector, and owns the page, the selection and the list
of stops for *Next Issue*. The views in `App/` render that state.

## Known limits

- Read-only: no editing of text or block types yet.
- A block is shown on the page where it **starts**. Its outline covers only
  that page's part, and the page it runs onto does not list it.
- The text of notes is not shown, only their labels at the references.
  Unlinked note texts appear as ordinary paragraphs.
- No spelling check yet: a misread word made of plausible letters is not
  flagged. `NSSpellChecker` is planned as a further rule.
- False positives are expected for formulas and codes ("H2O").
- The review is rebuilt each time it is opened and is not saved.
