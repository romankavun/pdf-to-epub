#!/usr/bin/env python3
"""Add or update a UI string in the String Catalog without reformatting it.

Run with `python3 -I` (isolated mode):

    python3 -I scripts/add-string.py "Save EPUB…" "Зберегти EPUB…" [--comment "…"]
    python3 -I scripts/add-string.py --check     # used by scripts/check.sh
    python3 -I scripts/add-string.py --format    # rewrite in Xcode's form

The file is written exactly as Xcode writes it, so a change shows up in the
diff as the changed entry only:

- `indent=2`, `" : "` between key and value, non-ASCII characters as they are;
- keys of every object sorted case-insensitively (ties: plain order), which is
  the order Xcode saves; a new key lands where Xcode would put it;
- an empty object as `{`, an empty line, `}` (Xcode's form), not `{}`;
- no newline after the last `}`.

`--check` exits 1 when the file differs from that form, for example after it
was rewritten with Python's default `json.dump` or re-sorted by plain order.
"""

import argparse
import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "App/PDFToEPUB/Localizable.xcstrings"
LANGUAGE = "uk"


def xcode_order(obj):
    """Return `obj` with the keys of every object in Xcode's order."""
    if isinstance(obj, dict):
        keys = sorted(obj, key=lambda k: (k.casefold(), k))
        return {k: xcode_order(obj[k]) for k in keys}
    if isinstance(obj, list):
        return [xcode_order(v) for v in obj]
    return obj


def serialize(catalog):
    """Serialize the catalog byte for byte as Xcode does."""
    text = json.dumps(xcode_order(catalog), indent=2, separators=(",", " : "), ensure_ascii=False)
    lines = []
    for line in text.split("\n"):
        stripped = line.rstrip()
        if stripped.endswith("{}") or stripped.endswith("{},"):
            indent = line[: len(line) - len(line.lstrip())]
            comma = "," if stripped.endswith(",") else ""
            lines.append(stripped[: stripped.rindex("{}")] + "{")
            lines.append("")
            lines.append(indent + "}" + comma)
        else:
            lines.append(line)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("key", nargs="?", help="the English base string, as written in the code")
    parser.add_argument("value", nargs="?", help="the Ukrainian translation")
    parser.add_argument("--comment", help="a comment for translators")
    parser.add_argument("--check", action="store_true", help="fail when the file is not in Xcode's form")
    parser.add_argument("--format", action="store_true", help="rewrite the file in Xcode's form")
    parser.add_argument("--file", type=Path, default=CATALOG, help="the .xcstrings file")
    args = parser.parse_args()

    original = args.file.read_text(encoding="utf-8")
    catalog = json.loads(original)

    if args.check:
        if serialize(catalog) != original:
            print(
                f"{args.file} is not in Xcode's format (key order or layout changed).\n"
                "Add strings with scripts/add-string.py; "
                "`python3 -I scripts/add-string.py --format` rewrites the file.",
                file=sys.stderr,
            )
            return 1
        return 0

    if args.format:
        args.file.write_text(serialize(catalog), encoding="utf-8")
        return 0

    if not args.key or args.value is None:
        parser.error("give the English key and the Ukrainian value, or --check / --format")

    entry = catalog["strings"].setdefault(args.key, {})
    if args.comment is not None:
        entry["comment"] = args.comment
    entry.setdefault("localizations", {})[LANGUAGE] = {
        "stringUnit": {"state": "translated", "value": args.value}
    }
    args.file.write_text(serialize(catalog), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
