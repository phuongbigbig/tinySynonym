#!/bin/bash
set -euo pipefail

APP_NAME="MenubarThesaurus"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SOURCES_DIR="$APP_NAME/Sources"
PLIST="$APP_NAME/Resources/Info.plist"
THESAURUS_JSON="$APP_NAME/Resources/thesaurus.json"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Swift sources
SWIFT_FILES=$(find "$SOURCES_DIR" -name "*.swift")
echo "Compiling: $SWIFT_FILES"

swiftc \
    -o "$MACOS_DIR/$APP_NAME" \
    -target arm64-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework ServiceManagement \
    $SWIFT_FILES

# Copy resources
cp "$PLIST" "$CONTENTS/Info.plist"

if [ -f "$THESAURUS_JSON" ]; then
    cp "$THESAURUS_JSON" "$RESOURCES_DIR/thesaurus.json"
    echo "Bundled offline thesaurus ($(du -h "$THESAURUS_JSON" | cut -f1) )"
fi

# Sign (ad-hoc for local use)
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "To run:"
echo "  open $APP_BUNDLE"
echo ""
echo "NOTE: On first run, grant Accessibility access in:"
echo "  System Settings > Privacy & Security > Accessibility"
