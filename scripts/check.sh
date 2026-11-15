#!/bin/bash
# Pre-commit check: formatting, lint and the fast tests (no Vision golden pages).
# Run before every commit. The Vision golden pages are run separately (docs/testing.md).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== swiftformat --lint"
swiftformat --lint .
echo "== swiftlint"
swiftlint --strict
echo "== swift test (without golden pages)"
swift test --package-path Packages/ScanCore --skip GoldenPageTests
echo "OK"
