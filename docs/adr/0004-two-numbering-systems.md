# ADR 0004: A reference is linked to the notes that follow it, in the right numbering system

- Status: accepted
- Date: 2026-11-13
- Evidence: all four sample sets, re-run through OCR, marker location and
  layout analysis; only page numbers, marker positions and labels were
  inspected, plus two pages viewed to tell the two kinds of note apart.
- Refines decision 5 of [ADR 0003](0003-notes-by-colour-and-sequence.md).

## Context

Sample set C has two kinds of notes, numbered apart:

- **explanatory notes**, printed under a rule after each section, one to
  eight pages after the text that refers to them, numbered through the document
  (about 1 to 74);
- **sources**, cited throughout the text and listed at the end of the document
  (about 1 to 400). A source is often cited many times.

So most numbers below 75 exist twice. ADR 0003 linked a reference to the
matching note nearest to a cursor (the note after the furthest one referred
to so far). Once the first source at the end had been referred to, the
cursor stayed there and later explanatory references went to the source
with the same number. Before that happened, citations went to explanatory
notes. Of 64 references linked to explanatory notes, 43 came from more than
ten pages away, and 25 explanatory notes stayed in the body unlinked.

Earlier ideas that turned out not to fit:

- *Footnotes at the foot of the same page.* The notes under a rule are not
  page footnotes: on the clean-page source they close a section, and their references
  are on earlier pages.
- *Smaller type below the rule.* Line heights barely differ, and section-end
  notes in documents A and B look the same as these. Nothing in the layout says
  which numbering a note belongs to.

## Findings

| Question | Result |
|---|---|
| Where is the reference to an explanatory note? | Always before the note, within the section that the note closes: 0 to 8 pages earlier. |
| Is a number cited as a source and as an explanation in the same stretch of text? | Rarely. Where it is, the explanatory reference is the later one: it stands just before its section's notes. |
| What else breaks a section's group of notes? | A note text of several paragraphs: its later paragraphs become ordinary blocks between the notes. They carry no references. |
| What looked like notes but was not? | Eight times in document C (and once in document B), the engine reported the end of a line as a line of its own, starting with the erased marker and then `.`, `,` or a bullet. The analyzer took the marker for a note label. These false notes sat between real notes and drew references away. |

## Decision

1. A line that opens with a marker followed by closing punctuation (or the
   bullet that stands for a full stop) is the rest of the line above. It
   continues the block being assembled and is never a note.
2. Of the notes that carry a reference's number, the reference's **own**
   note is the nearest one after it that
   - lies in the first group of notes after the reference (notes with no
     reference between them; plain paragraphs between them are allowed), or
     after the document's last reference, where notes collected at the end are;
   - and has no later reference before it with the same number.
3. When no note is its own, the reference repeats an earlier citation and
   takes the furthest matching note ahead: the list a document cites again and
   again is the one at its end.
4. A reference with no matching note ahead (a reference back) keeps the
   cursor rule of ADR 0003, and an unreadable label keeps the next note in
   order.

## Consequences

Measured on the four sample sets:

| Document | Linked (before → after) | References without a note | Notes without a reference |
|---|---|---|---|
| A | 18 → 18 | 0 → 0 | 1 → 1 |
| B | 61 → 61 | 0 → 0 | 6 → 6 |
| C | 461 → 500 | 10 → 10 | 55 → 8 |
| D | 1 → 1 | 0 → 0 | 0 → 0 |

The output of sets A, B and D is identical before and after. In document C, 71
explanatory notes are linked, all from within ten pages before them (before:
51, with 43 references from further away). Set C also has eight fewer note
texts, the false ones. The links to sources were not checked one by one.

Limits:

- An explanatory note whose own reference was misread stays unlinked rather
  than taking a citation with the same number. One in document C has a reference
  that the marker detector merged with the citation next to it into a single
  marker (`21852`).
- The rules assume that notes follow the text that refers to them. A document
  that prints a note before its reference is linked by the fallback rules.
- Both systems must be told apart by where the notes are. Two systems
  collected in the same place (two lists at the end with the same numbers)
  are still decided by the cursor.
- The first references of a document are ambiguous when both systems start at
  the same number close together. The nearer note wins.
