# Proposal: the document's style guide

- Status: proposed (direction agreed with the user, not built)
- Date: 2026-11-19
- Related: [ADR 0005](../adr/0005-corrections-apart-from-recognition.md),
  [ADR 0006](../adr/0006-body-size-headings.md),
  [ADR 0008](../adr/0008-merge-and-split-corrections.md),
  [corrections](../features/corrections.md), [review](../features/review.md)

## Problem

Layout analysis classifies blocks by a handful of heuristics. When one of
them is wrong for a document, it is wrong the same way on every page, but the
review screen makes the user find and fix it block by block. Seen on a
paper scan of an English novel:

- The running footer ("4 ANDY WEIR", read once as "6 ANDYWEIR") became a
  level 1 heading on every other page: OCR spells it differently and the
  scan puts it at slightly different heights, so the repetition rule missed
  it.
- A newspaper clipping reproduced inside the document was not taken for a
  picture; its headline became a heading and its small two-column print a
  run of misrecognized paragraphs.
- On a skewed page every line became a paragraph of its own.

The user wants to see, after a conversion, what the document's typography was
recognized as ("text that looks like this became Heading 1, this a
paragraph, this a caption") and fix a whole class at once.

## Direction: a style guide screen with style rules ("A+")

Three options were discussed:

| Option | What | Why not alone |
|---|---|---|
| A. Style guide + bulk retype | Group blocks into styles, show samples, change a style's type with ordinary per-block corrections | A decision does not reach blocks found by *Convert Again* |
| B. Style as a rule | The decision is stored as a rule over the style's signature and applies to the whole document, re-runs included; styles can be split and merged | Splitting and merging styles is more than v1 needs |
| C. Per-document thresholds | Edit the analyzer's thresholds (heading height factor, indent, running line tolerance) with a live preview | Recognized lines are not kept in the project, so every change means OCR again (minutes); numbers are abstract; anchors of merges and splits may be orphaned |

Chosen: **A's screen and actions, with each decision stored as a style rule
as in B**, without splitting or merging styles. C is a later step and
depends on keeping recognized lines in the project.

## What a style is

A style is a group of blocks with the same recognized type, the same
deciding rule and close measured features. The grouping is deterministic
(features quantized into buckets, like `SimilarBlocks`), no learning.

Features, all relative to the document's own body text and page:

- line height (multiple of the median line height) and ink weight
  (multiple of the typical density, ADR 0006);
- alignment: at the margin, indented, centred, or right; width;
- page zone: top edge, bottom edge, body;
- number of lines; space above and below (in median line steps);
- under a picture; opens with a note marker.

The deciding rule is what made the analyzer choose the type: larger than
the text, body size and bold, body size and centred, caption by label
("Fig. 3", "Мал. 27"), caption by gap, note text, paragraph.

**Prerequisite.** Today `LayoutAnalyzer` computes these per line and drops
them; `DocumentLayout` keeps only the type and the box. Layout analysis has to
export a `BlockStyle` (features + deciding rule) per block and per note,
carried by `Conversion` and saved in `project.json` (a format change;
older projects simply have no style guide until converted again).

## The screen

- A separate screen, opened from the summary by its own button
  (*Styles…*). It is never shown automatically after a conversion, and it
  is not a tab of the review, to keep the review uncluttered.
- Styles are listed grouped by type (headings by level, paragraphs,
  captions, notes, ignored). Each row shows:
  - 3–4 sample crops from the page images, the most typical first;
  - how many blocks and on which pages;
  - the rule in words: "1.6 × taller than the text, centred → Heading 1",
    "one line at the bottom edge, on 11 pages → Heading 1";
  - the type menu.
- Clicking a sample opens the review on that block; *Back* returns to the
  style guide.
- Rows that are probably wrong are marked: a heading style that recurs at
  the top or bottom edge, a paragraph style of one-line blocks across the
  full width, a style whose blocks are mostly *text probably
  misrecognized*.

## Actions

- **Change the type of a style**: Paragraph, Heading 1–3, Ignore.
- **Running header or footer**: ignore every block of the style. Unlike the
  review's propagation, which never offers ignoring, this is an explicit
  choice on the style, shown with the list of blocks it will drop first.
- **Show all blocks**: the list with a switch per block, as *Choose…* in
  the review; blocks switched off get a per-block exception.
- **Reset** a style to its recognized type.

Each action is one step of undo.

## How decisions are stored

A new correction, `styleRule(signature, type)`, in `CorrectionSet`:

- The signature is the style's bucketed features and deciding rule, not a
  list of anchors, so the rule also applies to blocks of that style found
  by a later *Convert Again*, like `replaceWord`.
- Order of application: merges and splits first (ADR 0008), then style
  rules, then per-block types and edits. A per-block decision always wins
  over a style rule, so a block the user fixed by hand is never overridden.
- A rule that matches no block after a re-run is reported with the other
  corrections that no longer apply.

## Limits

- Wrong block boundaries (every line a paragraph on a skewed scan) are
  visible as a suspicious style but not fixable here: that is merging, or
  option C.
- "This is an illustration" (the newspaper clipping) needs redrawing a
  region, which does not exist yet; the style can only be ignored.
- OCR noise blurs features: a line box reported two lines high, or a page
  number read as a letter, can put a block in the wrong style. Bucketing
  absorbs small shifts; the per-block switches cover the rest.
- Paper scans vary more than clean pages (slightly different heights and
  sizes from page to page), so they produce more, smaller styles; buckets
  may need to be wider for documents profiled as scans.
- Italic is not measured (ADR 0006), so it does not separate styles.

## Later

- Splitting a style by one feature and merging two styles.
- Per-document thresholds (option C), once recognized lines are kept in the
  project so layout analysis can run again without OCR.
