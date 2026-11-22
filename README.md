# pdf-to-epub

A native macOS app that turns a scanned document into an EPUB 3, keeping its
structure: headings, paragraphs, illustrations with captions, the cover and
linked notes. Recognition runs on device with Apple Vision; nothing is sent
over the network.

The input is a **PDF** or a **folder of page images** (one image per page);
see [docs/features/pdf-import.md](docs/features/pdf-import.md). The milestone
list is in [CLAUDE.md](CLAUDE.md), known defects in [docs/backlog.md](docs/backlog.md).

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
swift run --package-path Packages/ScanCore -c release pagescan <folder-or-file.pdf>
```

Tests:

```bash
swift test --package-path Packages/ScanCore
```

Before committing, run `scripts/check.sh` (format, lint, fast tests); see
[docs/testing.md](docs/testing.md).

The `epubcheck` test is skipped with a warning when `epubcheck` is not
installed; `REQUIRE_EPUBCHECK=1` turns that into a failure. Tests on
real documents run only when `PAGESCAN_SAMPLES_DIR` points to a folder of
sample sets.

## Usage walkthrough

1. Have the document as a PDF, or put its page images in one folder (`png`,
   `jpg`, `tif`, `heic`), named so that Finder sorts them in page order.
2. Start the app and press *Choose Folder or PDF…* (⌘O), or drop the PDF or
   folder on the window.
3. Check the title (preset to the folder's or the PDF's name), add the author if you
   like, pick Ukrainian or English, and press *Convert*. The first page
   takes about a minute while Vision loads its model; after that a page
   takes well under a second.
4. The summary shows how many chapters, headings, paragraphs,
   illustrations and notes were found. *Needs attention* lists note
   references and note texts that could not be linked.
5. *Review…* (⌘R) shows each page scan next to what was recognized on it,
   with suspicious words (likely OCR misreadings) highlighted, blocks whose
   text was probably misrecognized and pages that may have lost their text
   outlined in red; *Next Issue* (⌘G) jumps between them. Click a highlighted word for quick fixes, or
   turn on *Spelling* to mark words the dictionary does not know too. See
   [docs/features/review.md](docs/features/review.md).
   Select a block to change its type, edit its text or ignore it (⌘Z
   undoes); the app offers the same change for similar blocks and for a
   word fixed once. See [docs/features/corrections.md](docs/features/corrections.md).
6. The document and every correction are saved as `<name>.scanproject` beside
   the scans or the PDF. A PDF's pages are kept inside it. Choose that
   folder (⌘O) later to continue where you left off.
7. *Save EPUB…* (⌘S) writes the document with the corrections applied.

## Documentation

- [docs/README.md](docs/README.md): feature pages, design decisions (ADRs)
  and the backlog.
- [GLOSSARY.md](GLOSSARY.md): the project's shared vocabulary.
- [CLAUDE.md](CLAUDE.md): product decisions, architecture, development
  process and code standards.

## License

[MIT](LICENSE). The license covers this code only. The documents you convert
remain the property of their rights holders.
