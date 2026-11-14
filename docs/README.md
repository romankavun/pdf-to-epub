# Documentation

Build, run and a usage walkthrough are in the [project README](../README.md).

- Architecture decisions: [adr/](adr/)
  - [0001 - What we take from Vision and what we compute ourselves](adr/0001-vision-document-recognition.md)
  - [0002 - Pictures are found from pixel bands, not from OCR output](adr/0002-picture-detection.md)
  - [0003 - Notes are located by colour, erased before OCR, and linked by label and order](adr/0003-notes-by-colour-and-sequence.md)
  - [0004 - A reference is linked to the notes that follow it, in the right numbering system](adr/0004-two-numbering-systems.md)
  - [0005 - Corrections are kept apart from recognition and find their block by its place on the page](adr/0005-corrections-apart-from-recognition.md)
  - [0006 - Merging and splitting blocks are corrections applied before edits](adr/0006-merge-and-split-corrections.md)
- [Backlog: known defects, the next improvement (page preview while converting) and postponed ideas](backlog.md)
- Features: [features/](features/) - one page per user-facing feature.
  - [pagescan CLI: folder of page images to EPUB](features/pagescan-cli.md)
  - [App: convert a folder and save the EPUB](features/app-conversion.md)
  - [Review: the scan next to what was recognized](features/review.md)
  - [Corrections: fixing types and text, applying a fix to similar blocks](features/corrections.md)
  - [Projects: saving a document and its corrections, opening it later](features/projects.md)
  - [Layout analysis](features/layout-analysis.md)
  - [Illustrations, captions and the cover](features/illustrations.md)
  - [Notes: references, note texts and linking](features/notes.md)
  - [EPUB export](features/epub-export.md)
