# Proposal: the style overview

- Status: proposed (design agreed with the user, not built)
- Date: 2026-11-19, revised 2026-11-22 (read-only overview in the review;
  editing by style moved to *Later*)
- Issue: #31
- Prototype: branch `prototype/style-overview` (throwaway, not for main)
- Related: [ADR 0005](../adr/0005-corrections-apart-from-recognition.md),
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

A **style overview**, read-only, inside the [review](../features/review.md)
as an optional left sidebar. It shows; it does not edit. Fixes are made with
the review's existing tools on the blocks it leads to.

Chosen over a separate screen opened from the summary (the scan stays in
view, so a block is always seen on its page) and over a grid of styles or a
page map (prototyped as variants A and C; the user chose the list of styles
with the blocks of the selected one, variant B).

## What a style is

A [style](../../GLOSSARY.md) is a group of blocks with the same recognized
type, the same [deciding rule](../../GLOSSARY.md) and close measured
features. The grouping is deterministic (features quantized into buckets,
like `SimilarBlocks`), no learning.

Features, all relative to the document's own body text and page:

- line height (multiple of the median line height) and ink weight
  (multiple of the typical density, ADR 0006);
- alignment: at the margin, indented, centred, or right; width;
- page zone: top edge, bottom edge, body;
- number of lines; space above and below (in median line steps);
- under a picture; opens with a note label.

The deciding rule is what made the analyzer choose the type: larger than
the text, body size and bold, body size and centred, caption by label
("Fig. 3", "Мал. 27"), caption by gap, note text, paragraph, running line.

**Styles show what recognition decided, not the corrections.** They are
computed from the recognized document, so the list does not reshuffle while
the user fixes blocks; a style counts how many of its blocks were corrected,
and their crops carry a badge.

**Prerequisite.** Today `LayoutAnalyzer` computes these features per line
and drops them; `DocumentLayout` keeps only the type and the box. Layout
analysis has to export a `BlockStyle` (features + deciding rule) per block
and per note, carried by `Conversion` and saved in `project.json` (a format
change; older projects have no styles until converted again). The running
headers and footers it removes have to be kept too, with their boxes, so
the overview can show them.

## In the review

- **Styles** in the review toolbar (⌃⌘S) shows and hides the sidebar. It is
  off every time the review opens; the choice is not remembered. While it
  is shown the window is at least about 1180 pt wide.
- The **sidebar** lists the styles grouped by type: headings by level,
  paragraphs, figures and captions, note texts, ignored blocks, and removed
  running headers and footers. Each row: a colour, the style's name, the
  number of blocks, a mark if it is probably wrong.
- **Selecting a style** replaces the right-hand column (the page's block
  list) with the style's blocks:
  - the deciding rule in words ("1.6 × taller than the text, centred"),
    the number of blocks and the pages, and the warning if any;
  - every block as a crop of the page image, with its page number.
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
- it is a running-line style whose blocks are long or vary from page to
  page (body text removed by mistake).

## Limits

- Wrong block boundaries are visible as a suspicious style, not fixable
  from it: that is merging and splitting in the review.
- OCR noise blurs features: a line box reported two lines high can put a
  block in the wrong style. Bucketing absorbs small shifts.
- Scanned pages vary more than clean pages, so they produce more, smaller
  styles; buckets may need to be wider for sources profiled as scanned.
- Italic is not measured (ADR 0006), so it does not separate styles.

## Later

- **Editing by style.** Change the type of a whole style (Paragraph,
  Heading 1–3, Ignore; ignoring a running-line style after listing what it
  drops; per-block exceptions). Stored as a `styleRule(signature, type)`
  correction over the style's signature rather than a list of anchors, so
  it also reaches blocks found by *Convert Again*, like `replaceWord`.
  Applied after merges and splits and before per-block types and edits; a
  per-block decision always wins.
- "Not a note": turn a note-text style back into paragraphs.
- Splitting a style by one feature and merging two styles.
- Per-document thresholds (edit the analyzer's thresholds with a preview),
  once recognized lines are kept in the project so layout analysis can run
  again without OCR.
- Other panels in the same sidebar: the list of manual changes (#17) and
  the undo history (#29).
