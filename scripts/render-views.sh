#!/bin/bash
# Draws the review screen of a saved project to PNG files, without the screen.
# Usage: scripts/render-views.sh <project.scanproject> [page] [style title]
# Prints the paths of the pictures (blocks, styles, style; light and dark).
# See docs/testing.md, "Looking at a view".
set -euo pipefail
cd "$(dirname "$0")/.."

project=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
output=${RENDER_OUTPUT:-${TMPDIR:-/tmp}/pdftoepub-renders}
rm -f "$output"/*.png 2>/dev/null || true

# xcodebuild passes TEST_RUNNER_<NAME> to the test as <NAME>.
TEST_RUNNER_RENDER_PROJECT="$project" \
TEST_RUNNER_RENDER_OUTPUT="$output" \
TEST_RUNNER_RENDER_PAGE="${2:-1}" \
TEST_RUNNER_RENDER_STYLE="${3:-}" \
    xcodebuild -project App/PDFToEPUB.xcodeproj -scheme PDFToEPUB \
    -only-testing:PDFToEPUBRenderTests test 2>&1 |
    grep -E "RENDERED|: error:|XCTAssert|Test Suite .* (passed|failed)|skipped" || true
ls "$output"/*.png
