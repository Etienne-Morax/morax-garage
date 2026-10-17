#!/usr/bin/env bash
# Uploads the release DMG to the private Cloudflare R2 bucket that Morax One
# serves downloads from (Morax One ADR 0019), then reads it back and checks its
# sha256. Only the DMG is uploaded: release.json is ingested into the Morax One
# repository with `pnpm release:ingest garage dist/release/release.json`, see
# docs/DISTRIBUTION.md.
#
# Usage:
#   scripts/upload_release.sh
#
# Requires wrangler logged in to the Cloudflare account that owns the bucket
# (`npx wrangler login`); no key is read or printed by this script.
#
# Environment:
#   MORAX_DOWNLOADS_BUCKET  R2 bucket (default: morax-downloads)
#   MORAX_VERSION           Override the version from ./VERSION
#   MORAX_WRANGLER          wrangler command (default: npx --yes wrangler@4.151.1)
#   MORAX_PROJECT_ROOT      Project root (default: this script's parent; used by tests)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${MORAX_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
APP_SLUG="garage"
CONTENT_TYPE="application/x-apple-diskimage"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

if [ -n "${MORAX_SUPABASE_URL:-}" ] || [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    fail "Supabase Storage is retired for release artifacts: they live in Cloudflare R2 (Morax One ADR 0019). Unset MORAX_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, log in with 'npx wrangler login', and run this script again."
fi

VERSION="${MORAX_VERSION:-}"
if [ -z "$VERSION" ]; then
    [ -f "$PROJECT_ROOT/VERSION" ] || fail "VERSION file not found at $PROJECT_ROOT/VERSION"
    VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
fi
[ -n "$VERSION" ] || fail "version is empty"

DMG_NAME="MoraxGarage-${VERSION}.dmg"
DMG_PATH="$PROJECT_ROOT/dist/release/$DMG_NAME"
MANIFEST_PATH="$PROJECT_ROOT/dist/release/release.json"
BUCKET="${MORAX_DOWNLOADS_BUCKET:-morax-downloads}"
OBJECT="$BUCKET/$APP_SLUG/$DMG_NAME"

read -r -a WRANGLER <<< "${MORAX_WRANGLER:-npx --yes wrangler@4.151.1}"

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH. Run: scripts/package_release.sh"
[ -f "$MANIFEST_PATH" ] || fail "manifest not found at $MANIFEST_PATH. Run: scripts/package_release.sh"

LOCAL_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
LOCAL_SIZE="$(stat -f%z "$DMG_PATH")"
MANIFEST_SHA="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]*\)".*/\1/p' "$MANIFEST_PATH" | head -n 1)"
[ "$MANIFEST_SHA" = "$LOCAL_SHA" ] \
    || fail "$DMG_NAME does not match release.json (sha256 $LOCAL_SHA, manifest says ${MANIFEST_SHA:-none}); rebuild with scripts/package_release.sh"

"${WRANGLER[@]}" whoami > /dev/null 2>&1 \
    || fail "wrangler is not logged in to Cloudflare. Run: npx wrangler login"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/morax-upload.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

printf '==> Uploading %s (%s bytes) to r2://%s\n' "$DMG_NAME" "$LOCAL_SIZE" "$OBJECT"
"${WRANGLER[@]}" r2 object put "$OBJECT" --file "$DMG_PATH" --content-type "$CONTENT_TYPE" --remote \
    || fail "upload to r2://$OBJECT failed"
printf 'OK   upload accepted\n'

printf '==> Reading the object back to verify it\n'
READ_BACK="$WORK_DIR/$DMG_NAME"
"${WRANGLER[@]}" r2 object get "$OBJECT" --file "$READ_BACK" --remote \
    || fail "could not read r2://$OBJECT back after upload"
REMOTE_SHA="$(shasum -a 256 "$READ_BACK" | awk '{print $1}')"
[ "$REMOTE_SHA" = "$LOCAL_SHA" ] \
    || fail "object read back from r2://$OBJECT has sha256 $REMOTE_SHA, expected $LOCAL_SHA"
printf 'OK   read back matches (sha256 %s)\n' "$REMOTE_SHA"

printf '\nUpload complete\n'
printf '  Object  : r2://%s\n' "$OBJECT"
printf '  Size    : %s bytes\n' "$LOCAL_SIZE"
printf '  SHA-256 : %s\n' "$LOCAL_SHA"
printf 'Next: in the Morax One repo, run pnpm release:ingest garage %s\n' "$MANIFEST_PATH"
