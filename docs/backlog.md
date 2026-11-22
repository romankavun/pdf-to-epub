# Backlog

The backlog lives in GitHub Issues for `romankavun/pdf-to-epub`
([open issues](https://github.com/romankavun/pdf-to-epub/issues)); this page is
only an index. Conventions: [issue tracker](agents/issue-tracker.md), labels:
[triage labels](agents/triage-labels.md).

- Defects carry `bug`, planned improvements carry `enhancement`; new items also
  get `needs-triage` until they are evaluated.
- Each item becomes a test first (TDD rule in `CLAUDE.md`). Fix it in a commit or
  PR that says `Fixes #N`; GitHub closes the issue. Do not keep a second copy of
  the item here.
- Found a new defect or idea: `gh issue create`, not an edit to this file. Never
  copy text from the sample sets into an issue (the repository is public); page
  numbers are fine.
- Printed page N is page image N + 1 in the user's sample set about Ukrainian
  folk demonology.

## Where things were when the backlog moved to issues (2026-11-22)

Defects (the numbers in the old backlog are in brackets):

| Issue | Defect |
|---|---|
| [#1](https://github.com/romankavun/pdf-to-epub/issues/1) | Lists not recognized (1). Closed, never reproduced |
| [#2](https://github.com/romankavun/pdf-to-epub/issues/2) | Part of a line missing from OCR output (2). Closed, no named source |
| [#3](https://github.com/romankavun/pdf-to-epub/issues/3) | Dash read twice at a line break (3) |
| [#4](https://github.com/romankavun/pdf-to-epub/issues/4) | Next page's heading taken into a note (4) |
| [#5](https://github.com/romankavun/pdf-to-epub/issues/5) | Bottom notes not all recognized (5) |
| [#6](https://github.com/romankavun/pdf-to-epub/issues/6) | One paragraph comes out as three (7) |
| [#7](https://github.com/romankavun/pdf-to-epub/issues/7) | Only two heading levels (8) |
| [#8](https://github.com/romankavun/pdf-to-epub/issues/8) | First contents entry becomes a heading (9) |
| [#9](https://github.com/romankavun/pdf-to-epub/issues/9) | Caption of a full-page picture not attached (10) |
| [#10](https://github.com/romankavun/pdf-to-epub/issues/10) | Lines missing where blocks touch (11) |
| [#11](https://github.com/romankavun/pdf-to-epub/issues/11) | Suspicious word counts disagree (12) |
| [#12](https://github.com/romankavun/pdf-to-epub/issues/12) | Quotes and attributions become headings (16). Closed, no evidence |
| [#13](https://github.com/romankavun/pdf-to-epub/issues/13) | Foreign quotations flagged as misrecognized (19) |

Improvements: [#14](https://github.com/romankavun/pdf-to-epub/issues/14) to
[#22](https://github.com/romankavun/pdf-to-epub/issues/22) are review-screen and
summary ideas; [#23](https://github.com/romankavun/pdf-to-epub/issues/23) to
[#30](https://github.com/romankavun/pdf-to-epub/issues/30) are postponed
("Later") work.
