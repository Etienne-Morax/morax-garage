#!/usr/bin/env bash
# Prints the docs/CHANGELOG.md section for a version (anchor-based, matching the
# releaseNotes anchor written into release.json by package_release.sh).
#
# Usage: scripts/release-notes.sh [version]   (default: ./VERSION)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")}"
ANCHOR="${VERSION//./}"

NOTES="$(awk -v anchor="<a id=\"${ANCHOR}\"></a>" '
    $0 == anchor { found = 1; next }
    found && /^<a id=/ { exit }
    found { print }
' "$PROJECT_ROOT/docs/CHANGELOG.md")"

if [ -z "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ]; then
    printf 'FAIL no changelog section found for version %s (expected anchor <a id="%s"></a> in docs/CHANGELOG.md)\n' "$VERSION" "$ANCHOR" >&2
    exit 1
fi
printf '%s\n' "$NOTES"
