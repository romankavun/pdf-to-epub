# pdf-to-epub

Turns a scanned source into an EPUB 3 that keeps its structure, and lets a person correct what recognition got wrong. The terms below are the shared language of the code, the docs and the conversation.

## Input

**Source**:
The thing being converted: an ordered set of pages, from one PDF or one folder of page images.
_Avoid_: Scan (a scan is one kind of source), input file

**Page**:
One image of the source, in reading order.
_Avoid_: Sheet, picture (a picture is an illustration)

**Clean page**:
A page with one exact background colour, no skew and no scanner edges; it is read as it is and never prepared.
_Avoid_: Digital page, plain page

**Scanned page**:
A page photographed or scanned on a scanner bed, with grainy paper, edges and possible skew.
_Avoid_: Paper scan, physical scan, photo

**Input profile**:
The per-source decision whether its pages are scanned pages, taken from a sample of pages.
_Avoid_: Scan mode

**Prepared page**:
A scanned-page page after crop, cleanup and deskew; it replaces the original everywhere downstream.
_Avoid_: Cleaned page, processed page

## Recognition

**Line**:
One line of text with its word boxes, as returned by OCR. Vision's own paragraph grouping is not used.
_Avoid_: Row, text run

**Document**:
The recognized result of a conversion: the blocks and chapters that the review edits and the EPUB export reads. Only ever our own result; the parts of an EPUB are called its navigation file and package file in prose.
_Avoid_: Text, output

**Block**:
A unit of document structure: a heading, a paragraph or a figure.
_Avoid_: Element, section, region

**Heading**:
A block that titles a part of the document, with a level; level 1 starts a chapter.
_Avoid_: Title, header

**Paragraph**:
A block of running text, joined across lines and pages.
_Avoid_: Text block

**Figure**:
A block that is an illustration with its caption.
_Avoid_: Image block

**Illustration**:
A picture cropped out of a page and embedded in the EPUB.
_Avoid_: Image, picture

**Caption**:
The text attached to an illustration.
_Avoid_: Label, legend

**Page furniture**:
Lines recognition left out of the document because they belong to the page, not the text, such as running headers and page numbers; kept so the style overview can show them.
_Avoid_: Removed line, running line, deleted line

**Running header**:
Text repeated at the top or bottom of pages, such as the source's or the chapter's title; one kind of page furniture.
_Avoid_: Header, footer

## Notes

**Note**:
A footnote or endnote of the source, shown in the EPUB as a pop-up.
_Avoid_: Footnote (too narrow), annotation

**Note marker**:
The coloured mark in the page image where a note is referred to, found from pixels.
_Avoid_: Link, superscript

**Note reference**:
The place in the text that points to a note, carrying the note's label.
_Avoid_: Citation, anchor

**Note text**:
The paragraph that opens with a label and holds a note's content.
_Avoid_: Note body

**Note label**:
The number printed on a reference and on its note text.
_Avoid_: Note number (numbers repeat across numbering systems)

**Numbering system**:
One series of note labels in a source; a source may have two, such as explanatory notes and cited works.
_Avoid_: Note type

## Review and corrections

**Review**:
The screen that shows the page scan next to what was recognized, so a person can check and fix it.
_Avoid_: Preview, editor

**Correction**:
One recorded decision of the person, stored apart from recognition and applied on top of it.
_Avoid_: Edit, override, fix

**Block anchor**:
The place on a page by which a correction finds its block again after merges and splits shift the block list.
_Avoid_: Block ID

**Proposal**:
An offer to apply a correction to similar blocks across the document, awaiting confirmation.
_Avoid_: Suggestion, propagation

**Quick fix**:
A replacement suggested for one flagged word, recorded as an ordinary text edit.
_Avoid_: Autocorrect

**Suspicious word**:
A word flagged as a likely OCR misreading by a rule such as mixed scripts or digits inside a word.
_Avoid_: Error, typo

**Ignored block**:
A block the person left out of the document; it stays visible in review.
_Avoid_: Deleted block

**Style**:
A group of blocks that look alike on the page and were given the same type for the same reason.
_Avoid_: Class, category, block kind

**Deciding rule**:
The reason layout analysis gave a block its type, such as "body size and bold" or "opens with a note label".
_Avoid_: Heuristic, reason code

**Style overview**:
The screen that lists a document's styles with samples, so a person can see what recognition made of the document at a glance.
_Avoid_: Style map, style guide (a guide prescribes; the overview only shows)

**Example**:
One of the few blocks the style overview shows to illustrate a style, taken from pages spread across the document.
_Avoid_: Sample (a sample set is the user's scans), specimen

## Output and storage

**Project**:
The saved state of one conversion: its document, prepared or rendered pages and corrections, kept as a bundle beside the source.
_Avoid_: Session, workspace

**Conversion**:
One run of the pipeline from a source's pages to a document.
_Avoid_: Import, processing

**Start over**:
Discarding a project's corrections and converting its source again; the only way a source is converted twice.
_Avoid_: Convert again, reconvert

**Chapter**:
A part of the EPUB that begins at a level 1 heading.
_Avoid_: Section

**Golden page**:
A page fixture with an expected document structure, used as the regression suite for layout analysis.
_Avoid_: Snapshot, sample page
