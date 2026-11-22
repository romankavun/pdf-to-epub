# ADR 0010: Prepared scan pages replace the originals as the project's pages

- Status: accepted
- Date: 2026-11-19

## Context

Scanned pages need preprocessing before recognition: the document page lies on a
white scanner bed (about 12 % of the image), with page edges, a gutter
shadow, show-through and skew around and in the text. Left alone, picture
detection takes the whole page for an illustration and Vision reads less
than half the words. Clean pages need none of it.

Every stage after import (Vision, note-marker colours, ink weight, picture
crops) reads a page as an image file, and every box the pipeline produces
(block sources, note sources, correction anchors) is normalized to that
image. The review draws those boxes over a page image. If preprocessing
crops or rotates a page, boxes measured on the processed page do not line
up with the original scan.

## Decisions

1. **Preprocessing writes files.** A stage that crops, cleans and deskews a
   page (`Preprocessing`) writes the result as a PNG and hands the
   converter its URL; `DocumentConverter` reads every stage from it, and
   `Conversion.pageURLs` are the prepared files. The alternatives were
   preparing in memory for each stage (the four readers decode the file
   separately; preparing four times costs time and risks them disagreeing)
   or mapping boxes back to original coordinates (rotation makes boxes
   non-rectangular, and the review would show the skewed, bed-framed scan
   the user cannot read comfortably anyway).
2. **The review shows the prepared page.** It is the image every box was
   measured on, so boxes line up exactly. The user sees a cleaner page
   than the scan, cropped and level, which is easier to compare with the
   text.
3. **The project keeps the prepared pages** in its `pages/` folder, as for
   pages drawn from a PDF (ADR 0009), and stores them relative to the
   bundle. Prepared pages exist nowhere else; a folder of scans keeps its
   originals where the user has them, a PDF is its own original. Originals
   are not copied into the bundle: they can be prepared again from the
   input, and the preparation is deterministic.
4. **Staging.** The app prepares pages into `prepared/` inside its staging
   folder (beside drawn PDF pages, which have the same names). When the new
   project is written, it moves pages in only if every page lives in the
   staging folder; clean pages read in place stay where they are and the
   unused folder is deleted.
5. **Profile per document.** Whether pages are prepared is decided once per
   document from up to nine sampled pages (`InputProfile`): a document of
   clean pages is never touched, and every page of a scanned document is
   prepared, even a cover or a blank page that does not look scanned on
   its own, so all of a project's pages are in one place and one state.
6. **Converting again does not prepare again.** An open project is
   converted from its stored, already prepared pages with preparation off.
   The pages are the same images, so the boxes of the new conversion
   match the old ones and corrections keep their blocks (ADR 0005).
   Cleaning is not idempotent (each pass darkens mid-tones a little), which
   is another reason to prepare once.
7. **Colours.** Cleaning scales the three channels of a pixel by the same
   factor, so a link-coloured note marker keeps its hue; the PNG is
   lossless. Scanned documents seen so far have black, not coloured, markers.

## Consequences

- Project format stays version 1. A project made from scans before this
  change keeps its unprepared pages; converting it again does not prepare
  them. Open the folder or PDF again to get a new project with prepared
  pages.
- Figures cut from a scanned page come from the cleaned image: their
  lightest tones turn white.
- A folder of scans now costs a copy of every page in the project (PNG,
  cropped to the page, so smaller than the scan).
- `pagescan` prepares into a temporary folder; `--prepared-pages` keeps it
  for inspection.
