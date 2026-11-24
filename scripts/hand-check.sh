#!/bin/bash
# Builds the Debug app and opens it on a folder of pages or a sample set, for
# checking a change by hand (docs/testing.md, "Checking by hand").
#
#   scripts/hand-check.sh <folder>           open the folder (its project, if converted)
#   scripts/hand-check.sh --fresh <folder>   open a copy that has never been converted
#   scripts/hand-check.sh --clean            remove the copies made by --fresh
#
# A <folder> without a slash is a sample set in Samples/. A --fresh copy is
# Samples/_handcheck-<set>-<time>: hard links to the pages (no extra space; the
# importer skips symbolic links), with no project beside it, so the app offers
# Convert and the new project has the current format.
set -euo pipefail
cd "$(dirname "$0")/.."

samples=${PAGESCAN_SAMPLES_DIR:-Samples}
derived=$(pwd)/.build/hand-check
app="$derived/Build/Products/Debug/PDFToEPUB.app"

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "$samples"/_handcheck-*
    echo "removed the --fresh copies in $samples"
    exit 0
fi

fresh=false
if [[ "${1:-}" == "--fresh" ]]; then
    fresh=true
    shift
fi
source=${1:?usage: scripts/hand-check.sh [--fresh] <folder> | --clean}
[[ "$source" == */* ]] || source="$samples/$source"
[[ -d "$source" ]] || { echo "no folder $source" >&2; exit 1; }

if $fresh; then
    copy="$samples/_handcheck-$(basename "$source")-$(date +%H%M%S)"
    mkdir "$copy"
    ln "$source"/* "$copy"/
    source=$copy
fi
folder=$(cd "$source" && pwd)

echo "== building"
xcodebuild -project App/PDFToEPUB.xcodeproj -scheme PDFToEPUB -destination platform=macOS -derivedDataPath "$derived" build -quiet
# One instance at a time: quit an earlier hand-check app, never the user's own.
pkill -f "$derived/Build/Products/Debug/PDFToEPUB.app" 2>/dev/null && sleep 1 || true
open -n "$app" --args -UITestFolder "$folder"
echo "opened $folder"
echo "bundle id local.pdftoepub.PDFToEPUB; projects are written beside the folder"
