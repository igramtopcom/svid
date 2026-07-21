#!/bin/bash
# =============================================================================
# Multi-Brand Linux Packaging Script — Creates .AppImage from Flutter bundle
# Usage: bash scripts/package_linux.sh [svid|vidcombo]
# Default: svid
# =============================================================================
set -e

BRAND="${1:-svid}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
DIST_DIR="$PROJECT_ROOT/dist"

# Brand configuration
case "$BRAND" in
  svid)
    APP_NAME="Svid"
    APP_BINARY="svid"
    APP_COMMENT="The fastest desktop video downloader"
    ;;
  vidcombo)
    APP_NAME="VidCombo"
    APP_BINARY="vidcombo"
    APP_COMMENT="Fast & reliable video downloader"
    ;;
  *)
    echo "Error: Unknown brand '$BRAND'. Use 'svid' or 'vidcombo'."
    exit 1
    ;;
esac

# Parse version from pubspec.yaml
VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//')

BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
APPIMAGE_NAME="${APP_NAME}-${VERSION}-linux-x64.AppImage"
APPIMAGE_PATH="$DIST_DIR/$APPIMAGE_NAME"
APPDIR="$DIST_DIR/${APP_NAME}.AppDir"

echo "Packaging Linux AppImage: $APPIMAGE_NAME (brand: $BRAND)"

# Verify bundle exists
if [ ! -d "$BUNDLE_DIR" ]; then
    echo "ERROR: $BUNDLE_DIR not found. Run 'flutter build linux --release --dart-define=BRAND=$BRAND' first."
    exit 1
fi

mkdir -p "$DIST_DIR"

# Clean previous
rm -rf "$APPDIR"
rm -f "$APPIMAGE_PATH"

# Create AppDir structure
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle into AppDir
cp -R "$BUNDLE_DIR"/* "$APPDIR/usr/bin/"

# Move libraries to lib directory
if [ -d "$APPDIR/usr/bin/lib" ]; then
    cp -R "$APPDIR/usr/bin/lib"/* "$APPDIR/usr/lib/" 2>/dev/null || true
    rm -rf "$APPDIR/usr/bin/lib"
fi

# Create desktop file
cat > "$APPDIR/${APP_BINARY}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=${APP_COMMENT}
Exec=${APP_BINARY}
Icon=${APP_BINARY}
Categories=Network;AudioVideo;
Terminal=false
StartupWMClass=${APP_BINARY}
EOF

# Copy brand-specific icon
ICON_SOURCE="$PROJECT_ROOT/assets/brands/${BRAND}/app_icon.png"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APPDIR/${APP_BINARY}.png"
    cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_BINARY}.png"
else
    echo "  Warning: No app icon found at $ICON_SOURCE, using placeholder"
    printf '\x89PNG\r\n\x1a\n' > "$APPDIR/${APP_BINARY}.png"
fi

# Create AppRun script
cat > "$APPDIR/AppRun" << APPRUN
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/${APP_BINARY}" "\$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# Download appimagetool if not available
APPIMAGETOOL="$DIST_DIR/appimagetool"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "  Downloading appimagetool..."
    ARCH=$(uname -m)
    curl -fsSL -o "$APPIMAGETOOL" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

# Build AppImage
echo "  Creating AppImage..."
ARCH=$(uname -m) "$APPIMAGETOOL" "$APPDIR" "$APPIMAGE_PATH"

# Clean up
rm -rf "$APPDIR"

echo "  AppImage created: $APPIMAGE_PATH"
echo "  Size: $(du -h "$APPIMAGE_PATH" | cut -f1)"
