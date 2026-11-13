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
3. **Convert**: the window shows how many pages are done. The first page
   takes about a minute while Vision loads its model. *Cancel* returns to
   the metadata form.
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

`AppModel` imports Observation, not SwiftUI or AppKit, so the rule that
`ScanCore` has no UI imports still holds.

## Known limits

- Folder input only; PDF import is not built.
- Cancelling takes effect in the window at once, but Vision finishes the
  page it is on in the background before the pipeline stops.
- The converted document lives in memory only. Closing the window or opening
  another folder discards it; project persistence is a later milestone.
- A failed conversion can only be retried from the first page.
- Errors other than a bad folder and a recognition timeout are shown with
  their technical description, in English.
- One language per document in the picker; other BCP 47 tags are available only
  from `pagescan`.
