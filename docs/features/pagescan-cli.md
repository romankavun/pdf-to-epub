# pagescan: convert a folder of page images from the command line

Converts a folder holding one image per page into an EPUB. It runs the same
pipeline the app will use and exists for batch runs and for checking results
without the UI.

## Usage

```bash
swift run --package-path Packages/ScanCore -c release pagescan <folder> \
    [--output <file.epub>] [--title <title>] [--author <author>] [--language <tag>]
```

| Option | Default |
|---|---|
| `--output` | `<folder>.epub` next to the input folder |
| `--title` | The folder name |
| `--author` | None |
| `--language` | `uk`. English is always added as a second recognition language. |

The first page takes up to a minute while Vision loads its model; after that
a page takes well under a second. A 380-page sample set converts in about
100 seconds.

It ends with a summary: chapters, headings, paragraphs, figures, whether a
cover was found, the notes linked, and the references and note texts that
could not be linked.

## What it does

1. **Import** (`Importing`): takes the `png`, `jpg`, `jpeg`, `tif`, `tiff`
   and `heic` files directly inside the folder, ordered the way Finder sorts
   names (`page_2` before `page_10`). Hidden files and subfolders are ignored.
2. **OCR** (`OCR`): recognizes text lines with Apple Vision, on device.
3. **Pictures** (`Conversion`, `LayoutAnalysis`): illustrations are cut out
   and the cover is taken from the first page; see
   [illustrations](illustrations.md).
4. **Layout** (`LayoutAnalysis`): see [layout analysis](layout-analysis.md).
   Note markers are located by colour, erased before step 2 and linked to
   the note texts here; see [notes](notes.md).
5. **Chapters** (`Conversion`): a new chapter starts at every level 1
   heading. Text before the first heading becomes a chapter named after the
   document.
6. **Export**: see [EPUB export](epub-export.md).

## Known limits

- Folder input only; PDF input is not implemented.
- A Vision request occasionally never answers (seen about once per few
  thousand pages, with and without other conversions running). Each request
  has a 180-second limit and is started up to three times; if that fails the
  tool stops with `timedOut` and the page's path instead of hanging. Whether
  a retry recovers a stuck request has not been observed yet.
- Headings set at body size are not detected, so a document that uses them
  comes out as a single chapter.
- Notes are found only when their markers are drawn as blue links, as the
  sample clean-page source does.
- No review step: the output is exactly what the heuristics produced.
