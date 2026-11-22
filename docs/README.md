# Documentation

Build, run and a usage walkthrough are in the [project README](../README.md).

- [Architecture: pipeline stages, module layout, module boundaries](architecture.md)
- Architecture decisions: [adr/](adr/)
  - [0001 - What we take from Vision and what we compute ourselves](adr/0001-vision-document-recognition.md)
  - [0002 - Pictures are found from pixel bands, not from OCR output](adr/0002-picture-detection.md)
  - [0003 - Notes are located by colour, erased before OCR, and linked by label and order](adr/0003-notes-by-colour-and-sequence.md)
  - [0004 - A reference is linked to the notes that follow it, in the right numbering system](adr/0004-two-numbering-systems.md)
  - [0005 - Corrections are kept apart from recognition and find their block by its place on the page](adr/0005-corrections-apart-from-recognition.md)
  - [0006 - Headings at body size are found by what surrounds them and by ink weight](adr/0006-body-size-headings.md)
  - [0007 - The spell checker sits behind a protocol; the system adapter lives in the app](adr/0007-spell-checker-behind-a-protocol.md)
  - [0008 - Merging and splitting blocks are corrections applied before edits](adr/0008-merge-and-split-corrections.md)
  - [0009 - A PDF is drawn into page images once, and the project keeps them](adr/0009-pdf-drawn-to-page-images.md)
  - [0010 - Prepared scan pages replace the originals as the project's pages](adr/0010-prepared-pages-are-the-project-pages.md)
- [Backlog: index of the GitHub issues for known defects, improvements and postponed ideas](backlog.md)
- [Coding standards: the judgement rules a review checks](../CODING_STANDARDS.md)
- [Glossary: the project's shared vocabulary](../GLOSSARY.md)
- Proposals: [proposals/](proposals/) - designs agreed in direction but not built.
  - [The document's style guide: style rules applied across a whole document](proposals/style-guide.md)
- [Testing: unit tests, golden pages, regenerating expectations](testing.md)
- Features: [features/](features/) - one page per user-facing feature.
  - [pagescan CLI: folder of page images or PDF to EPUB](features/pagescan-cli.md)
  - [PDF import: how a PDF becomes page images](features/pdf-import.md)
  - [Scanned pages: crop, clean and level pages before recognition](features/scan-preprocessing.md)
  - [App: convert a folder or PDF and save the EPUB](features/app-conversion.md)
  - [Review: the scan next to what was recognized](features/review.md)
  - [Corrections: fixing types and text, applying a fix to similar blocks](features/corrections.md)
  - [Projects: saving a document and its corrections, opening it later](features/projects.md)
  - [Layout analysis](features/layout-analysis.md)
  - [Illustrations, captions and the cover](features/illustrations.md)
  - [Notes: references, note texts and linking](features/notes.md)
  - [EPUB export](features/epub-export.md)
