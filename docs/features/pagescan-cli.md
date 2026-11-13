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

It ends with a summary: chapters, headings, paragraphs, figures, and whether
a cover was found.

## What it does

1. **Import** (`Importing`): takes the `png`, `jpg`, `jpeg`, `tif`, `tiff`
   and `heic` files directly inside the folder, ordered the way Finder sorts
   names (`page_2` before `page_10`). Hidden files and subfolders are ignored.
2. **OCR** (`OCR`): recognizes text lines with Apple Vision, on device.
3. **Pictures** (`Conversion`, `LayoutAnalysis`): illustrations are cut out
   and the cover is taken from the first page; see
   [illustrations](illustrations.md).
4. **Layout** (`LayoutAnalysis`): see [layout analysis](layout-analysis.md).
5. **Chapters** (`Conversion`): a new chapter starts at every level 1
   heading. Text before the first heading becomes a chapter named after the
   document.
6. **Export**: see [EPUB export](epub-export.md).

## Known limits

- Folder input only; PDF input is not implemented.
- Run one conversion at a time: with several `pagescan` processes running
  in parallel, a Vision request has been seen to hang.
- Headings set at body size are not detected, so a document that uses them
  comes out as a single chapter.
- Notes are not linked: note references stay in the text as recognized, and
  note bodies appear as ordinary paragraphs.
- No review step: the output is exactly what the heuristics produced.
