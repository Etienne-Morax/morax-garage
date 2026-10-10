#!/usr/bin/env bash
# Morax Garage Official macOS Installation Script
# Installs Morax Garage.app into /Applications

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLICATIONS_DIR="/Applications"

echo "=========================================================="
echo "    MORAX GARAGE - OFFICIAL macOS INSTALLATION"
echo "=========================================================="

# 1. Run Automated Test Suite
cd "$PROJECT_ROOT"
if [ "${MORAX_SKIP_TESTS:-0}" = "1" ]; then
    echo "==> Step 1/4: Skipping automated tests (MORAX_SKIP_TESTS=1)"
else
    echo "==> Step 1/4: Running automated tests..."
    swift test
fi

# 2. Build Release Application Bundles
echo "==> Step 2/4: Building application bundles..."
chmod +x "$SCRIPT_DIR/build_app.sh"
"$SCRIPT_DIR/build_app.sh"

# 3. Terminate running instances & Install to /Applications
echo "==> Step 3/4: Installing Morax Garage to $APPLICATIONS_DIR..."
MAIN_APP_SRC="$PROJECT_ROOT/dist/Morax Garage.app"
MAIN_APP_DEST="$APPLICATIONS_DIR/Morax Garage.app"
MENU_APP_SRC="$PROJECT_ROOT/dist/Morax Garage Menu.app"
MENU_APP_DEST="$APPLICATIONS_DIR/Morax Garage Menu.app"

# Terminate running instances to avoid file-in-use locks
killall -9 MoraxCockpit MoraxCockpitMenu "Morax Garage" "Morax Garage Menu" 2>/dev/null || true
sleep 0.5

# Remove previous / legacy installed versions if existing
for old_app in \
    "$APPLICATIONS_DIR/MoraxCockpit.app" \
    "$APPLICATIONS_DIR/MoraxCockpitMenu.app" \
    "$APPLICATIONS_DIR/MoraxGarage.app" \
    "$MENU_APP_DEST" \
    "$MAIN_APP_DEST"; do
    if [ -d "$old_app" ]; then
        echo "  Removing previous version: $old_app..."
        rm -rf "$old_app"
    fi
done

# Copy Morax Garage bundles
echo "  Copying application bundles to $APPLICATIONS_DIR..."
cp -R "$MAIN_APP_SRC" "$MAIN_APP_DEST"
[ -d "$MENU_APP_SRC" ] && cp -R "$MENU_APP_SRC" "$MENU_APP_DEST"

# Codesign installed bundles
SIGN_IDENTITY="${MORAX_SIGN_IDENTITY:--}"
CODESIGN_FLAGS=(--force --deep --sign "$SIGN_IDENTITY" --timestamp=none)
if [ "$SIGN_IDENTITY" != "-" ]; then
    CODESIGN_FLAGS=(--force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp)
fi

echo "  Finalizing signatures in $APPLICATIONS_DIR..."
xattr -cr "$MAIN_APP_DEST"
[ -d "$MENU_APP_DEST" ] && xattr -cr "$MENU_APP_DEST"
codesign "${CODESIGN_FLAGS[@]}" "$MAIN_APP_DEST"
[ -d "$MENU_APP_DEST" ] && codesign "${CODESIGN_FLAGS[@]}" "$MENU_APP_DEST"

# 4. Register with macOS LaunchServices
echo "==> Step 4/4: Registering application with macOS LaunchServices..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "/Applications/MoraxCockpit.app" 2>/dev/null || true
    "$LSREGISTER" -u "/Applications/MoraxCockpitMenu.app" 2>/dev/null || true
    "$LSREGISTER" -f "$MAIN_APP_DEST" || true
    [ -d "$MENU_APP_DEST" ] && "$LSREGISTER" -f "$MENU_APP_DEST" || true
    echo "  Registered with LaunchServices."
fi

echo ""
echo "=========================================================="
echo "    INSTALLATION COMPLETED SUCCESSFULLY!"
echo "=========================================================="
echo "Morax Garage is now installed at: $MAIN_APP_DEST"
echo "Launch it from Applications, Dock, or Spotlight."
echo ""
echo "Permissions Note:"
echo "To work in optimal conditions (cleaning DaVinci Resolve caches,"
echo "Lightroom previews, and auditing LaunchAgents), please ensure"
echo "Full Disk Access is enabled in:"
echo "  System Settings > Privacy & Security > Full Disk Access"
echo "=========================================================="
