# ADR 0006: Headings at body size are found by what surrounds them and by ink weight

- Status: accepted
- Date: 2026-11-14
- Evidence: synthetic pages in the tests, and a few pages of three sample
  documents run through the whole pipeline (only the resulting headings were
  inspected).
- Answers the open question about bold and italic in `CLAUDE.md`, for
  headings.

## Context

Heading detection compared a line's height with the median line. Some
headings (sub-headings, a short title that opens a section, "Bibliography")
are set in the body size, or only slightly larger, and differ from text by
weight, by being centered and by the blank space around them. Neither the
engine's output (ADR 0001) nor its fonts tell us anything about weight:
Vision returns text and boxes only.

## Decision

1. **Weight is measured from pixels, as a density.** For each recognized
   line, the average difference from the page background over the line's
   box (`PageBitmap.inkDensity(in:)`). Bold has thicker strokes, so its
   density is clearly higher at the same typeface. The number is compared
   only with the document's own typical line (lower median, `1.15 x` or more is
   bold; measured headings were 1.2 to 1.6 x, body lines up to 1.15 x, because
   a box that hugs the letters closely reads denser), never against a fixed value, because backgrounds, colours and
   anti-aliasing differ between documents. `PageContent.lineInk` carries it;
   `Conversion` measures it (`LineInkMeasurer`). Without measurements no
   line is bold and the rule falls back to centering.
2. **A body-size heading is a single line set apart** (blank line above, or
   the page edge, and for a centered one also below; a bold heading may be
   followed closely by its text), short (at most 70 %
   of the page width, 100 characters, not ending with `. , ; : …`), which
   is either **bold** or **centered** (middle within 4 % of the page's
   middle) and then at most 8 words. The word limit keeps dedications and
   epigraphs, which are centered sentences, out. A line directly under a
   picture is a caption and is never a heading; a line carrying a note
   marker is never a heading.
3. **Levels.** A heading set larger than the text is level 1; a body-size
   one is level 2. A document with no larger headings promotes its body-size
   headings to level 1, so the contents are not left without a first level.
4. **Italic is not detected.** Slant has no cheap, reliable pixel measure;
   an italic-only heading is found only if it is centered. Inline emphasis
   inside paragraphs (the other half of the open question) is not touched.

## Consequences

- A heading at the top of a page no longer runs on from the previous page's
  unfinished paragraph (a heading never continues one); this was a defect
  in the backlog when the heading is bold or centered.
- A bold one-line paragraph with blank space around it (a short quotation, a
  lone sentence in bold) will be read as a heading. The user can change it
  in the review screen.
- Headings that wrap onto two lines at body size are not recognized (the
  lines of a block share too little space around them to tell them from a
  paragraph).
- One more pass over every line's box in the page image during conversion;
  it is cheap next to recognition.
