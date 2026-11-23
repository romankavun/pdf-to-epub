# Proposal: the style overview

- Status: accepted; slices 1 and 2 built (#33, #34, see [styles](../features/styles.md) and
  [review](../features/review.md#the-styles-sidebar)), slices 3-4 not built
- Date: 2026-11-19, revised 2026-11-22 (read-only overview in the review),
  revised 2026-11-23 (implementation plan, examples, page furniture, editing
  by style back in as slice 4 after [ADR 0011](../adr/0011-no-convert-again.md))
- Issue: #31
- Prototype: branch `prototype/style-overview` (throwaway, not for main)
- Related: [ADR 0011](../adr/0011-no-convert-again.md), [ADR 0005](../adr/0005-corrections-apart-from-recognition.md),
  [ADR 0006](../adr/0006-body-size-headings.md),
  [corrections](../features/corrections.md), [review](../features/review.md)

## Problem

Layout analysis gives each block a type by a handful of rules. When a rule
is wrong for a document, it is usually wrong the same way on every page: a
running footer that the repetition rule missed becomes a heading on every
other page, small print becomes a run of one-line paragraphs, a note style
swallows body text. The review shows one page at a time, so such a pattern
is only noticed page by page, if at all.

The user wants to see, after a conversion, every kind of block recognition
produced ("text that looks like this became Heading 1, this a paragraph,
this a note") and spot at a glance which ones are odd.

## Decision

A **style overview** inside the [review](../features/review.md) as an
optional left sidebar. It shows every style; fixes are made with the review's
existing tools on the blocks it leads to, or, from slice 4, by changing the
type of a whole style at once.

Chosen over a separate screen opened from the summary (the scan stays in
view, so a block is always seen on its page) and over a grid of styles or a
page map (prototyped as variants A and C; the user chose the list of styles
with the blocks of the selected one, variant B).

## What a style is

A [style](../../GLOSSARY.md) is a group of blocks with the same recognized
type, the same [deciding rule](../../GLOSSARY.md) and close measured
features. The grouping is deterministic (features quantized into buckets,
like `SimilarBlocks`), no learning. Grouping leans fine: a small difference
makes its own style, so an odd block stands out, and the list is grouped by
type so it stays easy to scan. There is no cap on the number of styles; the
tuning check on the sample sets is that no style mixes two types and none is
split by OCR noise alone.

Features, all relative to the document's own body text and page:

- line height (multiple of the median line height) and ink weight
  (multiple of the typical density, ADR 0006);
- alignment: at the margin, indented, centred, or right; width;
- page zone: top edge, bottom edge, body;
- number of lines; space above and below (in median line steps);
- under a picture; opens with a note label.

The deciding rule is what made the analyzer choose the type: larger than
the text, body size and bold, body size and centred, caption by label
("Fig. 3", "Мал. 27"), caption by gap, note text, paragraph, page furniture (repeats at the page edge, page number).

**Styles show what recognition decided, not the corrections.** They are
computed from the recognized document, so the list does not reshuffle while
the user fixes blocks; a style counts how many of its blocks were corrected,
and their crops carry a badge. An ignored block stays in its recognized style
with an *ignored* badge; there is no separate group of ignored blocks.

**Prerequisite.** Today `LayoutAnalyzer` computes these features per line
and drops them; `DocumentLayout` keeps only the type and the box. Layout
analysis has to export a `BlockStyle` (features + deciding rule) per block
and per note, carried by `Conversion` and saved in `project.json` (format
version 2). The [page furniture](../../GLOSSARY.md) it removes is kept too,
with its boxes, so the overview can show it. A version 1 project still
opens, without styles: *Styles* is disabled and its help says to *Start
over* to see them.

**Names and colours.** A style's name is its type and deciding rule,
numbered when two styles share both ("Heading 1 · larger, centred",
"Paragraph 2 · indented"), localized. Colours come from a fixed palette in
order of first appearance, so a project always gets the same colours.

## In the review

- **Styles** in the review toolbar (⌃⌘S) shows and hides the sidebar. It is
  off every time the review opens; the choice is not remembered. While it
  is shown the window is at least about 1180 pt wide.
- The **sidebar** lists the styles grouped by type: headings by level,
  paragraphs, figures and captions, note texts, and page furniture. Each row: a colour, the style's name, the
  number of blocks, a mark if it is probably wrong.
- **Selecting a style** replaces the right-hand column (the page's block
  list) with the style's blocks:
  - the deciding rule in words ("1.6 × taller than the text, centred"),
    the number of blocks and the pages, and the warning if any;
  - six [examples](../../GLOSSARY.md), crops of the page image with their
    page numbers, from pages spread across the document (no two from one
    page while other pages have one), then *Show All N* for every block.
- The style's blocks on the page in view are **outlined in its colour** on
  the scan; other outlines fade.
- **Clicking a crop** goes to its page, selects the block and brings back
  the block list. The style is no longer selected.
- A **selected block** shows a button with its style's name; it opens the
  sidebar (if hidden) on that style. That is the way back from a block to
  its style.
- While a style's blocks are shown, the issue and spelling controls are
  hidden (they act on the block list); undo and redo stay.

### Probably wrong

A style is marked when:

- it is a heading style at the top or bottom edge of several pages (a
  running header the repetition rule missed);
- it is a style of one-line paragraphs across the full width (lines that
  were not joined);
- most of its blocks are *text probably misrecognized*;
- it is a page-furniture style whose lines are long or vary from page to
  page (body text removed by mistake).

### Editing by style (slice 4)

The selected style's header has *Change to…*: Paragraph, Heading 1–3 or
Ignore, the types a single block can be changed to. It records one ordinary
per-block type correction for each block of the style, as one undo step;
the same mechanism as a [proposal](../../GLOSSARY.md), with the style
choosing the blocks instead of `SimilarBlocks`. No new correction kind and
no format change. The style stays in the list, now counting its blocks as
corrected; a later change to one block is a later correction and wins.

## Implementation

`LayoutAnalysis` computes features and the deciding rule. A new `Styles`
module (depends on `DocumentModel` and `LayoutAnalysis`) groups them into
styles, so the app and `pagescan` share it. UI is written test-first; the
prototype branch is a visual reference only. Slices, each a sub-issue of
#31 (#33–#36), after the *Convert Again* removal (#32, ADR 0011):

1. **Styles from layout analysis**: `BlockStyle` per block and note, page
   furniture kept, `project.json` version 2, the `Styles` grouping,
   `pagescan --styles`, golden pages assert the deciding rule.
2. **The sidebar in the review**: toggle, list, examples and *Show All*,
   outlines, crop to block, block to style.
3. **Probably-wrong marks.**
4. **Editing by style.**

## Limits

- Wrong block boundaries are visible as a suspicious style, not fixable
  from it: that is merging and splitting in the review.
- OCR noise blurs features: a line box reported two lines high can put a
  block in the wrong style. Bucketing absorbs small shifts.
- Scanned pages vary more than clean pages, so they produce more, smaller
  styles; buckets may need to be wider for sources profiled as scanned.
- Italic is not measured (ADR 0006), so it does not separate styles.

## Later

- Putting page furniture back into the document, and "not a note" (a
  note-text style back into paragraphs): each needs a new correction kind.
- A style rule (one correction over a style's signature instead of one per
  block): smaller to store; no longer needed to reach blocks of a later
  conversion (ADR 0011).
- Splitting a style by one feature and merging two styles.
- Per-document thresholds (edit the analyzer's thresholds with a preview),
  chosen as part of *Start over* before corrections are made, once
  recognized lines are kept in the project so layout analysis can run again
  without OCR.
- Other panels in the same sidebar: the list of manual changes (#17) and
  the undo history (#29).
