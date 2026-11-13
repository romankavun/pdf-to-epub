# Illustrations, captions and the cover

Pictures on a page are found from the page's pixels, cut out, embedded in the
EPUB as figures at their place in the text, and given their caption. Text
that the OCR engine reads *inside* a picture (lettering on a poster, a
diagram, the cover) is dropped instead of turning into body text or headings.

Nothing has to be switched on: `pagescan` and `DocumentConverter` do this for
every page.

## How a picture is found

`PictureDetector` (`LayoutAnalysis`) works on a `PageBitmap`, a plain array
of pixels, so it is tested on pages built in code.

1. The page background is the most common colour on the page border.
2. The page is cut into horizontal **bands**: runs of consecutive rows that
   contain any non-background pixel. Lines of text are separated by blank
   rows, so each gives a low band.
3. A band at least 5% of the page height (about three body lines) is a
   picture, **unless** at least 70% of its ink lies inside recognized text
   lines. That exception keeps a large title whose lines touch from being
   taken for a picture, while lettering inside a real picture covers only a
   small share of its ink.
4. The picture's box is the band's rows and the columns its ink spans.

`ImagePictureExtractor` (`Conversion`) loads the page file, runs the
detector, and crops each box from the original image as PNG at full
resolution. Images are named `figure-001.png`, `figure-002.png`, ... in
reading order.

## Where the figure goes, and its caption

`LayoutAnalyzer` receives each page as `PageContent`: lines plus pictures.

- A line whose centre lies inside a picture is discarded.
- A picture ends the paragraph before it and becomes a `figure` block.
- The block right under a picture, on the same page, becomes its caption if
  either
  - it starts with a figure label: `Fig. 3`, `Figure 12`, `Мал. 27`,
    `Рис. 5`, `Іл. 2` (any case), or
  - the vertical step to the text that follows it is at least 2.75 typical
    line steps, clearly more than the gap between paragraphs.
- A heading under a picture is never a caption.

## Cover

If the tallest picture on the **first page** is at least half the page high,
it becomes the cover (`cover.png`, marked `cover-image` in the package), and
the first page contributes nothing else. Otherwise the document has no cover and
first-page pictures are ordinary figures.

## Results on the sample sets

| Document | Pages | Figures | With caption | Cover |
|---|---|---|---|---|
| A (non-fiction, photos and diagrams) | 148 | 19 | 9 | yes |
| B (history, archive photos) | 161 | 32 | 26 | yes |
| C (fiction) | 156 | 0 | 0 | yes |
| D (non-fiction) | 380 | 4 | 0 | yes |

All four outputs pass `epubcheck` with no messages. Before this feature,
document A alone had several bogus chapters made of text inside pictures.

## Known limits

- **Text beside a picture** is not handled: the whole band, text included,
  becomes one image. Pictures are expected to span the column.
- **Pages of text embedded as images** in the source file (a half-title, a
  publisher's page on a white ground) are kept as full-page figures. Their
  ground differs from the page background, so they look like pictures.
- **A table drawn as text** under a picture, or any multi-column block, is
  read row by row and comes out garbled; tables are out of scope.
- A caption without a label is recognized only when text follows it on the
  same page. At the bottom of a page it stays a paragraph.
- An ordinary paragraph under a picture that is followed by a section break
  (extra space) is taken for a caption.
- Captions are plain text; a bold label is not preserved.
- `alt` text is empty: nothing better than the caption is known.
- The cover is embedded and declared, but there is no separate cover page in
  the reading order. Reading systems show it in the library.
- Figures are stored as PNG. A document with many photographs grows large
  (document B: 17 MB).
- Line drawings on the page's own background with blank rows inside are
  split into several pictures or missed if each part is low.
