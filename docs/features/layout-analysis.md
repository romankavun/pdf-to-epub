# Layout analysis

Turns the text lines recognized on each page into headings and paragraphs
(`LayoutAnalyzer` in the `LayoutAnalysis` module). It works on line positions
only, never on pixels, and measures everything relative to the document's own
typical line, so page size and resolution do not matter.

## Rules

| Decision | Rule |
|---|---|
| Body margin | The most common left edge among long lines in the whole document |
| New paragraph | The line starts to the right of the margin (first-line indent), **or** the vertical step from the previous line is more than 1.5 typical steps (a blank line) |
| Paragraph across pages | A page whose first line is not indented continues the last paragraph of the previous page |
| Heading | A line at least 1.5 times taller than the median line. Consecutive tall lines directly below each other form one heading. Always level 1 |
| Page number | The last line of a page, if it is in the bottom 15%, at most four characters, digits only. Dropped |
| Line joining | Lines are joined with a space; a line ending in a letter plus hyphen is joined without one, keeping the hyphen |

Thresholds live in `LayoutAnalyzer.Options`.

## Known limits

- Headings set in bold at body size, and sub-headings in the body font, are
  not detected; they come out as short paragraphs. Only one heading level is
  produced.
- A paragraph that starts at the top of a page without an indent is merged
  into the previous page's paragraph.
- Hyphens at line ends are always kept. This suits clean pages,
  which do not hyphenate; printed documents with soft hyphenation will get stray
  hyphens.
- Running headers and footers other than a page number are not removed.
- Single-column pages only.
- No inline formatting (italic, bold) is recovered.
