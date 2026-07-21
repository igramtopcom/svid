#!/usr/bin/env bash
# =============================================================================
# Sign Windows artifacts with YubiKey + Sectigo cert
#
# Usage:
#   sign_windows_artifacts.sh <SOURCE_DIR> <DEST_DIR> <BRAND>
#
# Inputs:
#   SOURCE_DIR — directory containing unsigned ZIP + setup.exe (recursive find)
#   DEST_DIR   — directory to write signed artifacts (created if missing)
#   BRAND      — svid | vidcombo
#
# Behavior:
#   1. Finds the brand's *-windows-x64.zip and either:
#      - unzips → signs all shipped PE files (`.exe`, `.dll`) in place → re-zips
#        into DEST_DIR (legacy / unsigned ZIP mode), or
#      - unzips → verifies all shipped PE files → copies ZIP into DEST_DIR
#        unchanged (presigned ZIP mode).
#   2. Finds the brand's *-windows-x64-setup.exe → signs in place into DEST_DIR.
#
# Requires (provided by Phase 1 setup on the self-hosted Mac runner):
#   - YubiKey 5 NFC FIPS plugged in (default slot 9A; override with
#     YUBIKEY_PIV_SLOT, e.g. 9c for a dedicated signing slot)
#   - osslsigncode + libp11 + libykcs11 installed via Homebrew
#   - ~/Desktop/yubikey-cert/sign_chain.pem
#   - ~/Desktop/yubikey-cert/secrets.txt (mode 600, contains "PIN: <8-digit>")
# =============================================================================

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <SOURCE_DIR> <DEST_DIR> <BRAND>" >&2
  exit 2
fi

SOURCE_DIR="$1"
DEST_DIR="$2"
BRAND="$3"

case "$BRAND" in
  svid)    APP_NAME="Svid";    EXE_NAME="svid.exe" ;;
  vidcombo) APP_NAME="VidCombo"; EXE_NAME="vidcombo.exe" ;;
  *) echo "Unknown brand: $BRAND (expected svid|vidcombo)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/windows_signing_common.sh
source "$SCRIPT_DIR/windows_signing_common.sh"

load_windows_signing_materials

WINDOWS_ZIP_PAYLOAD_STATE="${WINDOWS_ZIP_PAYLOAD_STATE:-unsigned}"

mkdir -p "$DEST_DIR"
# Resolve to absolute path BEFORE any `cd` — the repack step cds into the
# extract dir, which would break a relative DEST_DIR like "signed/".
DEST_DIR="$(cd "$DEST_DIR" && pwd)"

WORK_DIR="$(mktemp -d)"
# Force u+rwX before rm because Windows-created ZIPs (PowerShell Compress-Archive)
# extract some dirs without owner-write OR owner-execute on macOS, which makes
# plain `rm -rf` fail with "Permission denied" / "Directory not empty".
# Capital X adds execute only on dirs / already-executable files (safe).
trap 'chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

echo "==> Sign Windows artifacts for brand: $BRAND ($APP_NAME)"
echo "    Source : $SOURCE_DIR"
echo "    Dest   : $DEST_DIR"
echo "    Slot   : $(upper_slot "$YUBIKEY_PIV_SLOT") (${PKCS11_KEY_OBJECT})"

# === Process portable ZIP ===
ZIP_FILE="$(find "$SOURCE_DIR" -type f -name "${APP_NAME}-*-windows-x64.zip" -print -quit || true)"
if [ -n "$ZIP_FILE" ]; then
  echo
  echo "==> ZIP found: $ZIP_FILE"
  EXTRACT_DIR="$WORK_DIR/zip"
  mkdir -p "$EXTRACT_DIR"
  # PowerShell Compress-Archive writes ZIPs with backslash path separators,
  # which macOS unzip flags as a warning and exits with code 1. Code 1 means
  # "completed with warnings" (extracted successfully); only codes >=2 are
  # real errors. set -e would otherwise abort the whole script on RC=1.
  set +e
  unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
  UNZIP_RC=$?
  set -e
  if [ "$UNZIP_RC" -gt 1 ]; then
    echo "ERROR: unzip failed with exit code $UNZIP_RC" >&2
    exit 1
  fi

  # Some directories in the ZIP arrive without owner-execute on macOS, which
  # blocks both the repack step (`zip` cannot recurse into them) and the EXIT
  # trap cleanup (`rm` cannot delete entries inside them). Normalize now.
  chmod -R u+rwX "$EXTRACT_DIR"

  if [ ! -f "$EXTRACT_DIR/$EXE_NAME" ]; then
    echo "  WARN: $EXE_NAME not found in ZIP root" >&2
  fi

  # Repack — preserve filename + structure
  ZIP_BASENAME="$(basename "$ZIP_FILE")"
  rm -f "$DEST_DIR/$ZIP_BASENAME"
  case "$WINDOWS_ZIP_PAYLOAD_STATE" in
    presigned)
      echo "==> Verifying pre-signed PE payload inside ZIP"
      verify_pe_tree "$EXTRACT_DIR"
      cp "$ZIP_FILE" "$DEST_DIR/$ZIP_BASENAME"
      echo "==> Verified ZIP copied unchanged: $DEST_DIR/$ZIP_BASENAME"
      ;;
    unsigned)
      echo "==> Signing PE payload inside ZIP"
      sign_pe_tree_in_place "$EXTRACT_DIR"
      (cd "$EXTRACT_DIR" && zip -qr "$DEST_DIR/$ZIP_BASENAME" .)
      echo "==> Signed ZIP written: $DEST_DIR/$ZIP_BASENAME"
      ;;
    *)
      echo "ERROR: unsupported WINDOWS_ZIP_PAYLOAD_STATE: $WINDOWS_ZIP_PAYLOAD_STATE" >&2
      exit 2
      ;;
  esac
else
  echo "  WARN: no *-windows-x64.zip found for brand $APP_NAME under $SOURCE_DIR" >&2
fi

# === Process Inno Setup installer ===
SETUP_FILE="$(find "$SOURCE_DIR" -type f -name "${APP_NAME}-*-windows-x64-setup.exe" -print -quit || true)"
if [ -n "$SETUP_FILE" ]; then
  echo
  echo "==> Installer found: $SETUP_FILE"
  SETUP_BASENAME="$(basename "$SETUP_FILE")"
  echo "  → signing $SETUP_BASENAME"
  sign_pe_file "$SETUP_FILE" "$DEST_DIR/$SETUP_BASENAME"
  echo "  → verifying $SETUP_BASENAME"
  verify_pe_file "$DEST_DIR/$SETUP_BASENAME"
  echo "==> Signed installer written: $DEST_DIR/$SETUP_BASENAME"
else
  echo "  WARN: no *-windows-x64-setup.exe found for brand $APP_NAME under $SOURCE_DIR" >&2
fi

echo
echo "==> Done."
