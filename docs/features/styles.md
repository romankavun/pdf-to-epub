# Styles

A **style** is a group of blocks that look alike on the page and were given
the same type for the same reason. Styles show what recognition made of a
document at a glance: when a rule is wrong for a document it is usually
wrong the same way on every page, and that shows up as one odd style. They
are the data behind the style overview of the review (design:
[proposal](../proposals/style-overview.md), issue #31). This page covers the
data layer; the overview itself is not built yet.

## Block styles

Layout analysis gives every block, every linked note text and every line of
page furniture a **block style** (`BlockStyle` in `LayoutAnalysis`), kept in
`DocumentLayout.styles` and `Conversion.styles`:

| Feature | Measured as |
|---|---|
| Deciding rule | Why the block got its type; see below |
| Line height | Median height of its lines, as a multiple of the document's median line height |
| Ink | Mean ink density of its lines, as a multiple of the document's typical line ([ADR 0006](../adr/0006-body-size-headings.md)); none when the page was not measured |
| Alignment | `centered` (clear of both edges of the text column by at least 5% of its width, middle within 4% of the page width of the column's), `right` (clear of the margin by a fifth of the column, ending at the right edge), `indented` (first line right of the margin), else `margin` |
| Width | Of its area on its first page, as a share of the text column (margin to the median right edge of the lines) |
| Zone | `top` when its area ends above where the text of a page usually starts (the median top of a page's first line) plus half a line, `bottom` when it starts below where the text usually ends (the median bottom of a page's last line) less half a line, else `body`; the first and last lines of an ordinary page are in the body, and a block that runs onto the next page is always `body` |
| Lines | Number of lines, over all pages |
| Space above, below | Step from the line before and to the line after, in median line steps; none at a page edge or under a picture |
| Under a picture | The block, or a figure's caption, stands right under a picture |
| Opens with a note label | The block starts with a note marker |

A figure with a caption is measured as its caption; a figure without one by
the picture's place, with no lines. A block that runs onto further pages is
measured over all its lines and placed by its first page.

### Deciding rules

| Rule | Given to |
|---|---|
| `largerThanText` | A heading at least 1.5 times taller than the text |
| `bodySizeBold` | A heading at body size in heavier ink |
| `bodySizeCentered` | A heading at body size, centred, short, set apart by blank lines |
| `captionByLabel` | A figure whose caption opens with "Fig. 3", "Мал. 27" and the like |
| `captionByGap` | A figure whose caption is told apart by the space below it |
| `picture` | A figure without a caption |
| `noteText` | A block that opens with a note label; an unlinked one stays a paragraph with this rule |
| `paragraph` | Anything else |
| `runningLine` | Page furniture that repeats at the top or bottom edge |
| `pageNumber` | Page furniture that is a page number |

## Page furniture

Running headers, running footers and page numbers are left out of the
document as before, but kept as **page furniture** (`PageFurniture`): page,
box, text and block style, in page order, top to bottom. Nothing puts them
back into the document yet.

## Grouping

`StyleGrouping.styles(blocks:blockSources:noteSources:styles:)` in the
`Styles` module groups everything into styles, deterministically: blocks
fall into one style when they share

- the type (heading level, paragraph, figure, note text, page furniture) and
  the deciding rule;
- the line-height bucket: body text from 0.75 to 1.35 times the document's
  median line, larger type in steps of 1.5 above that, small print in steps
  of 1.5 below it;
- the ink bucket: regular from 0.7 to 1.35 times the typical line, heavy
  above, light below. Bold headings (`bodySizeBold`) are not split by ink,
  as their rule already says they are bold;
- alignment, zone, full width or not (80% of the column), one line or
  several, under a picture or not, opening with a note label or not.

A single line never counts as smaller or lighter than the text: its box
depends on its letters (a page number's digits have no descenders and come
out at 0.5 to 0.8 of a line), so only several lines make small print.
Spaces above and below are measured but do not split styles: a paragraph at
the top of a page is no different from one in the middle.

Styles come in order of first appearance (page, then top), which is also
their **palette index**, so a project always gets the same colours. A
style's name is its type and deciding rule; when two styles share both they
are numbered in order of first appearance ("Paragraph 2 · paragraph"). Each
style lists its members (blocks, notes, page furniture by index), its pages
and its typical look (the median of each measurement). Styles are computed
from the recognized document, not the corrected one.

`pagescan --styles` prints them ([pagescan](pagescan-cli.md)).

## Storage

`project.json` keeps the block styles and page furniture from format version
2 ([projects](projects.md)). A version 1 project opens without styles:
`Conversion.styles` is `nil`, not empty, and cannot be recomputed since the
recognized lines are not kept.

## Tuning on the sample sets

The thresholds were tuned on the four clean-page sample sets (148 to 380
pages each) with `pagescan --styles`. With them the sets give 33, 40, 38
and 29 styles; page numbers fall into one or two styles per set. A first cut
with finer buckets (steps of 1.2 for line height and 1.15 for ink, regions
fixed on the page) gave 100 to 200, mostly body text and page numbers split
by measurement noise:

- the median line of body paragraphs measured either about 0.90 or 1.00 of
  the document's, depending on the letters, across a bucket edge;
- the mean ink of body paragraphs spreads from 0.85 to 1.25;
- single lines without descenders (page numbers, short words) measure 0.5 to
  0.8 of a line;
- full-width single lines just short of both edges looked centred;
- the last line of a full page reached into the bottom band of the page.

What still splits a type and rule is layout: one line or several, at the
margin or indented, full width or not, centred dialogue, single heavy lines,
lines below where the text of a page usually ends. Headings larger than the
text often come one per style, as each size is set once (a title page).

## Known limits

- OCR noise blurs features: a line box reported two lines high can put a
  block in another style. Buckets absorb small shifts only.
- Scanned pages vary more than clean pages and give more, smaller styles.
- Italic is not measured, so it does not separate styles.
- Wrong block boundaries show as a suspicious style; they are fixed by
  merging and splitting in the review.
