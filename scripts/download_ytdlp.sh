#!/bin/bash

# Script to download yt-dlp master-channel binaries for bundling
# Run this before building release versions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$PROJECT_DIR/assets/bin"

# Get latest release version
echo "Fetching latest yt-dlp master release..."
REPO="yt-dlp/yt-dlp-master-builds"
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST" ]; then
  echo "Failed to resolve latest yt-dlp master release tag" >&2
  exit 1
fi
echo "Latest master version: $LATEST"

# Create bin directory
mkdir -p "$BIN_DIR"

# Download for macOS
echo "Downloading yt-dlp for macOS..."
curl -fL "https://github.com/$REPO/releases/download/$LATEST/yt-dlp_macos" -o "$BIN_DIR/yt-dlp_macos"
chmod +x "$BIN_DIR/yt-dlp_macos"

# Download for Linux
echo "Downloading yt-dlp for Linux..."
curl -fL "https://github.com/$REPO/releases/download/$LATEST/yt-dlp_linux" -o "$BIN_DIR/yt-dlp_linux"
chmod +x "$BIN_DIR/yt-dlp_linux"

# Download for Windows
echo "Downloading yt-dlp for Windows..."
curl -fL "https://github.com/$REPO/releases/download/$LATEST/yt-dlp.exe" -o "$BIN_DIR/yt-dlp.exe"

# Create version file
echo "$LATEST" > "$BIN_DIR/VERSION"

echo ""
echo "Downloaded yt-dlp binaries to $BIN_DIR:"
ls -la "$BIN_DIR"

echo ""
echo "Done! Master version $LATEST downloaded."
