# pdf-to-epub

Turns a scanned document into an EPUB 3 that keeps its structure, and lets a person correct what recognition got wrong. The terms below are the shared language of the code, the docs and the conversation.

## Input

**Document**:
The thing being converted: an ordered set of pages, from one PDF or one folder of page images.
_Avoid_: Document, scan (a scan is one kind of document)

**Page**:
One image of the document, in reading order.
_Avoid_: Sheet, picture (a picture is an illustration)

**Clean page**:
A page with one exact background colour, no skew and no scanner edges; it is read as it is and never prepared.
_Avoid_: Digital page, plain page

**Scanned page**:
A page photographed or scanned on a scanner bed, with grainy paper, edges and possible skew.
_Avoid_: Paper scan, physical scan, photo

**Input profile**:
The per-document decision whether its pages are scanned pages, taken from a sample of pages.
_Avoid_: Scan mode

**Prepared page**:
A scanned-page page after crop, cleanup and deskew; it replaces the original everywhere downstream.
_Avoid_: Cleaned page, processed page

## Recognition

**Line**:
One line of text with its word boxes, as returned by OCR. Vision's own paragraph grouping is not used.
_Avoid_: Row, text run

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

**Running header**:
Text repeated at the top or bottom of pages, such as a page number or document title; removed from the document.
_Avoid_: Header, footer

## Notes

**Note**:
A footnote or endnote of the source document, shown in the EPUB as a pop-up.
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
One series of note labels in a document; a document may have two, such as explanatory notes and sources.
_Avoid_: Note type

## Review and corrections

**Review**:
The screen that shows the page scan next to what was recognized, so a person can check and fix it.
_Avoid_: Preview, editor

**Correction**:
One recorded decision of the person, stored apart from recognition and applied on top of it.
_Avoid_: Edit, override, fix

**Block anchor**:
The place on a page by which a correction finds its block again after a new conversion.
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

## Output and storage

**Project**:
The saved state of one document: its recognized result, prepared or rendered pages and corrections, kept as a bundle beside the source.
_Avoid_: Session, workspace

**Conversion**:
One run of the pipeline from pages to a recognized document.
_Avoid_: Import, processing

**Chapter**:
A part of the EPUB that begins at a level 1 heading.
_Avoid_: Section

**Golden page**:
A page fixture with an expected document structure, used as the regression suite for layout analysis.
_Avoid_: Snapshot, sample page
