#!/bin/bash
# Pre-commit check: formatting, lint and the fast tests (no Vision golden pages).
# Run before every commit; CI runs the same plus the golden pages and the app build.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== swiftformat --lint"
swiftformat --lint .
echo "== swiftlint"
swiftlint --strict
echo "== swift test (without golden pages)"
swift test --package-path Packages/ScanCore --skip GoldenPageTests
echo "OK"
