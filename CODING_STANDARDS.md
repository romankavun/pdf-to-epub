# Coding standards

Read during review. Mechanical rules (formatting, force-unwraps, missing
DocC, module import boundaries) are enforced by `scripts/check.sh`
(SwiftFormat, SwiftLint, tests) and are not repeated here.

## Judgement calls

- **Comments say why.** A public type or function has a DocC comment that
  explains its purpose and any non-obvious behavior, not a restatement of its
  name.
- **Glossary terms.** Code, docs and commit messages use the terms of
  [GLOSSARY.md](GLOSSARY.md). A new or renamed term updates the glossary in the
  same change.
- **Seams are protocols.** Collaborators arrive through initializers as
  protocols; no singletons, no global mutable state. Vision, the spell checker
  and the file system sit behind a protocol so tests use a fake.
- **Typed errors per module.**
- **Heavy work leaves the main actor.** OCR and image processing report
  progress and support cancellation.
- **Prefer Apple frameworks.** A dependency, network call or out-of-scope
  feature needs the user's approval first.
- **Tests first.** Every behavior change comes with a test that was red before
  the change; a bug fix starts with a test that reproduces it. Golden pages
  run for every heuristic change.
- **Documentation travels with the feature.** A user-facing feature has a page
  in `docs/features/`, linked from `docs/README.md`; a significant design
  choice has a short ADR in `docs/adr/`.
- **UI strings are localizable**: String Catalog, English base, Ukrainian
  localization.
- **A view change was looked at.** A change to a SwiftUI view comes with
  evidence that someone saw it: pictures from `scripts/render-views.sh` for
  the review screen, or a recorded hand check with `scripts/hand-check.sh`
  for clicks, menus and undo ([testing](docs/testing.md), "Looking at a
  view" and "Checking by hand"). A report that says the UI was not checked
  means the change is not done.
- **Commits** follow Conventional Commits, small and focused.
