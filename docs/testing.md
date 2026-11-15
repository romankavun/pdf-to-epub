# Testing

```bash
swift test --package-path Packages/ScanCore                      # everything
swift test --package-path Packages/ScanCore --skip GoldenPageTests   # without the Vision runs
swift test --package-path Packages/ScanCore --filter GoldenPageTests # golden pages only
```

Before every commit run `scripts/check.sh`: `swiftformat --lint`,
`swiftlint --strict` and the tests without the Vision golden pages.

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

## Property tests

`Packages/ScanCore/Tests/InvariantTests` states things that must hold for
*every* document, not for one hand-built example, and checks them on generated
documents. Losing a user's corrections is the most expensive kind of bug, so
those come first.

| Suite | Property |
|---|---|
| `ProjectStoreInvariantTests` | save then load returns an equal document, block and note sources, page URLs, corrections of every kind and ignored words (unicode, markup and control characters in the text); converting again keeps the corrections; pages moved into the bundle are readable after loading |
| `CorrectionsInvariantTests` | after random retypes, edits, word replacements, merges, splits, resets and undo/redo, converting again (boxes moved by a fraction of a line, note labels recounted) gives the same document with nothing unapplied; undo right after a change restores the exact earlier corrections, document and ignored blocks, and redo the later ones; proposing a type to similar blocks and applying it twice changes nothing the second time and one undo takes the whole propagation back |
| `JoiningInvariantTests` | a draft built from lines, and whole pages run through `LayoutAnalyzer`, contain exactly the letters of the input (hyphens, spaces and digits are ignored: joining may add a space and a page number is dropped on purpose) |
| `EPUBInvariantTests` | in the exported package every `href`/`src`/fragment points at an existing file and id; ids are unique per document; every file of the archive is in the manifest and every manifest item is in the archive; the spine refers to manifest items; every noteref has a footnote and every footnote a noteref and a back link; the table of contents has one working entry per chapter; all XML is well-formed |

### How they work

Swift Testing has no property testing, so `TestSupport` has a small one:

- `SeededGenerator` is a deterministic random number generator
  (SplitMix64); `DocumentGenerator` draws valid documents and conversions from it
  (`TextStyle` tidy or wild, `Layout` tidy or wild: tidy stacks blocks
  without overlap so that a block can be found again by its place).
- `Property.check(name, cases:) { generator in ... }` runs the closure for
  each case with its own seed. The closure states the property with
  `Property.require` / `Property.requireEqual`. The first failing case is
  recorded as one issue and the run of that property stops.
- The seeds are fixed (`Property.baseSeed`), so the suite is deterministic: a
  failure in CI is the same failure locally.

### Reproducing a failure

A failure prints `Reproduce with PROPERTY_SEED=<n>`:

```bash
PROPERTY_SEED=9856676368292174555 swift test --package-path Packages/ScanCore --filter InvariantTests
```

runs only that case. `PROPERTY_CASES=2000` runs more cases than the default
(60 to 300 per property) for a deeper search, for example before a release
or after changing corrections or the exporter.

A property that fails is a finding: do not loosen it. If it exposes a bug
that is not fixed at once, keep the test, wrap the call in `withKnownIssue`
naming the `docs/backlog.md` item, and fix the bug later.

### Limits

- The generators do not run Vision or the pixel analysis, so nothing here
  says the *recognized* document is right, only that what is done with it is
  consistent.
- Corrections are replayed against a re-run of layout analysis that is
  simulated (moved boxes, new labels), not a real second OCR run.
- A split that cuts off a sliver of a block (under a quarter of its
  height) is not generated: its area is so small that moving it by a few
  thousandths of the page height means it is no longer found.
- `epubcheck` is the validator of the format; these tests only check that
  the package is internally consistent.

## epubcheck

The `passes epubcheck` test validates a generated EPUB with `epubcheck
--failonwarnings`. The launcher is looked up in `EPUBCHECK_PATH`, the
Homebrew locations and `PATH`.

- Without epubcheck the test is **skipped** with the reason `EPUB NOT
  VALIDATED ...`, also printed to stderr as a warning.
- With `REQUIRE_EPUBCHECK=1` a missing epubcheck **fails** the test. CI sets
  it, so the check cannot be skipped there by accident.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests, on
`macos-26` runners, with two jobs:

| Job | Steps |
|---|---|
| `build-and-test` | newest installed Xcode, `brew install epubcheck swiftformat swiftlint`, `swiftformat --lint`, `swiftlint --strict`, unit tests (`--skip GoldenPageTests`, `REQUIRE_EPUBCHECK=1`), `xcodebuild` of the app |
| `golden-pages` | the `.golden` suite only, `continue-on-error: true` |

Golden pages are a separate job because they depend on the Apple Vision
release of the runner: a different OS build can change OCR output without
any layout regression. They are reported on their own, and can be made a
required check once their behaviour on the runner is known. Real-document tests
need `PAGESCAN_SAMPLES_DIR`, which CI never sets, so they are skipped.

The workflow has not yet run on a real runner; the first run may need
adjustments (runner label, Xcode path, Homebrew formulae).

## Not yet covered

UI tests are a separate step of the testing plan.
