# Architecture

A pipeline of independent stages. Each stage is a pure transformation behind a
protocol, so it can be tested alone and replaced with a fake.

```
Import -> Preprocess -> OCR -> Layout analysis -> Document model -> EPUB export
                                                        ^
                                                  user review (UI)
```

1. **Import**: a PDF (CoreGraphics, drawn to page images) or an image folder
   becomes an ordered list of pages.
2. **Preprocess**: only for documents profiled as scanned pages (grainy paper
   on a scanner bed; clean pages are never touched). Crop the page off the
   bed, whiten the paper and remove edges, shadow and show-through, deskew.
   Pixel-based, no Vision. Writes prepared PNGs that every later stage and
   the review read (ADR 0010). Spread splitting is not built.
3. **OCR**: `RecognizeDocumentsRequest` with explicit languages. We use only
   its lines and word boxes; its paragraph grouping, `title` and confidence
   proved unreliable (ADR 0001). The first request in a process takes over a
   minute to load the model, so warm it up in the background.
4. **Layout analysis**: classifies blocks. Vision does not know what a heading
   or footnote is, so this is heuristic:
   - headings: line height relative to body text, centering, surrounding space;
   - paragraphs: built from line geometry (indent, vertical gap), continued
     across pages when a page starts with an unindented line;
   - notes: markers found by link colour in the page image, erased before
     OCR, their labels read from a strip of crops and repaired from the
     numbering sequence; a paragraph opening with a marker is a note text;
     references are linked by label and order (ADR 0003);
   - running headers/footers and page numbers: repetition across pages,
     left out of the document and kept as page furniture;
   - every block, note text and line of page furniture gets a block style:
     its features relative to the body text and page, and the deciding rule
     that gave it its type; `Styles` groups them into styles;
   - illustrations: tall unbroken bands of non-background rows, cropped out
     as images, text inside them dropped, captions attached (ADR 0002);
   - hyphenated words and paragraphs broken across lines/pages are rejoined.
5. **Document model**: chapters, headings, paragraphs, footnotes, images.
   The single source of truth: the UI edits it, the exporter reads it.
6. **EPUB export**: semantic XHTML, navigation document (TOC), pop-up
   footnotes (`epub:type="noteref"` / `"footnote"`), embedded images, metadata.

## User involvement (human in the loop)

OCR and layout heuristics will be wrong sometimes; the app is built around
making corrections cheap rather than pretending they are not needed.

- **Review screen**: page scan next to the recognized result; suspicious words
  highlighted (`NSSpellChecker`, mixed-script and digit/letter confusion rules;
  Vision confidence is only a tie-breaker); "next issue" navigation.
- **Structure fixes**: change a block's type (heading level / paragraph /
  footnote / illustration / ignore), redraw a region, merge or split blocks.
- **Propagation**: a correction to one block's type can be applied to
  similar-looking blocks across the document, with the user's confirmation.
- **Persistent project**: work is saved to disk as a project bundle so a long
  document can be reviewed across sessions. User corrections are stored
  separately from OCR output and must survive a re-run of OCR or layout
  analysis (ADR 0005).

## Module layout

```
Packages/ScanCore/          Swift package, no UI imports
  Sources/
    DocumentModel/          value types; no dependencies
    Importing/              PDF (drawn to page images) and image folder import
    Preprocessing/          scan profile, page crop, cleanup, deskew; no dependencies
    OCR/                    Vision adapter behind OCREngine protocol
    LayoutAnalysis/         block classification heuristics
    EPUBExport/             EPUB 3 writer
    Corrections/            user corrections applied over a conversion; no UI
    ProjectStore/           project bundle persistence
    Conversion/             pipeline: pages -> Document
    TextReview/             suspicious-word rules; no dependencies
    Styles/                 groups recognized blocks into styles; DocumentModel, LayoutAnalysis
    AppModel/               view models (Observation only, no SwiftUI/AppKit)
    pagescan/               CLI for batch conversion and debugging
  Tests/                    one test target per module + Fixtures/
App/                        SwiftUI app (thin: views + view models)
docs/                       feature and architecture documentation
```

Boundaries, enforced by custom rules in `.swiftlint.yml`:

- `ScanCore` never imports SwiftUI, AppKit or UIKit. The app depends on the
  package, never the reverse.
- Only `OCR` imports Vision; only `Importing` reads PDFs (`CGPDF`, no PDFKit).
  Everything else works on the package's own value types.
- `Styles` imports only `DocumentModel` and `LayoutAnalysis` (and Foundation),
  so the app and `pagescan` share the same grouping.

`DocumentModel` types are `Sendable`, `Codable` value types.

## Open questions

- Inline emphasis (bold/italic inside paragraphs) and italic-only headings;
  bold headings are found by ink weight (ADR 0006).
- How chapters are split: by large headings, by the contents page, or both.
