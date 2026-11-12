# EPUB export

Writes a `Document` (the document model) as an EPUB 3 file.

Status: implemented in `ScanCore` (`EPUBExport` module). Not yet reachable
from the app UI or a CLI; today it is called from code.

## Usage

```swift
import ScanCore

try EPUBExporter().export(document, to: URL(fileURLWithPath: "/path/document.epub"))
```

Pass `modified:` to fix the publication date and get byte-identical output
for the same document.

## What ends up in the file

| Model | EPUB |
|---|---|
| `DocumentMetadata` | `dc:identifier`, `dc:title`, `dc:language`, `dc:creator` (when the author is known), `dcterms:modified` |
| `Chapter` | One XHTML file (`chapter-001.xhtml`, ...) and one entry in the table of contents |
| `Block.heading` | `<h1>`...`<h6>`; levels outside that range are clamped |
| `Block.paragraph` | `<p>` |
| `Block.figure` | `<figure>` with `<img>` and, when there is a caption, `<figcaption>` |
| `Inline.emphasis` / `.strong` | `<em>` / `<strong>` |
| `Inline.noteReference` | A superscript link marked `epub:type="noteref"` showing the note's label |
| `Note` | An `epub:type="footnote"` aside at the end of each chapter that refers to it, with a link back to the first reference |
| `ImageResource` | A file under `images/`; the one named by `coverImageID` is declared as the cover |

Notes are written into the same file as their reference because that is where
pop-up footnotes work reliably (Apple Documents in particular). Reading systems
without pop-ups show the notes as a list after the chapter.

## Errors

Export fails with `EPUBExportError` rather than writing a broken file:

- `noChapters` - the document has no content.
- `missingNote(id:)` - text refers to a note that does not exist.
- `missingImage(id:)` - a figure or the cover refers to an image that does not exist.
- `duplicateImageFilename(_:)` - two images share a file name.

## Known limits

- The table of contents is flat: one entry per chapter, no sub-headings.
- Notes that nobody refers to are not exported.
- A note referenced from two chapters is written in both.
- Inline formatting does not nest (no bold-italic).
- No dedicated cover page; the cover is declared as metadata only, which is
  what library views use.
- Styling is a small built-in stylesheet; it is not configurable.
- Conformance is checked by `epubcheck` (5.4.0, warnings treated as failures)
  in the test suite. That test is skipped on machines without `epubcheck`
  (`brew install epubcheck`).
