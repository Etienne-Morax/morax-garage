#!/usr/bin/env bash
# Distribution verification for Morax Garage.
# Asserts that the shipped DMG and application bundle strictly meet all distribution requirements.
#
# Usage:
#   scripts/release-verify.sh [path/to/MoraxGarage-x.y.z.dmg] [path/to/release.json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib-codesign.sh"

VERSION="${MORAX_VERSION:-$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")}"
APP_NAME="Morax Garage"
RELEASE_DIR="$PROJECT_ROOT/dist/release"
DMG_PATH="${1:-$RELEASE_DIR/MoraxGarage-${VERSION}.dmg}"
MANIFEST_PATH="${2:-$RELEASE_DIR/release.json}"
DIST_APP="$PROJECT_ROOT/dist/$APP_NAME.app"

release_info "Starting release verification..."

# 1. Check existence of artifacts
[ -f "$DMG_PATH" ] || release_fail "DMG not found: $DMG_PATH"
[ -f "$MANIFEST_PATH" ] || release_fail "release.json manifest not found: $MANIFEST_PATH"
[ -d "$DIST_APP" ] || release_fail "App bundle not found: $DIST_APP"
release_ok "Artefact and manifest present"

# 2. Verify SHA-256 against manifest
ACTUAL_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
MANIFEST_SHA="$(grep '"sha256"' "$MANIFEST_PATH" | head -n 1 | awk -F'"' '{print $4}')"

if [ "$ACTUAL_SHA" != "$MANIFEST_SHA" ]; then
    release_fail "SHA-256 mismatch! Manifest: $MANIFEST_SHA vs Actual: $ACTUAL_SHA"
fi
release_ok "SHA-256 matches manifest ($ACTUAL_SHA)"

# Check .sha256 file if present
SHA_FILE="$DMG_PATH.sha256"
if [ -f "$SHA_FILE" ]; then
    RECORDED_SHA="$(awk '{print $1}' "$SHA_FILE")"
    if [ "$ACTUAL_SHA" != "$RECORDED_SHA" ]; then
        release_fail "SHA-256 mismatch with $SHA_FILE"
    fi
    release_ok "SHA-256 matches $(basename "$SHA_FILE")"
fi

# 3. Read manifest metadata
MANIFEST_APP="$(grep '"app"' "$MANIFEST_PATH" | head -n 1 | awk -F'"' '{print $4}')"
MANIFEST_ARCH="$(grep '"arch"' "$MANIFEST_PATH" | head -n 1 | awk -F'"' '{print $4}')"
MANIFEST_NOTARIZED="$(grep '"notarized"' "$MANIFEST_PATH" | head -n 1 | awk -F': ' '{print $2}' | tr -d ',\r\n ')"
MANIFEST_STAPLED="$(grep '"stapled"' "$MANIFEST_PATH" | head -n 1 | awk -F': ' '{print $2}' | tr -d ',\r\n ')"

if [ "$MANIFEST_APP" != "garage" ]; then
    release_fail "Manifest app field must be 'garage', got: $MANIFEST_APP"
fi
release_ok "Manifest app slug is 'garage'"

# 4. Verify binary architectures
APP_BINARY="$DIST_APP/Contents/MacOS/MoraxCockpit"
[ -f "$APP_BINARY" ] || release_fail "Binary not found at $APP_BINARY"
SLICES="$(lipo -archs "$APP_BINARY")"
if echo "$SLICES" | grep -qw "arm64" && echo "$SLICES" | grep -qw "x86_64"; then
    release_ok "Binary is universal ($SLICES)"
else
    release_fail "Binary is not universal, got slices: $SLICES"
fi

if [ "$MANIFEST_ARCH" != "universal" ]; then
    release_fail "Manifest arch is '$MANIFEST_ARCH', expected 'universal'"
fi
release_ok "Manifest arch matches binary reality"

# 5. Codesign deep & strict check
release_info "Checking code signatures..."
codesign --verify --deep --strict --verbose=2 "$DIST_APP" >/dev/null 2>&1 \
    || release_fail "App codesign verification failed"
codesign --verify --deep --strict --verbose=2 "$PROJECT_ROOT/dist/Morax Garage Menu.app" >/dev/null 2>&1 \
    || release_fail "Menu helper codesign verification failed"
codesign --verify --deep --strict --verbose=2 "$DMG_PATH" >/dev/null 2>&1 \
    || release_fail "DMG codesign verification failed"
release_ok "Code signatures verify (deep, strict) on app, helper and DMG"

# 6. Check signing authority & Gatekeeper / Notarization
APP_SIG_DETAILS="$(signature_details "$DIST_APP")"
APP_AUTHORITY="$(signature_field "$APP_SIG_DETAILS" Authority)"
MANIFEST_SIGNED_BY="$(grep '"signedBy"' "$MANIFEST_PATH" | head -n 1 | awk -F'"' '{print $4}')"
if [ -z "$APP_AUTHORITY" ]; then
    EXPECTED_SIGNED_BY="Ad-hoc"
elif printf '%s' "$APP_AUTHORITY" | grep -Fq 'Developer ID Application'; then
    EXPECTED_SIGNED_BY="Developer ID Application"
else
    EXPECTED_SIGNED_BY="$APP_AUTHORITY"
fi
if [ "$MANIFEST_SIGNED_BY" != "$EXPECTED_SIGNED_BY" ]; then
    release_fail "Manifest signedBy ('$MANIFEST_SIGNED_BY') does not match the app signature ('$EXPECTED_SIGNED_BY')"
fi
release_ok "Manifest signedBy matches the app signature"
if [ "$MANIFEST_NOTARIZED" != "true" ] && [ "$MANIFEST_STAPLED" = "true" ]; then
    release_fail "Manifest claims stapled=true while notarized=false"
fi

if [ "$MANIFEST_NOTARIZED" = "true" ]; then
    # Gatekeeper check
    SPCTL_OUT="$(spctl -a -vvv -t install "$DIST_APP" 2>&1 || true)"
    if ! printf '%s' "$SPCTL_OUT" | grep -Fq 'accepted'; then
        release_fail "Gatekeeper rejected the app: $SPCTL_OUT"
    fi
    if ! printf '%s' "$SPCTL_OUT" | grep -Fq 'Notarized Developer ID'; then
        release_fail "Gatekeeper did not recognize Notarized Developer ID: $SPCTL_OUT"
    fi
    release_ok "Gatekeeper accepts bundle as Notarized Developer ID"

    # Staple check
    xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1 \
        || release_fail "Notarization ticket is not stapled to the DMG"
    release_ok "Notarization ticket stapled to DMG"
    [ "$MANIFEST_STAPLED" = "true" ] || release_fail "DMG is stapled but manifest says stapled=$MANIFEST_STAPLED"
else
    release_info "Unnotarized build: notarized=false accurately reflected in manifest"
fi

# 7. Mount DMG and verify contained app & version
release_info "Mounting DMG to inspect delivered payload..."
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/morax-verify-mount.XXXXXX")"
cleanup_mount() {
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    rm -rf "$MOUNT_DIR"
}
trap cleanup_mount EXIT

hdiutil attach -nobrowse -readonly "$DMG_PATH" -mountpoint "$MOUNT_DIR" >/dev/null

MOUNTED_APP="$MOUNT_DIR/$APP_NAME.app"
[ -d "$MOUNTED_APP" ] || release_fail "Mounted DMG does not contain $APP_NAME.app"
[ -f "$MOUNT_DIR/LISEZ-MOI.txt" ] || release_fail "Mounted DMG missing LISEZ-MOI.txt"

MOUNTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNTED_APP/Contents/Info.plist")"
if [ "$MOUNTED_VERSION" != "$VERSION" ]; then
    release_fail "Version inside DMG ($MOUNTED_VERSION) does not match expected version ($VERSION)"
fi
release_ok "Mounted DMG contains $APP_NAME.app with CFBundleShortVersionString $MOUNTED_VERSION"

# Detach mount cleanly
hdiutil detach "$MOUNT_DIR" >/dev/null
trap - EXIT
rm -rf "$MOUNT_DIR"
release_ok "DMG unmounted cleanly"

release_ok "Release verification passed completely!"
