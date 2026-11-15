# PDF import: how a PDF becomes page images

A PDF is accepted anywhere a folder of page images is: in the
[app](app-conversion.md) (*Choose Folder or PDF…*, or drop it on the
window) and in [`pagescan`](pagescan-cli.md) (`pagescan document.pdf`). The
decisions behind it are in [ADR 0009](../adr/0009-pdf-drawn-to-page-images.md).

## What it does

1. The pages are drawn, one at a time, into PNG files (`page-0001.png`, …)
   in page order. A page that is a single image is drawn at that image's own
   pixel size, so nothing is resampled; other pages are drawn at 200 dpi.
   The longer side never exceeds 4096 pixels.
2. From there the pipeline is the same as for a folder of clean pages:
   recognition, notes by colour, pictures, layout, EPUB.
3. Any text layer in the PDF is ignored; recognition is from pixels only.

In the app the drawing step has its own progress bar (*Drawing the pages…*)
and can be cancelled. The pages are then kept inside the project:
`<PDF name>.scanproject` beside the PDF has a `pages/` folder, so the review
shows the scans and the project reopens even if the PDF was moved or deleted
(see [projects](projects.md)). `pagescan` draws into a temporary folder and
deletes it, keeping only the EPUB.

## Known limits

- A password-protected PDF is refused with a message; remove the password
  first. A file that is not a readable PDF, or has no pages, is reported too.
- The project holds a PNG per page, so a long document takes disk space about
  the size of its clean pages.
- A PDF is recognized as a PDF by its `.pdf` extension.
- Pages that are not one embedded image (born-digital PDFs) are drawn at a
  fixed 200 dpi; their text layer is not used.
- A page whose picture is placed smaller than the page keeps the page's
  empty margins, which layout analysis sees as page margins. A PDF made
  that way can come out differently from the same clean pages as a folder.
- Two-page spreads and skewed scans are not corrected; preprocessing is not
  built.
- A PDF whose pages are clean pages inset on a white page (a grey card with
  white margins all round) comes out as one picture per page and no text:
  picture detection takes the card for an illustration. This is the layout
  analysis meeting a margin it does not crop, not something the import
  changes; cropping margins belongs to preprocessing, which is not built. A
  161-page PDF of this kind was converted to an EPUB with 160 figures.

## How it was checked

- Synthetic PDFs in the tests: page count, order, size, colour, errors,
  cancellation, and a project that reopens after its PDF is deleted.
- On a 31-page sample PDF, the drawn pages 1-13 are pixel-identical to the
  same document's clean pages (maximum difference 0 of 255), and the whole document
  converts to 3 chapters, 8 headings, 174 paragraphs, 12 figures, a cover
  and 9 linked notes, the same counts as the image folder; `epubcheck` finds
  no errors. Note markers survive, so the link colour is intact.
- The 161-page PDF above converted in about 140 seconds with a peak memory
  footprint of about 220 MB, so pages are not held in memory.
- In the app, with a 2-page PDF: choosing it from the open panel and by drag
  and drop, converting, reviewing the scans, saving the EPUB, then renaming
  the project bundle, deleting the PDF and reopening the project: the review
  still shows the scans.
