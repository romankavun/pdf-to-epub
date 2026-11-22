# Paper scans: crop, clean and level pages before recognition

The app and [`pagescan`](pagescan-cli.md) notice when a document is a paper
scan rather than clean pages and prepare its pages before
anything reads them. Nothing has to be switched on. Where the prepared
pages live and why the review shows them is in
[ADR 0010](../adr/0010-prepared-pages-are-the-project-pages.md).

## What it does

All of it lives in the `Preprocessing` module, works on pixels only, and
uses no Vision.

1. **Input profile** (`InputProfile`). Up to nine pages spread over the
   document are sampled. A page counts as scanned when it lies on a scanner bed
   (a frame of one exact colour on every side) and its paper is grainy: at
   least 15 % of the page's pixels are a few shades off the bed colour.
   Scanned pages measured 21-48 %, clean pages at most 7 %, because a
   clean page's background is one exact colour. The document is a scan when
   more than half the sample is; then every page is prepared, otherwise
   none.
2. **Page crop** (`PageCrop`). The page is the rectangle of rows and
   columns where more than 4 % of the pixels differ from the bed colour;
   the bed must show on every side (at least 2 % of the image). A margin of
   2 % of the page width is kept so a curled edge is not cut. A dark cover
   on the bed is cropped the same way.
3. **Background cleanup** (`BackgroundCleaner`).
   - *Levels*: the paper's brightness is measured in 32 px tiles (the 90th
     percentile of each tile, ignoring tiles more than 40 shades darker
     than the page's paper) and interpolated between tiles, so a gradual
     gutter shadow or uneven yellowing is followed. Each pixel is scaled so
     that anything within 30 shades of the local paper turns white. That
     removes show-through, which is faint grey (220-250 on the sample)
     while the body of letters is far darker; only their lightest
     anti-aliased rim goes with it. The three channels of a pixel are scaled by the
     same factor, so a link-coloured note marker keeps its hue and is still
     found by colour.
   - *Debris*: grey or dark shapes touching the image's border (gutter
     shadow, bed beyond the page edge), long thin shapes in the outer 5 %
     band (page edges, ticks) and anything in a corner of that band are
     painted white. Letter-sized shapes in the band, such as the page
     number and the running line, are kept.
4. **Deskew** (`Deskew`). The tilt is found by projection profiles: ink is
   summed along lines of each trial angle (every 0.25° within ±5°, then
   every 0.05° around the best), and the angle at which the sums change
   most sharply between lines wins. The page is rotated by bilinear
   sampling onto a canvas grown to hold it, with white corners. Tilts under
   0.1° are left alone.

The prepared page is written as a PNG, which is lossless. In the app the
prepared pages go into the project's `pages/` folder and the review shows
them, so the boxes line up; see [projects](projects.md). With `pagescan`,
`--prepared-pages <folder>` keeps them for inspection.

## Measured on the sample

A 23-page flatbed scan of a commercial work (not in the repository):
pages 2, 3, 6, 7, 8 and 9, the problem pages, converted with
`pagescan --language en`. Misspelled share is words flagged by
`NSSpellChecker` (English) in the EPUB's text.

| Step | Words | Misspelled | Paragraphs | Figures |
|---|---|---|---|---|
| Before (no preprocessing) | 555 | 25.4 % | 16 | 4 |
| Crop | 1112 | 1.9 % | 63 | 2 |
| + cleanup | 1245 | 1.9 % | 69 | 0 |
| + deskew | 1246 | 1.9 % | 77 | 0 |

- Before, four of the six pages became whole-page illustrations and their
  text was lost. After cleanup none is. Show-through on page 3 was what
  kept it a picture after cropping.
- Deskew: page 8 measured -2.4° and page 3 -2.9° before, 0.0° and -0.2°
  after. On page 8 alone the misspelled share went from 1.2 % to 0.9 % and
  a false heading disappeared. The document's lines are curved towards the
  gutter, so one angle cannot level them completely.
- Pages 1-3 (cover and two text pages): before, no cover and two figures;
  after, the cover is found and there are no figures.
- The 24 remaining flagged words are mostly proper names and words split
  by a line-end hyphen that layout analysis did not rejoin; two or three
  are recognition errors.
- **Upscaling was measured and not added**: the six prepared pages enlarged
  2× (`sips`) gave 1246 words and 2.0 % misspelled against 1.9 % at their
  own size. At this resolution (text about 20 px tall) Vision gains nothing
  from more pixels.
- Clean pages: 12 pages from the four sample sets are profiled
  as clean pages and left untouched; the golden pages and every existing
  test are unchanged.

## Known limits

- The bed must be one exact colour (a scanner that saturates to white). A
  bed of noisy grey, a scan with a dark lid, or a page that fills the image
  is not cropped; cleanup and deskew still run if the document profiles as a
  scan, which it then probably does not.
- Clean pages inset on a white page (a card with white margins) have no
  grain and are not cropped, so picture detection still takes the card for
  an illustration.
- Two-page spreads are not split.
- Lines that curve towards the gutter are levelled on average only; there
  is no dewarping.
- Cleanup also whitens the lightest tones of photographs on a scanned page,
  and the figures cut from it.
- Preparation runs once, when a project is created; an older project made
  from unprepared scans is not prepared by converting it again (see the ADR).
- In the app, preparing has no progress bar of its own: it happens page by
  page inside *Converting*. On the sample (pages about 1500x2600 px) the
  profile took 0.27 s for six pages and preparing about 0.09 s per page,
  release build; Vision's recognition dominates.
