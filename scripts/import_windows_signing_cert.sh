#!/usr/bin/env bash
# =============================================================================
# Import the reissued Windows code-signing certificate into a YubiKey PIV slot
# and refresh the local cert files used by the signing scripts.
#
# Usage:
#   scripts/import_windows_signing_cert.sh <LEAF_CERT_PEM> <SIGN_CHAIN_PEM>
#
# Environment overrides:
#   YUBIKEY_PIV_SLOT default: 9c
#   YUBIKEY_CERT_DIR default: $HOME/Desktop/yubikey-cert
# =============================================================================

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <LEAF_CERT_PEM> <SIGN_CHAIN_PEM>" >&2
  exit 2
fi

LEAF_CERT_PEM="$1"
SIGN_CHAIN_PEM="$2"
CERT_DIR="${YUBIKEY_CERT_DIR:-$HOME/Desktop/yubikey-cert}"
YUBIKEY_PIV_SLOT="${YUBIKEY_PIV_SLOT:-9c}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

lower_slot() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

upper_slot() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

SLOT_LOWER="$(lower_slot "$YUBIKEY_PIV_SLOT")"
SLOT_UPPER="$(upper_slot "$YUBIKEY_PIV_SLOT")"

case "$SLOT_LOWER" in
  9a|9c|9d|9e) ;;
  *) fail "Unsupported YUBIKEY_PIV_SLOT: $YUBIKEY_PIV_SLOT" ;;
esac

command -v ykman >/dev/null 2>&1 || fail "ykman not found"
[ -f "$LEAF_CERT_PEM" ] || fail "Leaf certificate not found: $LEAF_CERT_PEM"
[ -f "$SIGN_CHAIN_PEM" ] || fail "Sign chain not found: $SIGN_CHAIN_PEM"
[ -d "$CERT_DIR" ] || fail "Cert directory not found: $CERT_DIR"
[ -f "$CERT_DIR/secrets.txt" ] || fail "Missing $CERT_DIR/secrets.txt"

PIN="$(awk '/^PIN:/ {print $2; exit}' "$CERT_DIR/secrets.txt")"
[ -n "$PIN" ] || fail "PIN line missing in $CERT_DIR/secrets.txt"

echo "==> Importing certificate into slot $SLOT_UPPER"
ykman piv certificates import \
  -P "$PIN" \
  --verify \
  "$SLOT_LOWER" \
  "$LEAF_CERT_PEM"

echo "==> Refreshing local signer cert files"
cp "$LEAF_CERT_PEM" "$CERT_DIR/leaf.pem"
cp "$SIGN_CHAIN_PEM" "$CERT_DIR/sign_chain.pem"

echo "==> Verifying imported certificate"
openssl x509 -in "$CERT_DIR/leaf.pem" -text -noout | \
  awk -F: '/Subject:|Issuer:|Public Key Algorithm:/ {print}'

echo
echo "Imported RSA Windows signing certificate into slot $SLOT_UPPER."
echo "Next step: run YUBIKEY_PIV_SLOT=$SLOT_LOWER bash scripts/preflight_yubikey.sh"
