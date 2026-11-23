# Projects: keeping a document and its corrections

A converted document is saved as a project so that a long document can be reviewed
over several sessions.

## Usage

- When a conversion finishes, the app writes `<folder or PDF name>.scanproject`
  next to the folder of scans or the PDF (`<name> 2.scanproject` if that is
  taken by something else). The
  summary shows its name and *Show in Finder*. Nothing is asked.
- Words ignored in the review's quick fixes are kept in the project too, in
  a file of their own (`ignored-words.json`), not as corrections: undo does
  not take them back.
- Every correction is written as soon as it is made. There is no save
  button, and quitting loses nothing.
- Open a project with *Choose Folder…* (⌘O) or by dropping it on the window:
  the app tells a project from a folder of scans. The document opens on the
  summary, with title, author and language restored, ready for *Review…* and
  *Save EPUB…* (exported with the corrections applied).
- A project is never converted again under its corrections
  ([ADR 0011](../adr/0011-no-convert-again.md)). Opening a folder or PDF
  that already has `<name>.scanproject` beside it shows *Already converted*
  with **Open Project**, and **Start Over…** in place of *Convert*. Start
  over asks first, converts the document into a new project, and only then
  moves the old one, with its corrections, to the Trash; a cancelled or
  failed run leaves it alone. If the old project cannot be moved, the
  summary says so and the new one is saved as `<name> 2.scanproject`.
- If the project cannot be written (a read-only disk, say), the summary says
  so; the document and the corrections stay usable until the window is closed.

## What is in the folder

```
Name.scanproject/
  project.json       the conversion: chapters, notes, where each block lies,
                     each block's style (from version 2), the page furniture,
                     the paths of the scans (relative for `pages/`), the metadata (no image bytes)
  images/            one file per figure and the cover
  pages/             page images drawn from a PDF or prepared from scanned pages
                     (absent for a folder of clean pages)
  corrections.json   the user's decisions
  ignored-words.json words the review no longer flags (optional)
```

Both JSON files carry `formatVersion`: 2 for `project.json`, 1 for
`corrections.json`. Version 2 adds the [styles](styles.md) of the conversion;
a version 1 project still opens, without styles (they cannot be recovered,
as the recognized lines are not kept: *Start over* makes a project that has
them). A newer version than the app knows is refused. Corrections have a file of their
own because they change after every edit and are small. A project is never
converted again ([ADR 0011](../adr/0011-no-convert-again.md)), so
`project.json` is written once.
The folder is written beside the destination and moved into place, so a
crash while creating it leaves no half-written project.

## Known limits

- Scans in a folder are not copied into the project; their paths are stored.
  If the folder is moved or renamed, the review shows no page images (the
  document and EPUB export still work). Pages drawn from a PDF, and pages of a
  scanned page prepared for recognition ([scan preprocessing](scan-preprocessing.md)),
  are different: they are moved into the project's `pages/` folder and stored relative to
  it, so the project works after the PDF is moved or deleted and after the
  project itself is moved. They cost disk space (about the size of the
  document's clean pages as PNG).
- Replacing the conversion of an existing project is not atomic: a crash in
  the middle leaves a project that reports itself as damaged.
- A project cannot be moved to another name from inside the app; moving the
  folder in Finder is fine.
- Undo and redo history is not saved.
- One window, one document: opening another project or folder closes the
  current one.
