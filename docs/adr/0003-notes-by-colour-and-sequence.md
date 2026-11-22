# ADR 0003: Notes are located by colour, erased before OCR, and linked by label and order

- Status: accepted
- Date: 2026-11-13
- Evidence: spikes on pages of the four sample sets (clean pages);
  only marker geometry and the short labels were inspected.
- Resolves the open question of ADR 0001: "does re-recognising a cropped
  note reference give correct digits?"

## Context

The sample sets draw a note reference, and the label that opens the text of a
note, as a blue link. Vision fuses a reference into the word before it and
often misreads it (ADR 0001), so neither the text of the word nor the label
can be trusted as recognized in place.

## Findings

| Question | Result |
|---|---|
| Is colour a reliable locator? | Yes. A pixel whose blue channel exceeds red and green by more than 50 belongs to a link; body text never does. |
| What else is blue? | Contents entries (whole lines) and, potentially, web addresses. A contents entry has no dark text beside it; an address is far wider than a marker. |
| Re-recognising one cropped, enlarged marker | Unreliable. Two- and three-digit numbers are mostly read; a single character (`I`, `c`, `7`) frequently gives nothing. Roughly three markers in four were right. |
| Recognising all markers of a page laid out in one row | Clearly better: most labels come back, with look-alike errors (`I0`, `2I`, Cyrillic `П` for `II`). Some rows still fail completely, so a per-marker retry is kept as a fallback. |
| Erasing markers before page OCR | Works: the words around the marker are read cleanly. A full stop left alone after the gap is sometimes read as a bullet. |
| Are references sequential? | No. One sample set cites sources: the same note is referred to repeatedly and out of sequence, so references cannot be matched to notes by order. Note texts, however, are numbered in sequence within a run. |
| How are endnotes set? | In one document as a numbered list: a list number, then the note's own label, then the text, with a hanging indent. |

## Decision

1. `NoteMarkerDetector` (pure, on `PageBitmap`) finds markers: a run of
   link-coloured pixels at most four line-heights wide with dark, colourless
   text right beside it.
2. The OCR engine recognizes the page with marker boxes painted over
   (`recognize(imageAt:erasing:)`), and reads the labels separately from a
   synthetic strip (`readLabels(inImageAt:regions:)`).
3. The engine reports word boxes; a marker is placed after the last word
   whose centre lies to its left. A marker before the first word of a line
   that starts a paragraph makes that paragraph the text of a note.
4. Labels of note texts are repaired per run of consecutive notes
   (`NoteNumbering`): the kind of numbering (arabic, roman, letters) and the
   sequence that most readings agree on win; unread labels are filled in;
   an unreadable run continues the previous one.
5. References are linked by label (`NoteLinker`): to the note carrying the
   same number, the nearest one when several do; to the next note in order
   only when the label is unreadable or matches nothing. An earlier design
   walked references and notes in parallel and used labels for small
   corrections; it failed on a sample set that cites sources, where one
   note is referred to many times and out of sequence.
6. What cannot be linked is kept visible and counted: a reference stays as
   its label in the text, a note text stays as a paragraph.

## Consequences

- Two more passes per page (pixel scan, label strip) and a second Vision
  request on pages with markers. A 150-page document still converts in about a
  minute.
- `OCREngine` now has two requirements; fakes return canned labels.
- While measuring, a Vision request on a 380-page document twice never returned
  (process idle), once with no other conversion running. Requests therefore
  run under `Deadline`: a time limit, the stuck request abandoned, up to
  three attempts, then `OCRError.timedOut`. The helper is unit-tested; a
  recovery from a real stuck request has not been observed.
- Endnote lists carry a list number before the label and a hanging indent;
  OCR misreads the list number often (`IO.`, `39-`), so it is matched
  loosely and only directly before a marker.
- The link colour is fixed to "distinctly blue". Another reader theme needs
  the threshold exposed, or a learned link colour.
- Scanned pages have no coloured markers; superscript detection by size and
  position is a separate piece of work.
- Two numbering systems interleaved in one document (letters for one kind of
  note, numbers for another, collected in different places) were not told
  apart; the cursor linked some references to the wrong run. Superseded by
  [ADR 0004](0004-two-numbering-systems.md).
