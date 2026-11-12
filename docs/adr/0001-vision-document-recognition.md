# ADR 0001: What we take from Vision and what we compute ourselves

- Status: accepted
- Date: 2026-11-12
- Evidence: `Spikes/vision-ocr/main.swift`, run on macOS 27.2 against a synthetic
  page and pages from four sample sets (Ukrainian, some Latin-script fragments).

## Context

The plan assumed `RecognizeDocumentsRequest` might return enough structure
(paragraphs, lists, title) to keep our own layout heuristics small, and that
recognition confidence could drive the "words to review" list. Both needed
checking on real Ukrainian material before building the layout stage.

The sample sets turned out to be **clean pages of a clean-page source**, not camera or
flatbed scans: clean rendering, no skew, no running headers, a page number at
the bottom, note references drawn as blue links, notes collected at the end of
the document, illustrations with captions, a cover and a contents page.

## Findings

| Question | Result |
|---|---|
| Is Ukrainian supported? | Yes (`uk` is in `supportedRecognitionLanguages`). |
| Text accuracy on body text | Good. No errors spotted in the pages inspected by eye. |
| Speed | 0.2-0.4 s per page once warm. The first request in a process took 85 s (one-off model load), so the app must warm up in the background and show progress. |
| Language setting | `uk-UA` alone, `uk-UA + en-US`, and automatic detection gave the same lines on Ukrainian pages. Automatic detection changed paragraph grouping on one page and lowered confidence, so languages are set explicitly. |
| Paragraph grouping | **Not reliable.** An indented first line is often split from the rest of its paragraph, and one visual line was split into two "paragraphs". |
| `title` | Returned for every page, including pages with no heading. Not usable. |
| Lists / tables | None detected on the samples (none expected). |
| Confidence | **Weak signal.** Correct text scores 0.4-0.6. Word observations carry the confidence of their line, so there is no per-word confidence. |
| Heading detection by line height | Works for large chapter titles (about 2x body height). Fails for bold headings set at body size and for short sub-headings in the body font. |
| Small type | On the synthetic page, Ukrainian lines about 30 px tall were read as Latin gibberish at 1x; the real clean pages at similar size were read correctly. Treat small text as a risk and keep 2x upscaling as a fallback. |
| Note references | The digits are fused into the preceding word and frequently misread (`60` read as Cyrillic letters, Latin `b`/`c` markers read as Cyrillic look-alikes). |
| Blue text as a signal | Works: every word box containing a note reference had a clearly non-zero share of blue pixels, and no body word did. One page showed two adjacent references of different colour, so colour finds references but does not separate neighbours. |
| Page number | Sometimes missed entirely. Harmless: page numbers are discarded anyway. |

## Decision

1. Use `RecognizeDocumentsRequest` as the OCR engine, but consume only its
   **lines** (text, bounding box, confidence) and **word boxes**. Ignore its
   paragraph grouping and `title`.
2. Build paragraphs ourselves from line geometry: first-line indent, vertical
   gap, and continuation across pages (a page that starts with an unindented
   line continues the previous page's paragraph).
3. Do not use Vision confidence as the main review signal. Flag words for
   review with the system spell checker plus specific rules (digit/letter
   confusion, mixed-script words), with confidence only as a tie-breaker.
4. Detect note references by **colour** in the page image, then re-recognise
   just that region (upscaled, Latin/digits) instead of trusting the fused
   word text. Numbering is validated against the expected sequence, and gaps
   are shown to the user.
5. Heading detection combines line height with stroke weight (bold) and
   isolation (a short single line with space around it). Body-font
   sub-headings are ambiguous by nature and go through user confirmation with
   propagation to similar blocks.
6. Notes are modelled as **endnotes collected at the end of the document** as well
   as page footnotes; the samples only have the former.
7. Deskew and spread splitting stay in the design but move to the end of the
   backlog: none of the current samples need them.

## Consequences

- The layout stage is larger than hoped, but it is pure geometry over our own
  line type, so it is fully unit-testable without Vision.
- The OCR adapter needs access to page pixels (colour sampling, region
  re-recognition), not only to Vision output.
- The findings come from a handful of pages of four sets from what looks like
  one reader app. They must be re-checked when a document from another source, or
  a real paper scan, is added.

## Not yet verified

- Italic/bold detection for inline emphasis.
- Illustration region detection and caption association.
- Whether re-recognising a cropped note reference actually yields correct
  digits (decision 4 is the plan, not a measured result).
- Latin-script and mixed-language paragraphs beyond single words.
