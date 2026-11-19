# Projects: keeping a document and its corrections

A converted document is saved as a project so that a long document can be reviewed
over several sessions.

## Usage

- When a conversion finishes, the app writes `<folder or PDF name>.scanproject`
  next to the folder of scans or the PDF (`<name> 2.scanproject` if that exists). The
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
- **Convert Again** on the summary converts the scans again (for example
  after the recognition improved) and puts the result under the existing
  corrections. Corrections that no longer find their block are counted in
  the summary as *Corrections that no longer apply*.
- If the project cannot be written (a read-only disk, say), the summary says
  so; the document and the corrections stay usable until the window is closed.

## What is in the folder

```
Name.scanproject/
  project.json       the conversion: chapters, notes, where each block lies,
                     the paths of the scans (relative for `pages/`), the metadata (no image bytes)
  images/            one file per figure and the cover
  pages/             page images drawn from a PDF or prepared from paper scans
                     (absent for a folder of clean pages)
  corrections.json   the user's decisions
  ignored-words.json words the review no longer flags (optional)
```

Both JSON files carry `formatVersion` (1). Corrections have a file of their
own because they change after every edit and are small. Converting again
replaces `project.json` and `images/` and leaves `corrections.json` and `ignored-words.json` alone.
The folder is written beside the destination and moved into place, so a
crash while creating it leaves no half-written project.

## Known limits

- Scans in a folder are not copied into the project; their paths are stored.
  If the folder is moved or renamed, the review shows no page images (the
  document and EPUB export still work). Pages drawn from a PDF, and pages of a
  paper scan prepared for recognition ([scan preprocessing](scan-preprocessing.md)),
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
