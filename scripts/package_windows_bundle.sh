#!/usr/bin/env bash
# =============================================================================
# Package a signed Windows runner bundle into the public portable ZIP artifact.
#
# Usage:
#   package_windows_bundle.sh <BUNDLE_DIR> <DEST_DIR> <BRAND>
# =============================================================================

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <BUNDLE_DIR> <DEST_DIR> <BRAND>" >&2
  exit 2
fi

BUNDLE_DIR="$1"
DEST_DIR="$2"
BRAND="$3"

case "$BRAND" in
  svid)    APP_NAME="Svid";    EXE_NAME="svid.exe" ;;
  vidcombo) APP_NAME="VidCombo"; EXE_NAME="vidcombo.exe" ;;
  *) echo "Unknown brand: $BRAND (expected svid|vidcombo)" >&2; exit 2 ;;
esac

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "ERROR: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [ ! -f "$BUNDLE_DIR/$EXE_NAME" ]; then
  echo "ERROR: expected $EXE_NAME missing from $BUNDLE_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
if [ ! -f "$PUBSPEC" ]; then
  echo "ERROR: pubspec.yaml not found at $PUBSPEC" >&2
  exit 1
fi

VERSION="$(awk '/^version:/ {print $2; exit}' "$PUBSPEC" | sed 's/+.*//')"
if [ -z "$VERSION" ]; then
  echo "ERROR: failed to parse version from $PUBSPEC" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
# Resolve to absolute path BEFORE the subshell `cd "$BUNDLE_DIR"` step —
# otherwise the relative ZIP path resolves under the bundle dir and zip
# fails with "Could not create output file" / "No such file or directory".
# Same class of bug already fixed in scripts/sign_windows_artifacts.sh.
DEST_DIR="$(cd "$DEST_DIR" && pwd)"
ZIP_NAME="${APP_NAME}-${VERSION}-windows-x64.zip"
ZIP_PATH="$DEST_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"

echo "==> Package signed Windows ZIP for brand: $BRAND ($APP_NAME)"
echo "    Bundle : $BUNDLE_DIR"
echo "    Output : $ZIP_PATH"

(cd "$BUNDLE_DIR" && zip -qr "$ZIP_PATH" .)

echo "==> Signed ZIP written: $ZIP_PATH"
