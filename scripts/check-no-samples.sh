#!/bin/bash
# Fails when anything that could be sample material is tracked or staged:
# the Samples/ folder (git-ignored, the home of the user's sample sets) or any
# image or PDF outside Tests/Fixtures and asset catalogs. `git add -f` goes
# around .gitignore; this does not.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=$(git ls-files | grep -E '^Samples/|\.(png|jpe?g|tiff?|heic|pdf)$' \
    | grep -vE '^Packages/ScanCore/Tests/Fixtures/|\.xcassets/' || true)
if [ -n "$bad" ]; then
    echo "Sample-like files are tracked or staged (sample sets must never be committed):" >&2
    echo "$bad" >&2
    echo "Unstage with: git rm --cached <file>" >&2
    exit 1
fi
