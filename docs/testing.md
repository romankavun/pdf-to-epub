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
  failure is the same failure on every run.

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
- With `REQUIRE_EPUBCHECK=1` a missing epubcheck **fails** the test. Use it before a
  release so the check cannot be skipped by accident.

There is no CI: checks run locally (`scripts/check.sh`, and the golden pages by hand).

## Not yet covered

Not covered by any test: the layout and look of the views (colours, spacing,
the scan overlay in `PageScan`), the text selection and cursor handling in the
editor (`TextSelection` in `BlockCard`), the file panels, and the position of
the quick-fix row (a known defect, `docs/backlog.md`). The sheet that picks
which similar blocks to change (`CandidateSheet`) has no UI test either: it
needs similar blocks, which the synthetic pages do not reliably give.

## What covers the views

Views stay thin on purpose, so most of what they decide is unit tested in
`AppModel`: which buttons a selected block shows (`Item.actions`), whether the
editor offers a split (`offersSplit`), how a frame is outlined (`outline`),
apply-to-all (`acceptTypeProposalForAll`), plus merge, split, undo, proposals
and editing (`ReviewItemPresentationTests`, `ReviewEditingTests`). The views
map those values to buttons and colours one to one. What is left is checked
by the UI tests below: that the buttons exist, are wired to the model and the
screens change.

## UI tests (XCUITest)

`ConvertReviewSaveTests` is the end-to-end scenario in `App/PDFToEPUBUITests`: open a folder of pages,
convert, open the review, make the first block a level 3 heading, save the
EPUB, and check that the file exists and contains `<h3`.

`ReviewScenarioTests` are short, independent scenarios, each launching the app
on its own folder: an empty folder shows the failure screen (no Vision, a few
seconds); ignore a block and undo; open the text editor of a block and cancel it; merge with the next block and undo; make a block a heading and
dismiss the offer to repeat it. Vision decides which blocks exist, so these
assert on what a click does, not on recognized text. The merge and offer
scenarios are **skipped** (not failed) when the synthetic pages give no second
block or no similar block. Each converting scenario pays the conversion again
(with a warm model about 20 s).

```bash
xcodebuild -project App/PDFToEPUB.xcodeproj -scheme PDFToEPUB test
```

It is **not** part of `scripts/check.sh`: it needs a logged-in desktop
session, drives the real window and waits for the first Vision request (over a
minute). Run it by hand before a release or after changing the review or save
flow.

How it avoids the system file panels: in Debug builds the app reads two launch
arguments (`UITestHooks.swift`): `-UITestFolder <path>` opens that folder when
the window appears, `-UITestOutput <path>` makes "Save EPUB…" write there
without asking. Release builds ignore them. The views the test drives carry
accessibility identifiers (`convertButton`, `reviewButton`, `blockCard`,
`typeMenu`, `typeHeading3`, `typeIgnore`, `blockEditor`, `failureScreen`,
`saveButton`, `exportSaved`).

The pages are drawn by the test itself (`PageFolder.swift`, invented text):
the package's `TestSupport` belongs to another package's test target and cannot
be imported, and a tiny CoreText renderer is simpler than a build script.

### One-time macOS setup

- **Developer mode** (Privacy & Security > Developer Mode, or
  `sudo DevToolsSecurity -enable`) must be on, or the runner fails with "Timed
  out while enabling automation mode". Your user must be in the `_developer`
  group. `DevToolsSecurity -status` can still print "disabled" on a machine
  where the test passes, so trust the test run, not that command.
- The first run asks to allow **PDFToEPUBUITests-Runner** to control the
  computer (System Settings > Privacy & Security > Accessibility). Allow it
  and run again. Do not touch the mouse or keyboard while the test runs.

### Known flake: Vision `e5rtError` (cause not found)

Once, when an agent session ran this test, the first Vision request failed
with `e5rtError` (code 13, Neural Engine), the app showed "Could not convert
the document" and the test timed out after 420 s. The same error was seen earlier
in the OCR tests run by other agent sessions. It did not reproduce in a later
run: the unchanged test passed in 82 s. What was learned:

- A sandbox of the agent's shell is **not** the cause: XCUITest launches the
  app through system services, outside the shell's process tree.
- Forcing Vision onto the CPU was tried and **not adopted**: the test passed
  with it too (19 s, but that run had a warm model cache, so it is not a fair
  speed comparison), which proves nothing about the cause. The likeliest
  explanation, unproven, is a Neural Engine busy with or unavailable to
  another process. If it comes back, retry first; re-test the CPU-only idea
  only against a cold start (needs the model cache location found and
  cleared, or a reboot).
- 20 runs on 4 sample sets (5 pages each) passed 18 times; the 2 failures
  (the same document) were in the review step ("no blocks", "no type menu"), not
  in OCR. Not investigated: a possible flake or a real defect on that document.

Typing into the editor is not tested: synthesized key events did not reach
the `TextEditor` (its accessibility value stayed unchanged after `typeText`, a
long string timed out). Not known whether this is a runner limit or a real
focus problem; saving edited text is covered by `ReviewEditingTests`.

The tests do not assert on the position of the quick-fix popover (a known
defect, `docs/backlog.md`).
