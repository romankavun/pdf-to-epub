# App: convert a folder and save the EPUB

The app's main window takes a folder of page images through the same
pipeline as [`pagescan`](pagescan-cli.md) and saves the result as an EPUB.
The result can be [reviewed](review.md) against the scans before saving,
but not edited yet: what the pipeline produces is what gets saved.

## Usage

1. **Open a folder**: press *Choose Folder…* (⌘O) or drop the folder on the
   window. The folder must hold one image per page directly inside it.
2. **Check the metadata**: the title is preset to the folder's name; the
   author is optional; the language is Ukrainian or English. English is
   always recognized as a second language.
3. **Convert**: the window shows the scan of the page being recognized,
   and how many pages are done. Only the scan is shown, not what was
   recognized on it. After the last page the progress bar reads
   *Assembling the document…* while layout analysis runs. The first page takes
   about a minute while Vision loads its model. *Cancel* returns to the
   metadata form.
4. **Review the numbers**: chapters, headings, paragraphs, illustrations,
   notes and whether a cover was found. *Needs attention* appears when note
   references or note texts could not be linked; see [notes](notes.md).
5. **Review…** (⌘R): see [review](review.md).
6. **Save EPUB…** (⌘S): the save panel suggests `<folder>.epub` next to the
   folder. After saving, *Show in Finder* reveals the file. The document can be
   saved more than once.

The interface is in English, with a Ukrainian localization
(`App/PDFToEPUB/Localizable.xcstrings`).

## How it is built

`ConversionModel` (`AppModel` module in `ScanCore`) holds the window's state
as one `phase`: empty, ready, converting, finished or failed. It talks to
the rest of the package through the `ConversionPipeline` protocol, so its
tests run against a fake with no files or Vision involved. `LivePipeline` is
the real one. The SwiftUI views in `App/` only render the phase and forward
button presses.

The page being recognized (`pageInProgress`) is derived from the count of
pages done, not reported by the pipeline: pages are recognized one after
another, so page N + 1 starts as soon as page N is reported done. The view
loads a scaled-down copy of the scan off the main actor and keeps the
previous scan on screen until the next one is ready.

`AppModel` imports Observation, not SwiftUI or AppKit, so the rule that
`ScanCore` has no UI imports still holds.

## Known limits

- Folder input only; PDF import is not built.
- Cancelling takes effect in the window at once, but Vision finishes the
  page it is on in the background before the pipeline stops.
- A finished conversion is saved as a [project](projects.md) beside the
  folder. Opening another folder or project closes the current one.
- Pages are shown as they come, about one a second; none is held on screen
  longer so it can be read.
- A failed conversion can only be retried from the first page.
- Errors other than a bad folder and a recognition timeout are shown with
  their technical description, in English.
- One language per document in the picker; other BCP 47 tags are available only
  from `pagescan`.
