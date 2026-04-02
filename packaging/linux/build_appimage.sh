#!/bin/bash
# Build Helios GCS AppImage from Flutter linux release bundle
# Usage: ./packaging/linux/build_appimage.sh
# Requires: appimagetool (downloaded automatically if missing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
APPDIR="$PROJECT_ROOT/build/linux/x64/release/Helios_GCS.AppDir"
OUTPUT="$PROJECT_ROOT/build/helios-gcs-linux-x64.AppImage"

# Verify Flutter build exists
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: Flutter linux release bundle not found at $BUNDLE_DIR"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

# Clean previous AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy the Flutter bundle into the AppDir
cp -r "$BUNDLE_DIR"/* "$APPDIR/"

# Copy desktop file and icon
cp "$SCRIPT_DIR/helios-gcs.desktop" "$APPDIR/helios-gcs.desktop"
cp "$SCRIPT_DIR/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

# Generate PNG icon from SVG (if rsvg-convert available) or use existing PNG
ICON_SVG="$PROJECT_ROOT/assets/icons/helios_app_icon.svg"
ICON_PNG_256="$APPDIR/usr/share/icons/hicolor/256x256/apps/helios-gcs.png"
ICON_PNG_SRC="$PROJECT_ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"

if command -v rsvg-convert &>/dev/null; then
  rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICON_PNG_256"
elif [ -f "$ICON_PNG_SRC" ]; then
  cp "$ICON_PNG_SRC" "$ICON_PNG_256"
else
  echo "Warning: No icon converter available and no pre-built 256px icon found."
  echo "Install librsvg2-bin for SVG→PNG conversion."
fi

# Symlink icon at AppDir root (required by AppImage spec)
if [ -f "$ICON_PNG_256" ]; then
  cp "$ICON_PNG_256" "$APPDIR/helios-gcs.png"
fi

# Download appimagetool if not available
APPIMAGETOOL=""
if command -v appimagetool &>/dev/null; then
  APPIMAGETOOL="appimagetool"
else
  TOOL_PATH="$PROJECT_ROOT/build/appimagetool"
  if [ ! -f "$TOOL_PATH" ]; then
    echo "Downloading appimagetool..."
    ARCH=$(uname -m)
    curl -fsSL "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage" \
      -o "$TOOL_PATH"
    chmod +x "$TOOL_PATH"
  fi
  APPIMAGETOOL="$TOOL_PATH"
fi

# Build the AppImage
echo "Building AppImage..."
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"

echo "AppImage: $OUTPUT"
