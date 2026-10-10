#!/usr/bin/env bash
# Uploads the release DMG to Morax One's Supabase Storage bucket and verifies
# that the object exists. Only the DMG is uploaded: release.json is committed
# into the Morax One repository (content/releases/garage.json), see
# docs/DISTRIBUTION.md.
#
# Usage:
#   MORAX_SUPABASE_URL="https://<project-ref>.supabase.co" \
#   SUPABASE_SERVICE_ROLE_KEY="..." \
#   scripts/upload_release.sh
#
# Environment:
#   MORAX_SUPABASE_URL          Supabase project URL (required)
#   SUPABASE_SERVICE_ROLE_KEY   Service role key (required; prompted if unset on a TTY)
#   MORAX_STORAGE_BUCKET        Storage bucket name (default: releases)
#   MORAX_VERSION               Override the version from ./VERSION

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

VERSION="${MORAX_VERSION:-}"
if [ -z "$VERSION" ]; then
    [ -f "$PROJECT_ROOT/VERSION" ] || fail "VERSION file not found at $PROJECT_ROOT/VERSION"
    VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
fi
[ -n "$VERSION" ] || fail "version is empty"

DMG_NAME="MoraxGarage-${VERSION}.dmg"
DMG_PATH="$PROJECT_ROOT/dist/release/$DMG_NAME"
BUCKET="${MORAX_STORAGE_BUCKET:-releases}"

if [ -z "${MORAX_SUPABASE_URL:-}" ]; then
    fail "MORAX_SUPABASE_URL is not set. Export your Supabase project URL, e.g. MORAX_SUPABASE_URL=https://<project-ref>.supabase.co"
fi
SUPABASE_URL="${MORAX_SUPABASE_URL%/}"
case "$SUPABASE_URL" in
    https://*) ;;
    *) fail "MORAX_SUPABASE_URL must start with https://" ;;
esac

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH. Run: ALLOW_UNNOTARIZED=1 scripts/package_release.sh"

KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"
if [ -z "$KEY" ] && [ -t 0 ]; then
    printf 'Supabase service role key (input hidden): '
    read -r -s KEY
    printf '\n'
fi
[ -n "$KEY" ] || fail "SUPABASE_SERVICE_ROLE_KEY is not set. Export it, or run this script from an interactive terminal."

LOCAL_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
LOCAL_SIZE="$(stat -f%z "$DMG_PATH")"

# Keep the key out of the process list and shell history: pass headers via a
# private curl config file removed on exit.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/morax-upload.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
chmod 700 "$WORK_DIR"
CURL_CONFIG="$WORK_DIR/curl.conf"
RESPONSE="$WORK_DIR/response.txt"
(
    umask 077
    {
        printf 'header = "Authorization: Bearer %s"\n' "$KEY"
        printf 'header = "apikey: %s"\n' "$KEY"
    } > "$CURL_CONFIG"
)

printf '==> Uploading %s (%s bytes) to bucket %s\n' "$DMG_NAME" "$LOCAL_SIZE" "$BUCKET"
HTTP_STATUS="$(curl -sS -K "$CURL_CONFIG" -o "$RESPONSE" -w '%{http_code}' \
    -X POST "$SUPABASE_URL/storage/v1/object/$BUCKET/$DMG_NAME" \
    -H "x-upsert: true" \
    -H "Content-Type: application/x-apple-diskimage" \
    --data-binary "@$DMG_PATH")"

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    cat "$RESPONSE" >&2
    printf '\n' >&2
    fail "upload failed (HTTP $HTTP_STATUS)"
fi
printf 'OK   upload accepted (HTTP %s)\n' "$HTTP_STATUS"

printf '==> Verifying the object exists (authenticated)\n'
INFO_STATUS="$(curl -sS -K "$CURL_CONFIG" -o "$RESPONSE" -w '%{http_code}' \
    "$SUPABASE_URL/storage/v1/object/info/$BUCKET/$DMG_NAME")"
if [ "$INFO_STATUS" -lt 200 ] || [ "$INFO_STATUS" -ge 300 ]; then
    cat "$RESPONSE" >&2
    printf '\n' >&2
    fail "object not found after upload (HTTP $INFO_STATUS)"
fi
printf 'OK   object present (HTTP %s)\n' "$INFO_STATUS"

printf '\nUpload complete\n'
printf '  Bucket  : %s\n' "$BUCKET"
printf '  File    : %s\n' "$DMG_NAME"
printf '  Size    : %s bytes\n' "$LOCAL_SIZE"
printf '  SHA-256 : %s\n' "$LOCAL_SHA"
printf 'Next: copy dist/release/release.json to content/releases/garage.json in the Morax One repo (see docs/DISTRIBUTION.md).\n'
