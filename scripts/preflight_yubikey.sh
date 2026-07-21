#!/usr/bin/env bash
# =============================================================================
# Pre-flight check for YubiKey + Sectigo signing toolchain.
#
# Run before sign_windows_artifacts.sh in CI to fail-fast with clear errors
# rather than half-failing inside osslsigncode.
#
# Exits 0 if everything is ready to sign; non-zero with explicit message if
# any precondition is missing.
# =============================================================================

set -euo pipefail

CERT_DIR="${YUBIKEY_CERT_DIR:-$HOME/Desktop/yubikey-cert}"
PKCS11_ENGINE="/opt/homebrew/lib/engines-3/pkcs11.dylib"
PKCS11_MODULE="/opt/homebrew/lib/libykcs11.dylib"
EXPIRY_WARN_DAYS=30
# No fallback: caller MUST set YUBIKEY_PIV_SLOT explicitly. The previous
# ':-9a' default allowed silent signing with the wrong slot. Removed
# because it let ECC-signed releases pass preflight on hardware where 9c
# (RSA) was actually provisioned. See docs/windows-ecc-to-rsa-migration.md.
if [ -z "${YUBIKEY_PIV_SLOT:-}" ]; then
  echo "❌ PREFLIGHT FAIL: YUBIKEY_PIV_SLOT environment variable is not set." >&2
  echo "   The previous '9a' fallback was removed — caller must export" >&2
  echo "   the slot explicitly (production: YUBIKEY_PIV_SLOT=9c)." >&2
  echo "   Example:" >&2
  echo "     YUBIKEY_PIV_SLOT=9c bash scripts/preflight_yubikey.sh" >&2
  echo "   See docs/windows-ecc-to-rsa-migration.md." >&2
  exit 1
fi
WINDOWS_SIGNING_MIN_RSA_BITS="${WINDOWS_SIGNING_MIN_RSA_BITS:-3072}"
SLOT_CERT_TMP=""

cleanup() {
  [ -n "$SLOT_CERT_TMP" ] && rm -f "$SLOT_CERT_TMP"
}

trap cleanup EXIT

fail() {
  echo "❌ PREFLIGHT FAIL: $*" >&2
  exit 1
}

ok() {
  echo "✅ $*"
}

lower_slot() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

upper_slot() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

slot_cert_label() {
  case "$(lower_slot "$1")" in
    9a) printf '%s' 'X.509 Certificate for PIV Authentication' ;;
    9c) printf '%s' 'X.509 Certificate for Digital Signature' ;;
    9d) printf '%s' 'X.509 Certificate for Key Management' ;;
    9e) printf '%s' 'X.509 Certificate for Card Authentication' ;;
    *) fail "Unsupported YUBIKEY_PIV_SLOT: $1" ;;
  esac
}

echo "==> YubiKey signing pre-flight checks"
echo "==> Target slot: $(upper_slot "$YUBIKEY_PIV_SLOT")"

# 1. Toolchain binaries
command -v osslsigncode >/dev/null 2>&1 || fail "osslsigncode not on PATH (brew install osslsigncode)"
ok "osslsigncode: $(osslsigncode --version 2>&1 | head -1)"

command -v ykman >/dev/null 2>&1 || fail "ykman not on PATH (brew install ykman)"
ok "ykman present"

command -v pkcs11-tool >/dev/null 2>&1 || fail "pkcs11-tool not on PATH (brew install opensc)"
ok "pkcs11-tool present"

command -v expect >/dev/null 2>&1 || fail "expect not on PATH (required for non-interactive RSA 9C PIN prompts)"
ok "expect present"

# 2. PKCS#11 engine + YubiKey module files
[ -f "$PKCS11_ENGINE" ] || fail "PKCS#11 engine missing: $PKCS11_ENGINE (brew install libp11)"
ok "PKCS#11 engine: $PKCS11_ENGINE"

[ -f "$PKCS11_MODULE" ] || fail "YubiKey PKCS#11 module missing: $PKCS11_MODULE (brew install yubico-piv-tool)"
ok "PKCS#11 module: $PKCS11_MODULE"

# 3. Cert directory + required files
[ -d "$CERT_DIR" ] || fail "Cert directory missing: $CERT_DIR"
ok "Cert dir: $CERT_DIR"

for f in sign_chain.pem secrets.txt leaf.pem; do
  [ -f "$CERT_DIR/$f" ] || fail "$CERT_DIR/$f missing"
done
ok "sign_chain.pem + secrets.txt + leaf.pem present"

# 4. secrets.txt parseable PIN
PIN="$(awk '/^PIN:/ {print $2; exit}' "$CERT_DIR/secrets.txt")"
[ -n "$PIN" ] || fail "PIN line missing in $CERT_DIR/secrets.txt"
ok "PIN parsed from secrets.txt (${#PIN} chars)"

# 5. YubiKey hardware reachable + target-slot cert present.
# Note: private keys require PIN login to enumerate via pkcs11-tool, but the
# leaf cert is publicly readable. Checking the expected cert label is
# sufficient + safer than testing private-key operations here.
CERT_LABEL="$(slot_cert_label "$YUBIKEY_PIV_SLOT")"
if ! pkcs11-tool --module "$PKCS11_MODULE" --list-objects --type cert 2>&1 \
    | grep -q "$CERT_LABEL"; then
  SLOT_UPPER="$(upper_slot "$YUBIKEY_PIV_SLOT")"
  fail "YubiKey not detected or slot $SLOT_UPPER empty. Cắm YubiKey + đảm bảo slot $SLOT_UPPER có cert."
fi
ok "YubiKey detected + slot $(upper_slot "$YUBIKEY_PIV_SLOT") has cert"

# Export the cert directly from the target slot so preflight verifies the
# material that will actually sign, not just the copy on disk.
SLOT_CERT_TMP="$(mktemp "${TMPDIR:-/tmp}/yubikey-slot-cert.XXXXXX.pem")"
if ! ykman piv certificates export "$(lower_slot "$YUBIKEY_PIV_SLOT")" "$SLOT_CERT_TMP" >/dev/null 2>&1; then
  fail "Failed to export certificate from slot $(upper_slot "$YUBIKEY_PIV_SLOT") via ykman"
fi
ok "Exported slot $(upper_slot "$YUBIKEY_PIV_SLOT") certificate for verification"

LOCAL_FP="$(openssl x509 -in "$CERT_DIR/leaf.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
SLOT_FP="$(openssl x509 -in "$SLOT_CERT_TMP" -noout -fingerprint -sha256 | cut -d= -f2)"
[ -n "$LOCAL_FP" ] || fail "Could not read SHA-256 fingerprint from $CERT_DIR/leaf.pem"
[ -n "$SLOT_FP" ] || fail "Could not read SHA-256 fingerprint from slot $(upper_slot "$YUBIKEY_PIV_SLOT") cert"

if [ "$LOCAL_FP" != "$SLOT_FP" ]; then
  fail "slot $(upper_slot "$YUBIKEY_PIV_SLOT") cert does not match $CERT_DIR/leaf.pem. Run scripts/import_windows_signing_cert.sh or refresh local signer files."
fi
ok "Local leaf.pem matches slot $(upper_slot "$YUBIKEY_PIV_SLOT") certificate"

# 6. Cert not expiring soon
EXPIRY_RAW="$(openssl x509 -in "$SLOT_CERT_TMP" -noout -enddate | sed 's/notAfter=//')"
EXPIRY_EPOCH="$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_RAW" +%s 2>/dev/null || echo 0)"
NOW_EPOCH="$(date +%s)"

if [ "$EXPIRY_EPOCH" -eq 0 ]; then
  echo "  ⚠ Could not parse cert expiry, skipping expiry check" >&2
else
  DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
  if [ "$DAYS_LEFT" -lt 0 ]; then
    fail "Cert EXPIRED $((-DAYS_LEFT)) days ago ($EXPIRY_RAW)"
  elif [ "$DAYS_LEFT" -lt "$EXPIRY_WARN_DAYS" ]; then
    echo "  ⚠ Cert expires in $DAYS_LEFT days ($EXPIRY_RAW) — plan renewal"
  fi
  ok "Cert valid for $DAYS_LEFT more days (expires $EXPIRY_RAW)"
fi

# 7. Windows Smart App Control requires RSA-based code signing certs.
#    Production default: FAIL hard on ECDSA. Smart App Control on Windows 11
#    rejects ECDSA-signed installers (manifest as WebView2Loader.dll
#    "Bad Image" 0xc0e90002 crash on user machines).
#    Local diagnostic builds may bypass this gate via
#    WINDOWS_SIGNING_ALLOW_ECC=1. CI/release MUST NOT set this env var.
#    See docs/windows-ecc-to-rsa-migration.md.
PUBKEY_ALGO="$(openssl x509 -in "$SLOT_CERT_TMP" -text -noout \
  | awk -F: '/Public Key Algorithm:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
[ -n "$PUBKEY_ALGO" ] || fail "Could not read public key algorithm from slot $(upper_slot "$YUBIKEY_PIV_SLOT") cert"

KEY_BITS="$(openssl x509 -in "$SLOT_CERT_TMP" -text -noout \
  | awk -F'[()]' '/Public-Key:/ {gsub(/ bit/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')"

case "$PUBKEY_ALGO" in
  rsaEncryption|rsa)
    if [ -n "$KEY_BITS" ] && [ "$KEY_BITS" -lt "$WINDOWS_SIGNING_MIN_RSA_BITS" ]; then
      fail "Windows release signing cert must be at least RSA $WINDOWS_SIGNING_MIN_RSA_BITS (found: RSA $KEY_BITS)"
    fi
    ok "Windows signing policy: RSA ${KEY_BITS:-unknown}-bit certificate"
    ;;
  id-ecPublicKey|ecdsa*|ec)
    if [ "${WINDOWS_SIGNING_ALLOW_ECC:-0}" = "1" ]; then
      echo "  ⚠ Windows signing cert is ECDSA (${KEY_BITS:-?}-bit)." >&2
      echo "    Allowed because WINDOWS_SIGNING_ALLOW_ECC=1 (diagnostic only)." >&2
      echo "    DO NOT set this env var in CI/production pipelines." >&2
      ok "Windows signing policy: ECDSA ${KEY_BITS:-unknown}-bit (diagnostic override)"
    else
      echo "  ✗ Windows signing cert is ECDSA (${KEY_BITS:-?}-bit)." >&2
      echo "    Production default is FAIL — Smart App Control on Windows 11" >&2
      echo "    blocks ECDSA-signed installers (Bad Image 0xc0e90002)." >&2
      echo "    Production releases must use the RSA cert on slot 9c." >&2
      echo "    For local diagnostic builds only, set WINDOWS_SIGNING_ALLOW_ECC=1." >&2
      echo "    See docs/windows-ecc-to-rsa-migration.md." >&2
      fail "Windows release signing cert is ECDSA — RSA required for production"
    fi
    ;;
  *)
    fail "Windows release signing cert uses unsupported algorithm: $PUBKEY_ALGO"
    ;;
esac

echo
echo "==> All pre-flight checks passed. Ready to sign."
