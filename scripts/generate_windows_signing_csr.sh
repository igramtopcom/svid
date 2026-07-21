#!/usr/bin/env bash
# =============================================================================
# Generate a Windows code-signing RSA key + CSR on a YubiKey PIV slot.
#
# Defaults to slot 9C so we can stage the RSA migration without overwriting
# the current ECC cert in 9A.
# Defaults to RSA3072 because the active Sectigo reissue flow for this order
# rejects RSA2048.
#
# Usage:
#   scripts/generate_windows_signing_csr.sh [OUTPUT_DIR]
#
# Environment overrides:
#   YUBIKEY_PIV_SLOT    default: 9c
#   YUBIKEY_CERT_DIR    default: $HOME/Desktop/yubikey-cert
#   WINDOWS_CERT_SUBJECT default: CN=Bui Xuan Mai,O=Bui Xuan Mai,ST=Thai Binh,C=VN
#   WINDOWS_SIGNING_KEY_ALGORITHM default: RSA3072
# =============================================================================

set -euo pipefail

OUTPUT_DIR="${1:-$PWD/yubikey-csr}"
CERT_DIR="${YUBIKEY_CERT_DIR:-$HOME/Desktop/yubikey-cert}"
YUBIKEY_PIV_SLOT="${YUBIKEY_PIV_SLOT:-9c}"
WINDOWS_CERT_SUBJECT="${WINDOWS_CERT_SUBJECT:-CN=Bui Xuan Mai,O=Bui Xuan Mai,ST=Thai Binh,C=VN}"
WINDOWS_SIGNING_KEY_ALGORITHM="${WINDOWS_SIGNING_KEY_ALGORITHM:-RSA3072}"

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

case "$WINDOWS_SIGNING_KEY_ALGORITHM" in
  RSA2048|RSA3072|RSA4096) ;;
  *) fail "Unsupported WINDOWS_SIGNING_KEY_ALGORITHM: $WINDOWS_SIGNING_KEY_ALGORITHM" ;;
esac

command -v ykman >/dev/null 2>&1 || fail "ykman not found"
command -v openssl >/dev/null 2>&1 || fail "openssl not found"
[ -f "$CERT_DIR/secrets.txt" ] || fail "Missing $CERT_DIR/secrets.txt"

PIN="$(awk '/^PIN:/ {print $2; exit}' "$CERT_DIR/secrets.txt")"
[ -n "$PIN" ] || fail "PIN line missing in $CERT_DIR/secrets.txt"

mkdir -p "$OUTPUT_DIR"

PUBKEY_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.pub.pem"
CSR_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.csr.pem"
ATTEST_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.attestation.pem"
ATTEST_INTERMEDIATE_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.attestation-intermediate-f9.pem"
ATTEST_CHAIN_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.attestation-chain.pem"
ATTEST_B64_PATH="$OUTPUT_DIR/windows-signing-${SLOT_LOWER}.attestation.b64"

echo "==> Generating $WINDOWS_SIGNING_KEY_ALGORITHM key on slot $SLOT_UPPER"
ykman piv keys generate -P "$PIN" --algorithm "$WINDOWS_SIGNING_KEY_ALGORITHM" "$SLOT_LOWER" "$PUBKEY_PATH"

echo "==> Generating CSR"
ykman piv certificates request \
  -P "$PIN" \
  --subject "$WINDOWS_CERT_SUBJECT" \
  "$SLOT_LOWER" \
  "$PUBKEY_PATH" \
  "$CSR_PATH"

echo "==> Generating attestation certificate"
ykman piv keys attest "$SLOT_LOWER" "$ATTEST_PATH"

echo "==> Exporting YubiKey attestation intermediate from slot F9"
ykman piv certificates export f9 "$ATTEST_INTERMEDIATE_PATH"

echo "==> Building Sectigo attestation chain"
cat "$ATTEST_PATH" "$ATTEST_INTERMEDIATE_PATH" > "$ATTEST_CHAIN_PATH"

echo "==> Encoding attestation chain for Sectigo"
openssl base64 -A -in "$ATTEST_CHAIN_PATH" -out "$ATTEST_B64_PATH"

echo
echo "Generated:"
echo "  Public key : $PUBKEY_PATH"
echo "  CSR        : $CSR_PATH"
echo "  Attestation cert        : $ATTEST_PATH"
echo "  Attestation intermediate: $ATTEST_INTERMEDIATE_PATH"
echo "  Attestation chain       : $ATTEST_CHAIN_PATH"
echo "  Sectigo attestation.b64 : $ATTEST_B64_PATH"
echo
echo "Next step: send the CSR plus the contents of attestation.b64 to Sectigo for RSA reissue on the same publisher identity."
