# ADR 0011: A project is never converted again under its corrections

- Status: accepted
- Date: 2026-11-23
- Amends: [ADR 0005](0005-corrections-apart-from-recognition.md)

## Context

ADR 0005 assumed a project could be converted again (*Convert Again*) and its
corrections carried onto the new recognition. In practice the user never needs
it, and it makes every new kind of state harder to design: corrections that no
longer apply, styles that would change under a corrected document, a style rule
that would have to reach blocks found by a later conversion.

## Decision

The recognition a project was converted with never changes. *Convert Again* is
removed. To get a fresh conversion, the user chooses **Start over**: after a
warning, the project's corrections are discarded and its source is converted
again into a new project that replaces the old one.

Rejected: no way to convert again (the user would delete the bundle in
Finder), and keeping the old project as a backup beside the new one (two
bundles for one source, with no way to bring corrections across anyway).

## Consequences

- Block anchors stay: merges and splits still shift the block list, and an
  anchor is how a correction finds its block among them. Rejected: block
  positions, which those same merges and splits make fragile.
- A text edit still stores the recognized text it was made against. It can no
  longer be stale through a new conversion, but it is a cheap check against a
  project file edited by hand.
- The summary's *Corrections that no longer apply* count goes away.
- Editing by style in the style overview is a batch of ordinary per-block
  corrections, not a rule over the style's signature: there are no later blocks
  for a rule to reach.
- Anything that re-runs layout analysis with other settings (per-document
  thresholds) is part of *Start over*, chosen before corrections are made.
