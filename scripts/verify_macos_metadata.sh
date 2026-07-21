#!/usr/bin/env bash
# Verify user-visible macOS bundle metadata from a .app or a packaged DMG.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: bash scripts/verify_macos_metadata.sh <ssvid|vidcombo> <app-or-dmg-path>" >&2
  exit 2
fi

BRAND="$1"
TARGET="$2"

case "$BRAND" in
  ssvid)
    DISPLAY_NAME="SSvid"
    BUNDLE_ID="com.ssvid.app"
    URL_SCHEME="ssvid"
    COPYRIGHT="Copyright © 2026 SSvid. All rights reserved."
    ;;
  vidcombo)
    DISPLAY_NAME="VidCombo"
    BUNDLE_ID="com.tinasoft.vidcombo"
    URL_SCHEME="vidcombo"
    COPYRIGHT="Copyright © 2026 VidCombo. All rights reserved."
    ;;
  *)
    echo "ERROR: unknown brand: $BRAND" >&2
    exit 2
    ;;
esac

if [ ! -e "$TARGET" ]; then
  echo "ERROR: metadata target not found: $TARGET" >&2
  exit 2
fi

MOUNT_POINT=""
MOUNTED=0

cleanup() {
  if [ "$MOUNTED" -eq 1 ] && [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ -d "$TARGET" ] && [[ "$TARGET" == *.app ]]; then
  APP_PATH="$TARGET"
else
  MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/macos-metadata.XXXXXX")"
  if ! hdiutil attach "$TARGET" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen -readonly >/tmp/macos_metadata_hdiutil.out 2>&1; then
    echo "ERROR: failed to mount DMG for metadata verification: $TARGET" >&2
    tail -10 /tmp/macos_metadata_hdiutil.out >&2
    exit 1
  fi
  MOUNTED=1
  APP_PATH="$(find "$MOUNT_POINT" -maxdepth 2 -name '*.app' -type d -print -quit)"
fi

if [ -z "${APP_PATH:-}" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: no .app bundle found in target: $TARGET" >&2
  exit 1
fi

PLIST="$APP_PATH/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "ERROR: Info.plist missing: $PLIST" >&2
  exit 1
fi

plist_value() {
  plutil -extract "$1" raw "$PLIST" 2>/dev/null || true
}

assert_equal() {
  local field="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: $field mismatch for $APP_PATH" >&2
    echo "       expected: $expected" >&2
    echo "       actual  : ${actual:-<empty>}" >&2
    exit 1
  fi
}

assert_nonempty() {
  local field="$1"
  local actual="$2"
  if [ -z "$actual" ]; then
    echo "ERROR: $field is empty for $APP_PATH" >&2
    exit 1
  fi
}

assert_equal "CFBundleIdentifier" "$(plist_value CFBundleIdentifier)" "$BUNDLE_ID"
assert_equal "CFBundleName" "$(plist_value CFBundleName)" "$DISPLAY_NAME"
assert_equal "CFBundleDisplayName" "$(plist_value CFBundleDisplayName)" "$DISPLAY_NAME"
assert_equal "NSHumanReadableCopyright" "$(plist_value NSHumanReadableCopyright)" "$COPYRIGHT"
assert_equal "CFBundleURLSchemes[0]" "$(plist_value CFBundleURLTypes.0.CFBundleURLSchemes.0)" "$URL_SCHEME"
assert_equal "CFBundlePackageType" "$(plist_value CFBundlePackageType)" "APPL"
assert_nonempty "CFBundleShortVersionString" "$(plist_value CFBundleShortVersionString)"
assert_nonempty "CFBundleVersion" "$(plist_value CFBundleVersion)"
assert_nonempty "CFBundleExecutable" "$(plist_value CFBundleExecutable)"

ICON_FILE="$(plist_value CFBundleIconFile)"
assert_equal "CFBundleIconFile" "$ICON_FILE" "AppIcon"

if [ ! -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
  echo "ERROR: AppIcon.icns missing in bundle resources: $APP_PATH" >&2
  exit 1
fi

echo "macOS metadata OK: $APP_PATH"
echo "  CFBundleIdentifier      : $BUNDLE_ID"
echo "  CFBundleDisplayName     : $DISPLAY_NAME"
echo "  CFBundleShortVersion    : $(plist_value CFBundleShortVersionString)"
echo "  CFBundleVersion         : $(plist_value CFBundleVersion)"
