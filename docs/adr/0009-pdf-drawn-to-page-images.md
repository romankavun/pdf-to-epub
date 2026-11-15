# ADR 0009: A PDF is drawn into page images once, and the project keeps them

- Status: accepted
- Date: 2026-11-15

## Context

Every stage after import (Vision, note-marker colours, ink weight, picture
cropping, the review's scans) takes a page as an image file URL. A PDF has
to become that. The inputs we care about are scanned documents: a PDF with one
image per page, often with a text layer we do not want (recognition is from
pixels only), sometimes with the image placed smaller than the page.
Note markers are found by link colour, so colour must not shift or blur.

## Decisions

1. **Draw, do not re-plumb.** `PDFImporter` (in `Importing`, CoreGraphics
   `CGPDFDocument`, no PDFKit needed) draws each page to a PNG file
   `page-NNNN.png`. The pipeline is unchanged and treats the files as a
   folder of clean pages. The text layer is ignored because only page
   content is drawn to pixels.
2. **Resolution.** A page that is exactly one image (found by scanning the
   content stream, so placement and the page's size in points do not
   matter) is drawn at that image's own pixel density: the source pixels
   are kept, not resampled. Any other page is drawn at 200 dpi. The longer
   side is capped at 4096 px. PNG, sRGB, white background; no JPEG, so the
   link colour survives. We do not extract the embedded stream: decoding
   every filter and mask by hand is error-prone, and drawing at native
   density gives the same pixels in the common case.
3. **Memory.** One page at a time is drawn, written and released; a
   380-page document never holds more than one bitmap. Rendering supports
   cancellation between pages and reports progress.
4. **Project keeps the pages.** Pages drawn from a PDF are moved into the
   project bundle's `pages/` folder and stored relative to the bundle. The
   alternatives were rendering again on demand (needs the PDF to stay put,
   costs time on every review step) or keeping absolute paths into a temp
   folder (lost on restart). The cost is disk space; the gain is a project
   that survives a moved or deleted PDF and a moved bundle. Scans in a
   folder keep being referred to by absolute path, as before.
5. **Staging.** Pages are drawn to a temporary folder first and moved into
   the bundle when the project is created; a failed or cancelled run
   deletes them, a failed project write puts them back and the document keeps
   using them until another input is opened.
6. **Errors** are typed (`PDFImportError`): unreadable, password required
   (an empty password is tried first), no pages, cannot render, cannot
   write.

## Consequences

- Project format stays version 1: relative page paths are told apart from
  absolute ones by the leading slash.
- Encrypted PDFs are refused rather than prompted for a password.
- A PDF whose pages are not one image (born-digital) is drawn at 200 dpi,
  which is fine for Vision but not tuned.
- Spread splitting and deskew remain out of scope (preprocessing).
