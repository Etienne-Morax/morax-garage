#!/usr/bin/env bash
# Morax Garage Release Packaging Script
# Exposes the single release command chaining:
# 1. Preflight (environment & tooling assertion)
# 2. Universal compilation & bundle assembly
# 3. Developer ID signing (with hardened runtime)
# 4. DMG assembly and signing
# 5. Notarization & Stapling
# 6. Measured manifest generation (Morax One §3.3 contract)
# 7. Distribution verification
#
# Usage:
#   scripts/package_release.sh
#
# Environment:
#   MORAX_SIGN_IDENTITY    Developer ID Application identity (default: the team's one in the keychain)
#   MORAX_NOTARY_PROFILE   notarytool keychain profile name (default: morax-notary)
#   MORAX_NOTARY_KEYCHAIN  keychain holding that profile (default: login keychain)
#   MORAX_TEAM_ID          Apple Developer Team ID (10 chars, optional/checked)
#   MORAX_VERSION          override the version from ./VERSION
#   MORAX_BUILD            override the generated build number
#   ALLOW_UNNOTARIZED      set to 1 to produce a local ad-hoc unnotarized test build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib-codesign.sh"

DIST_DIR="$PROJECT_ROOT/dist"
RELEASE_DIR="$PROJECT_ROOT/dist/release"

VERSION="${MORAX_VERSION:-$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")}"
SIGN_IDENTITY="${MORAX_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${MORAX_NOTARY_PROFILE:-}"

APP_SLUG="garage"
APP_NAME="Morax Garage"
DMG_NAME="MoraxGarage-${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
VOLUME_NAME="$APP_NAME $VERSION"

echo "=========================================================="
echo "    MORAX GARAGE — RELEASE PIPELINE ${VERSION}"
echo "=========================================================="

# -----------------------------------------------------------------------------
# Step 1/6 — Preflight
# -----------------------------------------------------------------------------
release_info "Step 1/6: Running preflight assertions..."
"$SCRIPT_DIR/release-preflight.sh"

# -----------------------------------------------------------------------------
# Step 2 & 3/6 — Build, Assemble and Sign Application Bundles
# -----------------------------------------------------------------------------
release_info "Step 2 & 3/6: Building universal bundles and signing..."
MORAX_VERSION="$VERSION" MORAX_SIGN_IDENTITY="$SIGN_IDENTITY" "$SCRIPT_DIR/build_app.sh"

APP_PATH="$DIST_DIR/$APP_NAME.app"
[ -d "$APP_PATH" ] || release_fail "$APP_PATH not found"

# -----------------------------------------------------------------------------
# Step 4/6 — Assemble and Sign Disk Image (DMG)
# -----------------------------------------------------------------------------
release_info "Step 4/6: Assembling disk image..."
mkdir -p "$RELEASE_DIR"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/morax-dmg-staging.XXXXXX")"
cleanup_staging() {
    rm -rf "$STAGING"
}
trap cleanup_staging EXIT

cp -R "$APP_PATH" "$STAGING/"
if [ -d "$DIST_DIR/$APP_NAME Menu.app" ]; then
    cp -R "$DIST_DIR/$APP_NAME Menu.app" "$STAGING/"
fi
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/LISEZ-MOI.txt" <<EOF
$APP_NAME $VERSION

Installation
  1. Glissez "$APP_NAME.app" dans le dossier Applications.
  2. Lancez l'application depuis votre dossier Applications ou via le hub Morax One.

Permissions
  Pour analyser les caches DaVinci Resolve, les apercus Lightroom et les
  LaunchAgents, activez l'Acces complet au disque dans :
  Reglages Systeme > Confidentialite et securite > Acces complet au disque

Support : https://morax.one
EOF

xattr -cr "$STAGING"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"
trap - EXIT

release_info "Signing disk image..."
xattr -cr "$DMG_PATH"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
else
    codesign --force --sign "-" "$DMG_PATH"
fi
release_ok "Disk image assembled and signed"

# -----------------------------------------------------------------------------
# Step 5/6 — Notarization & Stapling
# -----------------------------------------------------------------------------
release_info "Step 5/6: Notarization and Stapling..."
NOTARIZED=false
STAPLED=false

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    release_info "Submitting DMG to Apple notary service..."
    NOTARY_ARGS=()
    while IFS= read -r arg; do NOTARY_ARGS+=("$arg"); done < <(notary_credential_args)
    xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait
    NOTARIZED=true

    release_info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    
    if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
        STAPLED=true
        release_ok "Notarized and stapled successfully"
    else
        release_fail "Stapler validation failed after notarization"
    fi
else
    NOTARIZED=false
    STAPLED=false
    release_info "Skipping Apple notarization (no notary profile or identity is ad-hoc)."
fi

# -----------------------------------------------------------------------------
# Step 6/6 — Measured Manifest & SHA-256 (Morax One §3.3 Contract)
# -----------------------------------------------------------------------------
release_info "Step 6/6: Measuring output files and generating manifest..."

# Measure all fields directly on the shipped files
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "$DMG_PATH")"
RELEASED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Derived from binary inspection
APP_SLICES="$(lipo -archs "$APP_PATH/Contents/MacOS/MoraxCockpit")"
if echo "$APP_SLICES" | grep -qw "arm64" && echo "$APP_SLICES" | grep -qw "x86_64"; then
    APP_ARCH="universal"
else
    APP_ARCH="$APP_SLICES"
fi

# Derived from Info.plist
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"

# Derived from signature details
APP_DETAILS="$(signature_details "$APP_PATH")"
APP_AUTHORITY="$(signature_field "$APP_DETAILS" Authority)"
if printf '%s' "$APP_AUTHORITY" | grep -Fq 'Developer ID Application'; then
    SIGNED_BY="Developer ID Application"
elif [ -n "$APP_AUTHORITY" ]; then
    SIGNED_BY="$APP_AUTHORITY"
else
    SIGNED_BY="Ad-hoc"
fi

# Release notes anchor (e.g. 1.0.0 -> 100)
VERSION_ANCHOR="$(echo "$VERSION" | tr -d '.')"
RELEASE_NOTES="docs/CHANGELOG.md#${VERSION_ANCHOR}"

# Write standalone checksum file
echo "$SHA256  $DMG_NAME" > "$RELEASE_DIR/$DMG_NAME.sha256"

# Write manifest strictly adhering to Morax One §3.3
cat > "$RELEASE_DIR/release.json" <<EOF
{
  "app": "$APP_SLUG",
  "name": "$APP_NAME",
  "version": "$VERSION",
  "channel": "stable",
  "platform": "macos",
  "arch": "$APP_ARCH",
  "minimumOS": "$MIN_OS",
  "releasedAt": "$RELEASED_AT",
  "file": "$DMG_NAME",
  "sizeBytes": $SIZE_BYTES,
  "sha256": "$SHA256",
  "notarized": $NOTARIZED,
  "stapled": $STAPLED,
  "signedBy": "$SIGNED_BY",
  "releaseNotes": "$RELEASE_NOTES"
}
EOF
release_ok "Manifest written to $RELEASE_DIR/release.json"

# -----------------------------------------------------------------------------
# Step 7/6 — Post-distribution Verification Gate
# -----------------------------------------------------------------------------
release_info "Running post-release verification suite..."
"$SCRIPT_DIR/release-verify.sh" "$DMG_PATH" "$RELEASE_DIR/release.json"

echo ""
echo "=========================================================="
echo "    RELEASE READY & VERIFIED"
echo "=========================================================="
echo "  App Slug  : $APP_SLUG"
echo "  Name      : $APP_NAME"
echo "  Version   : $VERSION"
echo "  DMG       : $DMG_PATH"
echo "  Size      : $SIZE_BYTES bytes ($((SIZE_BYTES / 1024 / 1024)) MB)"
echo "  Arch      : $APP_ARCH ($APP_SLICES)"
echo "  SHA-256   : $SHA256"
echo "  Signed By : $SIGNED_BY"
echo "  Notarized : $NOTARIZED"
echo "  Stapled   : $STAPLED"
echo "  Manifest  : $RELEASE_DIR/release.json"
echo "=========================================================="
