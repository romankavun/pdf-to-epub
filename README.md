# pdf-to-epub

A native macOS app that turns a scanned document into an EPUB 3, keeping its
structure: headings, paragraphs, illustrations with captions, the cover and
linked notes. Recognition runs on device with Apple Vision; nothing is sent
over the network.

Today the input is a **folder of page images** (one image per page). PDF
input is not built yet; see [docs/backlog.md](docs/backlog.md) and the milestone list in
[CLAUDE.md](CLAUDE.md).

## Requirements

- macOS 26 or later
- Xcode 27 (Swift 6.4)
- Optional, for development: `epubcheck`, `swiftformat` and `swiftlint`
  (`brew install epubcheck swiftformat swiftlint`)

## Build and run

The app:

```bash
xcodebuild -project App/PDFToEPUB.xcodeproj -scheme PDFToEPUB build
```

or open `App/PDFToEPUB.xcodeproj` in Xcode and run the `PDFToEPUB`
scheme.

The command-line tool, same pipeline without the window:

```bash
swift run --package-path Packages/ScanCore -c release pagescan <folder>
```

Tests:

```bash
swift test --package-path Packages/ScanCore
```

The `epubcheck` test is skipped when `epubcheck` is not installed. Tests on
real documents run only when `PAGESCAN_SAMPLES_DIR` points to a folder of
sample sets.

## Usage walkthrough

1. Put the page images of a document in one folder (`png`, `jpg`, `tif`,
   `heic`), named so that Finder sorts them in page order.
2. Start the app and press *Choose Folder…* (⌘O), or drop the folder on the
   window.
3. Check the title (preset to the folder's name), add the author if you
   like, pick Ukrainian or English, and press *Convert*. The first page
   takes about a minute while Vision loads its model; after that a page
   takes well under a second.
4. The summary shows how many chapters, headings, paragraphs,
   illustrations and notes were found. *Needs attention* lists note
   references and note texts that could not be linked.
5. *Review…* (⌘R) shows each page scan next to what was recognized on it,
   with suspicious words (likely OCR misreadings) highlighted; *Next Issue*
   (⌘G) jumps between them. Click a highlighted word for quick fixes, or
   turn on *Spelling* to mark words the dictionary does not know too. See
   [docs/features/review.md](docs/features/review.md).
   Select a block to change its type, edit its text or ignore it (⌘Z
   undoes); the app offers the same change for similar blocks and for a
   word fixed once. See [docs/features/corrections.md](docs/features/corrections.md).
6. The document and every correction are saved as `<folder>.scanproject` beside
   the scans. Choose that folder (⌘O) later to continue where you left off.
7. *Save EPUB…* (⌘S) writes the document with the corrections applied.

## Documentation

- [docs/README.md](docs/README.md): feature pages, design decisions (ADRs)
  and the backlog.
- [CLAUDE.md](CLAUDE.md): product decisions, architecture, development
  process and code standards.
