#!/usr/bin/env bash
# Morax Garage Application Build & Bundle Script
# Builds universal release binaries, generates .icns icons, assembles .app bundles, and signs them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib-codesign.sh"

BUILD_ARCHS=(arm64 x86_64)
NATIVE_ARCH="$(uname -m)"
BUILD_DIR="$PROJECT_ROOT/.build/$NATIVE_ARCH-apple-macosx/release"
UNIVERSAL_DIR="$PROJECT_ROOT/.build/universal/release"
DIST_DIR="$PROJECT_ROOT/dist"

# Version: single source of truth is the VERSION file, overridable with MORAX_VERSION.
VERSION="${MORAX_VERSION:-$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")}"
BUILD_NUMBER="${MORAX_BUILD:-$(date +%Y%m%d%H%M)}"

# Signing identity: ad-hoc ("-") by default, Developer ID when MORAX_SIGN_IDENTITY is set.
SIGN_IDENTITY="${MORAX_SIGN_IDENTITY:--}"

release_info "Building Morax Garage $VERSION ($BUILD_NUMBER) in Release mode (${BUILD_ARCHS[*]})..."
cd "$PROJECT_ROOT"
arm64_slice_dir=""
x86_64_slice_dir=""
for arch in "${BUILD_ARCHS[@]}"; do
    release_info "Building $arch slice..."
    scratch_dir="$PROJECT_ROOT/.build/scratch-$arch"
    swift build -c release --triple "$arch-apple-macosx" --scratch-path "$scratch_dir"
    slice_dir="$(swift build -c release --triple "$arch-apple-macosx" --scratch-path "$scratch_dir" --show-bin-path)"
    if [ ! -d "$slice_dir" ]; then
        release_fail "expected products directory not found: $slice_dir"
    fi
    if [ "$arch" = "arm64" ]; then
        arm64_slice_dir="$slice_dir"
    else
        x86_64_slice_dir="$slice_dir"
    fi
done

release_info "Merging slices into universal binaries..."
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_DIR"
for executable in MoraxCockpit MoraxCockpitMenu; do
    lipo -create "$arm64_slice_dir/$executable" "$x86_64_slice_dir/$executable" -output "$UNIVERSAL_DIR/$executable"
    release_ok "$executable: $(lipo -archs "$UNIVERSAL_DIR/$executable")"
done

# Resource bundles are architecture independent: take them from the native slice.
NATIVE_SLICE_DIR="$arm64_slice_dir"
if [ "$NATIVE_ARCH" = "x86_64" ]; then
    NATIVE_SLICE_DIR="$x86_64_slice_dir"
fi
for bundle in "$NATIVE_SLICE_DIR"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$UNIVERSAL_DIR/"
done

BUILD_DIR="$UNIVERSAL_DIR"

release_info "Preparing output directory..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 1. Generate macOS Icon (.icns)
release_info "Generating AppIcon.icns..."
ICONSET_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/morax-iconset.XXXXXX")"
ICONSET_TMP="$ICONSET_PARENT/AppIcon.iconset"
mkdir -p "$ICONSET_TMP"
trap 'rm -rf "$ICONSET_PARENT"' EXIT

cp "$PROJECT_ROOT/Sources/MoraxCockpit/Resources/Assets.xcassets/AppIcon.appiconset"/*.png "$ICONSET_TMP/"
iconutil -c icns "$ICONSET_TMP" -o "$DIST_DIR/AppIcon.icns"
rm -rf "$ICONSET_PARENT"
trap - EXIT

# 2. Build Morax Garage.app Bundle
release_info "Creating Morax Garage.app bundle..."
MAIN_APP="$DIST_DIR/Morax Garage.app"
mkdir -p "$MAIN_APP/Contents/MacOS"
mkdir -p "$MAIN_APP/Contents/Resources"

# Copy main binary
cp "$BUILD_DIR/MoraxCockpit" "$MAIN_APP/Contents/MacOS/MoraxCockpit"
chmod +x "$MAIN_APP/Contents/MacOS/MoraxCockpit"

# Copy Icon
cp "$DIST_DIR/AppIcon.icns" "$MAIN_APP/Contents/Resources/AppIcon.icns"

# Copy SPM Resource Bundles
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        release_info "Embedding resource bundle: $(basename "$bundle")"
        cp -R "$bundle" "$MAIN_APP/Contents/Resources/"
    fi
done

# Create PkgInfo
printf 'APPL????' > "$MAIN_APP/Contents/PkgInfo"

# Create Info.plist with complete macOS permissions descriptions
cat << EOF > "$MAIN_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MoraxCockpit</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.morax.garage</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Morax Garage</string>
    <key>CFBundleDisplayName</key>
    <string>Morax Garage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    
    <!-- macOS Security & Privacy TCC Usage Descriptions -->
    <key>NSFullDiskAccessUsageDescription</key>
    <string>Morax Garage requires Full Disk Access to scan DaVinci Resolve render caches, Lightroom/Capture One previews, developer artifacts, and LaunchAgents for safe Mac maintenance.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Morax Garage needs access to your Downloads folder to locate old installer packages (.dmg, .pkg) and large archives taking up space.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Morax Garage needs access to your Desktop folder to identify unused installer disk images.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Morax Garage needs access to scan developer repositories and project build caches in Documents and project directories.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Morax Garage requires access to external volumes to scan DaVinci Resolve external scratch disks and optimized media caches.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Morax Garage uses AppleEvents to reveal items in Finder and hand off applications to Pearcleaner for clean uninstallation.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>Morax Garage inspects system-level LaunchAgents in read-only mode to audit persistence items.</string>
</dict>
</plist>
EOF

# 3. Build Morax Garage Menu.app Bundle (MenuBar standalone helper)
release_info "Creating Morax Garage Menu.app bundle..."
MENU_APP="$DIST_DIR/Morax Garage Menu.app"
mkdir -p "$MENU_APP/Contents/MacOS"
mkdir -p "$MENU_APP/Contents/Resources"

cp "$BUILD_DIR/MoraxCockpitMenu" "$MENU_APP/Contents/MacOS/MoraxCockpitMenu"
chmod +x "$MENU_APP/Contents/MacOS/MoraxCockpitMenu"
cp "$DIST_DIR/AppIcon.icns" "$MENU_APP/Contents/Resources/AppIcon.icns"

for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        release_info "Embedding resource bundle: $(basename "$bundle")"
        cp -R "$bundle" "$MENU_APP/Contents/Resources/"
    fi
done

printf 'APPL????' > "$MENU_APP/Contents/PkgInfo"

cat << EOF > "$MENU_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MoraxCockpitMenu</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.morax.garage.menu</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Morax Garage Menu</string>
    <key>CFBundleDisplayName</key>
    <string>Morax Garage Menu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 4. Binary architecture checks
release_info "Verifying binary architectures..."
for binary in "$MAIN_APP/Contents/MacOS/MoraxCockpit" "$MENU_APP/Contents/MacOS/MoraxCockpitMenu"; do
    slices="$(lipo -archs "$binary")"
    release_ok "$(basename "$binary"): $slices"
    for arch in "${BUILD_ARCHS[@]}"; do
        case " $slices " in
            *" $arch "*) ;;
            *) release_fail "$binary is missing the $arch slice (got: $slices)" ;;
        esac
    done
done

# 5. Codesigning
release_info "Codesigning application bundles..."
xattr -cr "$MAIN_APP"
xattr -cr "$MENU_APP"
CODESIGN_FLAGS=(--force --deep --sign "$SIGN_IDENTITY" --timestamp=none)
if [ "$SIGN_IDENTITY" != "-" ]; then
    # Hardened runtime and secure timestamp are required for notarization
    CODESIGN_FLAGS=(--force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp)
fi

codesign "${CODESIGN_FLAGS[@]}" "$MAIN_APP"
codesign "${CODESIGN_FLAGS[@]}" "$MENU_APP"

release_info "Verifying bundle signatures..."
codesign --verify --deep --strict "$MAIN_APP"
codesign --verify --deep --strict "$MENU_APP"
release_ok "Application bundles built and signed successfully: $DIST_DIR"
