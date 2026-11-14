# Projects: keeping a document and its corrections

A converted document is saved as a project so that a long document can be reviewed
over several sessions.

## Usage

- When a conversion finishes, the app writes `<folder name>.scanproject`
  next to the folder of scans (`<name> 2.scanproject` if that exists). The
  summary shows its name and *Show in Finder*. Nothing is asked.
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
                     the paths of the scans, the metadata (no image bytes)
  images/            one file per figure and the cover
  corrections.json   the user's decisions
```

Both JSON files carry `formatVersion` (1). Corrections have a file of their
own because they change after every edit and are small. Converting again
replaces `project.json` and `images/` and leaves `corrections.json` alone.
The folder is written beside the destination and moved into place, so a
crash while creating it leaves no half-written project.

## Known limits

- The scans are not copied into the project; their paths are stored. If the
  folder is moved or renamed, the review shows no page images (the document and
  EPUB export still work).
- Replacing the conversion of an existing project is not atomic: a crash in
  the middle leaves a project that reports itself as damaged.
- A project cannot be moved to another name from inside the app; moving the
  folder in Finder is fine.
- Undo history is not saved.
- One window, one document: opening another project or folder closes the
  current one.
