# Testing

```bash
swift test --package-path Packages/ScanCore                      # everything
swift test --package-path Packages/ScanCore --skip GoldenPageTests   # without the Vision runs
swift test --package-path Packages/ScanCore --filter GoldenPageTests # golden pages only
```

Most tests are unit tests over hand-built values. Two kinds need more:

## Golden pages

A golden case is a short synthetic document drawn by code
(`Packages/ScanCore/Tests/TestSupport/SyntheticPage.swift`), converted with
the real pipeline (marker colour, picture bands and Apple Vision OCR), and
compared with an expected structure stored in
`Packages/ScanCore/Tests/Fixtures/golden/<name>.json`. The pages are invented
text: commercial material never enter the repository.

What a file holds (`DocumentSnapshot`): the blocks in reading order (kind,
heading level, text, labels of the notes a block refers to), the notes
(label, text) and the counts of unlinked references and notes. Kinds, levels,
note links and counts must match exactly; text only has to be about 80%
alike, so a different OCR release that misreads a letter does not fail the
suite.

The suite is tagged `.golden` and runs serially. The first Vision request of
a process loads the model and can take a minute.

### Adding a case

1. Add a `@Test` to `GoldenPageTests` that calls `runGolden(GoldenCase(...))`
   with a name and the pages. A page is a list of elements: `.line("> text{1}")`
   (`>` indents, `{label}` is a link-blue note marker), `.heading`,
   `.picture(height:caption:)`, `.rule`, `.pageNumber`, `.gap`, `.moveTo`.
   Start with `SyntheticPage.prose()`: layout analysis measures the body margin
   from the most common left edge, which a couple of short pages lack.
2. Write the expected JSON by hand from what the document **should** produce, or
   record it from the current result (below) and check every line.
3. Run the suite.

### Regenerating expectations

```bash
GOLDEN_RECORD=1 swift test --package-path Packages/ScanCore --filter GoldenPageTests
```

This rewrites the JSON files from the actual result instead of comparing.
Review `git diff` before committing: a recorded file that encodes a defect
turns the defect into the expectation.

### Known defects

A case with `knownIssue: "docs/backlog.md defect N"` is compared inside
`withKnownIssue`: the suite stays green while the defect exists, and fails
with "expected an issue" once it is fixed. Then remove `knownIssue`.

Current cases:

| Case | Covers |
|---|---|
| `basic` | heading, paragraphs, illustration with caption, a linked note |
| `note-before-heading`, `note-before-heading-roman` | backlog defect 4: a note across an almost empty page, then a heading. **Not reproduced** with synthetic pages; kept as guards |
| `bottom-notes` | backlog defect 5 with arabic labels: passes |
| `bottom-notes-roman` | backlog defect 5: reproduced (known issue). Long roman labels such as `LXXVIII` are not all found by the marker detector and those notes stay paragraphs with the label in the text; the width limit `maximumAspect` in `NoteMarkerDetector` is the first suspect, not yet confirmed |

## Not yet covered

CI, `epubcheck` as an automated test, EPUB round trips and UI tests are
separate steps of the testing plan.
