#!/usr/bin/env bash
# =============================================================================
# Sign every shipped Windows PE file in a Flutter runner Release bundle.
#
# Usage:
#   sign_windows_bundle.sh <SOURCE_BUNDLE_DIR> <DEST_BUNDLE_DIR> <BRAND>
#
# The source bundle remains untouched. The destination bundle is a signed copy.
# =============================================================================

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <SOURCE_BUNDLE_DIR> <DEST_BUNDLE_DIR> <BRAND>" >&2
  exit 2
fi

SOURCE_BUNDLE_DIR="$1"
DEST_BUNDLE_DIR="$2"
BRAND="$3"

case "$BRAND" in
  ssvid)    APP_NAME="SSvid";    EXE_NAME="ssvid.exe" ;;
  vidcombo) APP_NAME="VidCombo"; EXE_NAME="vidcombo.exe" ;;
  *) echo "Unknown brand: $BRAND (expected ssvid|vidcombo)" >&2; exit 2 ;;
esac

if [ ! -d "$SOURCE_BUNDLE_DIR" ]; then
  echo "ERROR: source bundle directory not found: $SOURCE_BUNDLE_DIR" >&2
  exit 1
fi

resolve_bundle_root() {
  local root="$1"
  local exe_name="$2"
  local match

  if [ -f "$root/$exe_name" ]; then
    printf '%s\n' "$root"
    return 0
  fi

  match="$(find "$root" -type f -name "$exe_name" -print -quit)"
  if [ -z "$match" ]; then
    return 1
  fi

  dirname "$match"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/windows_signing_common.sh
source "$SCRIPT_DIR/windows_signing_common.sh"

load_windows_signing_materials

SOURCE_BUNDLE_ROOT="$(resolve_bundle_root "$SOURCE_BUNDLE_DIR" "$EXE_NAME" || true)"
if [ -z "$SOURCE_BUNDLE_ROOT" ]; then
  echo "ERROR: expected $EXE_NAME not found anywhere under $SOURCE_BUNDLE_DIR" >&2
  exit 1
fi

rm -rf "$DEST_BUNDLE_DIR"
mkdir -p "$DEST_BUNDLE_DIR"
cp -R "$SOURCE_BUNDLE_ROOT"/. "$DEST_BUNDLE_DIR"/

if [ ! -f "$DEST_BUNDLE_DIR/$EXE_NAME" ]; then
  echo "ERROR: expected $EXE_NAME missing from $DEST_BUNDLE_DIR" >&2
  exit 1
fi

echo "==> Sign Windows bundle for brand: $BRAND ($APP_NAME)"
echo "    Source : $SOURCE_BUNDLE_ROOT"
echo "    Dest   : $DEST_BUNDLE_DIR"
echo "    Slot   : $(upper_slot "$YUBIKEY_PIV_SLOT") (${PKCS11_KEY_OBJECT})"

sign_pe_tree_in_place "$DEST_BUNDLE_DIR"

echo
echo "==> Signed bundle ready: $DEST_BUNDLE_DIR"
