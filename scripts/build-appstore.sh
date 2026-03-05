#!/bin/bash
set -euo pipefail

# FabricTray — App Store Build Script
# Creates a signed .app bundle ready for App Store submission.
#
# Usage:
#   ./scripts/build-appstore.sh                     # Build only (no signing)
#   ./scripts/build-appstore.sh --sign "Developer ID Application: Name (TEAMID)"
#   ./scripts/build-appstore.sh --archive "3rd Party Mac Developer Application: Name (TEAMID)"
#
# Prerequisites:
#   - Xcode command line tools (xcode-select --install)
#   - Valid Apple Developer signing identity (for --sign / --archive)
#   - App icon PNGs in Assets.xcassets/AppIcon.appiconset (optional but recommended)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/appstore"
APP_NAME="FabricTray"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RESOURCES="$PROJECT_ROOT/Sources/FabricTray/Resources"

SIGN_IDENTITY=""
ARCHIVE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --archive)
            SIGN_IDENTITY="$2"
            ARCHIVE_MODE=true
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_ROOT"
swift build -c release --arch arm64 --arch x86_64 2>&1

EXECUTABLE="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Build product not found at $EXECUTABLE"
    exit 1
fi

echo "==> Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$RESOURCES/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy privacy manifest
cp "$RESOURCES/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"

# Copy SVG icons
if [ -d "$RESOURCES/Icons" ]; then
    cp -R "$RESOURCES/Icons" "$APP_BUNDLE/Contents/Resources/Icons"
fi

# Copy bundled resources from SwiftPM build (contains Resources directory)
BUNDLE_RESOURCES="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$BUNDLE_RESOURCES" ]; then
    cp -R "$BUNDLE_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
fi

# Generate .icns from AppIcon.appiconset if source PNGs exist
ICONSET_DIR="$RESOURCES/Assets.xcassets/AppIcon.appiconset"
if ls "$ICONSET_DIR"/*.png 1>/dev/null 2>&1; then
    echo "==> Generating AppIcon.icns..."
    ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_TMP"
    for size in 16 32 128 256 512; do
        [ -f "$ICONSET_DIR/icon_${size}x${size}.png" ] && cp "$ICONSET_DIR/icon_${size}x${size}.png" "$ICONSET_TMP/icon_${size}x${size}.png"
        [ -f "$ICONSET_DIR/icon_${size}x${size}@2x.png" ] && cp "$ICONSET_DIR/icon_${size}x${size}@2x.png" "$ICONSET_TMP/icon_${size}x${size}@2x.png"
    done
    if ls "$ICONSET_TMP"/*.png 1>/dev/null 2>&1; then
        iconutil -c icns "$ICONSET_TMP" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    else
        echo "    (No icon PNGs found in expected naming format, skipping .icns generation)"
    fi
    rm -rf "$ICONSET_TMP"
else
    echo "    (No app icon PNGs in $ICONSET_DIR — add PNGs for App Store submission)"
fi

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> App bundle created at $APP_BUNDLE"

# Code signing
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with identity: $SIGN_IDENTITY"
    ENTITLEMENTS="$RESOURCES/FabricTray.entitlements"
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "    Signature valid."
fi

# Archive for App Store
if [ "$ARCHIVE_MODE" = true ]; then
    echo "==> Creating App Store package..."
    ARCHIVE_DIR="$BUILD_DIR/archive"
    PKG_PATH="$BUILD_DIR/$APP_NAME.pkg"
    mkdir -p "$ARCHIVE_DIR"
    cp -R "$APP_BUNDLE" "$ARCHIVE_DIR/"
    productbuild --component "$ARCHIVE_DIR/$APP_NAME.app" /Applications \
        --sign "$SIGN_IDENTITY" \
        "$PKG_PATH" 2>/dev/null || \
    productbuild --component "$ARCHIVE_DIR/$APP_NAME.app" /Applications \
        "$PKG_PATH"
    echo "==> Package created at $PKG_PATH"
    echo "    Submit with: xcrun altool --upload-app -f $PKG_PATH -t osx -u YOUR_APPLE_ID"
    rm -rf "$ARCHIVE_DIR"
fi

echo "==> Done! Test with: open $APP_BUNDLE"
