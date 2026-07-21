#!/usr/bin/env bash
# Shared helpers for Windows Authenticode signing via YubiKey + Sectigo.

WINDOWS_SIGNING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${YUBIKEY_CERT_DIR:-$HOME/Desktop/yubikey-cert}"
SIGN_CHAIN="$CERT_DIR/sign_chain.pem"
SECRETS_FILE="$CERT_DIR/secrets.txt"
PKCS11_ENGINE="/opt/homebrew/lib/engines-3/pkcs11.dylib"
PKCS11_MODULE="/opt/homebrew/lib/libykcs11.dylib"
# Sectigo TSA accepts both HTTP and HTTPS for RFC 3161 timestamp POSTs.
# HTTPS prevents passive interception of the timestamp request/response and
# blocks an on-path attacker from delaying/replaying the nonce. The signed
# timestamp token itself is integrity-protected either way, but the transport
# hop is the one piece an operator can actually harden.
TIMESTAMP_URL="${TIMESTAMP_URL:-https://timestamp.sectigo.com}"
# No fallback: caller MUST set YUBIKEY_PIV_SLOT explicitly. The previous
# ':-9a' default allowed silent signing with the wrong slot — production
# convention is 9c (RSA). Removed because it permitted ECC-signed releases
# that triggered the WebView2Loader.dll Bad Image (0xc0e90002) class on
# Smart App Control. See docs/windows-ecc-to-rsa-migration.md.
if [ -z "${YUBIKEY_PIV_SLOT:-}" ]; then
  echo "ERROR: YUBIKEY_PIV_SLOT environment variable is not set." >&2
  echo "       The previous '9a' fallback was removed — caller must export" >&2
  echo "       the slot explicitly (production: YUBIKEY_PIV_SLOT=9c)." >&2
  echo "       Direct invocation example:" >&2
  echo "         YUBIKEY_PIV_SLOT=9c bash scripts/sign_windows_bundle.sh ..." >&2
  echo "       See docs/windows-ecc-to-rsa-migration.md." >&2
  exit 3
fi

lower_slot() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

upper_slot() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

slot_key_object() {
  case "$(lower_slot "$1")" in
    9a) printf '%s' 'Private key for PIV Authentication' ;;
    9c) printf '%s' 'Private key for Digital Signature' ;;
    9d) printf '%s' 'Private key for Key Management' ;;
    9e) printf '%s' 'Private key for Card Authentication' ;;
    *) echo "ERROR: unsupported YUBIKEY_PIV_SLOT: $1" >&2; exit 3 ;;
  esac
}

load_windows_signing_materials() {
  if [ ! -r "$SECRETS_FILE" ]; then
    echo "ERROR: secrets file not readable: $SECRETS_FILE" >&2
    exit 3
  fi

  PIN="$(awk '/^PIN:/ {print $2; exit}' "$SECRETS_FILE")"
  if [ -z "$PIN" ]; then
    echo "ERROR: failed to parse PIN from $SECRETS_FILE" >&2
    exit 3
  fi

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::add-mask::$PIN"
  fi

  for f in "$SIGN_CHAIN" "$PKCS11_ENGINE" "$PKCS11_MODULE"; do
    if [ ! -e "$f" ]; then
      echo "ERROR: required file missing: $f" >&2
      exit 3
    fi
  done

  enforce_windows_signing_policy

  PKCS11_KEY_OBJECT="$(slot_key_object "$YUBIKEY_PIV_SLOT")"
  PKCS11_KEY_URI="pkcs11:object=${PKCS11_KEY_OBJECT// /%20};type=private"
}

# Release Gate #1 from docs/windows-signing-policy.md:
#   "CI preflight must fail if the signing certificate is not RSA or is
#    expiring soon."
#
# Catches two historical disasters at BUILD time instead of USER time:
# 1. ECDSA-signed binaries — Smart App Control silently refuses to launch
#    them on Windows 11 (issue that blocked the v1.3.x line until the RSA
#    baseline landed in commit 952d8aac).
# 2. Cert that expires days after shipping — already-installed users keep
#    working, but new installs hit "unknown publisher" the moment the cert
#    crosses its notAfter timestamp.
#
# Override: set SKIP_WINDOWS_SIGNING_POLICY=1 for the rare case of signing a
# diagnostic/internal-only build with an expiring rollback cert. CI must NOT
# set this.
enforce_windows_signing_policy() {
  if [ "${SKIP_WINDOWS_SIGNING_POLICY:-0}" = "1" ]; then
    echo "WARN: windows signing policy check skipped (SKIP_WINDOWS_SIGNING_POLICY=1)" >&2
    return 0
  fi

  local algo bits expiry_days
  algo="$(openssl x509 -in "$SIGN_CHAIN" -noout -text 2>/dev/null \
    | awk -F': ' '/Public Key Algorithm/ {print $2; exit}')"
  bits="$(openssl x509 -in "$SIGN_CHAIN" -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -noout -text 2>/dev/null \
    | awk -F'[()]' '/Public-Key:/ {print $2; exit}' \
    | awk '{print $1}')"

  case "$algo" in
    rsaEncryption|rsa)
      # RSA path — enforce >= 3072 bit (Smart App Control + CA/B Forum).
      if [ -z "$bits" ] || [ "$bits" -lt 3072 ]; then
        echo "ERROR: RSA signing cert key size is '${bits:-unknown}' bits." >&2
        echo "       Policy requires RSA >= 3072. See docs/windows-signing-policy.md." >&2
        exit 3
      fi
      echo "  signing cert preflight: RSA ${bits}-bit OK"
      ;;
    id-ecPublicKey|ecdsa*|ec)
      # ECC path — production default is FAIL HARD.
      # Smart App Control on Windows 11 rejects ECDSA-signed installers,
      # producing the WebView2Loader.dll "Bad Image" 0xc0e90002 class of
      # crash on user machines. RSA cert (slot 9c) is the only valid
      # production signing path. See docs/windows-ecc-to-rsa-migration.md.
      #
      # Local diagnostic builds may bypass this gate by setting
      # WINDOWS_SIGNING_ALLOW_ECC=1. CI/release MUST NOT set this env var.
      if [ "${WINDOWS_SIGNING_ALLOW_ECC:-0}" = "1" ]; then
        echo "WARN: signing cert uses ECDSA (${bits:-?}-bit)." >&2
        echo "      Allowed because WINDOWS_SIGNING_ALLOW_ECC=1 (diagnostic only)." >&2
        echo "      DO NOT set this env var in CI/production pipelines." >&2
      else
        echo "ERROR: signing cert uses ECDSA (${bits:-?}-bit)." >&2
        echo "       Production default is FAIL — Smart App Control on Windows 11" >&2
        echo "       blocks ECDSA-signed installers (Bad Image 0xc0e90002)." >&2
        echo "       Production releases must use the RSA cert on slot 9c." >&2
        echo "       For local diagnostic builds only, set WINDOWS_SIGNING_ALLOW_ECC=1." >&2
        echo "       See docs/windows-ecc-to-rsa-migration.md." >&2
        exit 3
      fi
      ;;
    *)
      echo "ERROR: cannot determine signing cert key algorithm" >&2
      echo "       (openssl reported: '${algo:-<empty>}')." >&2
      exit 3
      ;;
  esac

  # openssl -checkend returns non-zero if the cert expires within the given
  # number of seconds — works identically on macOS and Linux runners.
  if ! openssl x509 -in "$SIGN_CHAIN" -noout -checkend 0 >/dev/null 2>&1; then
    echo "ERROR: signing cert is already expired. Renew before shipping." >&2
    exit 3
  fi
  if ! openssl x509 -in "$SIGN_CHAIN" -noout -checkend $((14 * 86400)) >/dev/null 2>&1; then
    echo "ERROR: signing cert expires within 14 days. Renew before shipping." >&2
    exit 3
  fi
  if ! openssl x509 -in "$SIGN_CHAIN" -noout -checkend $((30 * 86400)) >/dev/null 2>&1; then
    expiry_days="$(openssl x509 -in "$SIGN_CHAIN" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
    echo "WARN: signing cert expires within 30 days (notAfter=${expiry_days}) — plan renewal." >&2
  fi
}

sign_pe_file() {
  local input="$1"
  local output="$2"

  # libp11 reads RSA 9C PIN prompts through OpenSSL's UI callback. Plain stdin
  # piping works in some local shells but fails in GitHub Actions' self-hosted
  # runner context. Use expect to provide a pseudo-TTY and answer both token
  # and private-key PIN prompts without exposing the PIN in process argv.
  SIGNING_PIN="$PIN" \
  SIGNING_INPUT="$input" \
  SIGNING_OUTPUT="$output" \
  SIGNING_CHAIN="$SIGN_CHAIN" \
  SIGNING_KEY_URI="$PKCS11_KEY_URI" \
  SIGNING_PKCS11_ENGINE="$PKCS11_ENGINE" \
  SIGNING_PKCS11_MODULE="$PKCS11_MODULE" \
  SIGNING_TIMESTAMP_URL="$TIMESTAMP_URL" \
    timeout 60s expect "$WINDOWS_SIGNING_SCRIPT_DIR/sign_pe_with_expect.exp" \
    >/dev/null
}

verify_pe_file() {
  local file="$1"
  osslsigncode verify "$file" >/dev/null
}

is_microsoft_vcruntime_dll() {
  local base="$1"
  case "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" in
    msvcp140.dll|vcruntime140.dll|vcruntime140_1.dll) return 0 ;;
    *) return 1 ;;
  esac
}

# Probe a PE file's signer string via osslsigncode without requiring full
# chain validation. macOS OpenSSL does not ship Microsoft Root CA in its
# trust store, so a strict `osslsigncode verify` exit-code check fails for
# legitimately Microsoft-signed DLLs on this runner. Strong chain
# verification has already been performed at source-copy time on the
# Windows build runner (Get-AuthenticodeSignature in
# scripts/windows_bundle_vcruntime.ps1) which DOES have the Microsoft Root.
# Here we only confirm the signer string is Microsoft as a sanity guard
# against a file with the right filename but wrong contents — full chain
# trust is upstream of this step.
probe_microsoft_signer_string() {
  local file="$1"
  local verify_out
  # osslsigncode verify prints "Subject: ... Microsoft Corporation ..." in
  # its output even when chain validation fails (CA not in trust store).
  # We capture stdout+stderr without failing on non-zero exit.
  verify_out="$(osslsigncode verify "$file" 2>&1 || true)"
  if printf '%s' "$verify_out" | grep -qi 'Microsoft Corporation'; then
    return 0
  fi
  echo "    ERR: signer string 'Microsoft Corporation' not found for $(basename "$file")" >&2
  echo "$verify_out" >&2
  return 1
}

sign_pe_tree_in_place() {
  local root="$1"
  local manifest
  local count=0
  local skipped=0
  local file rel tmp base

  manifest="$(mktemp)"
  find "$root" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print | LC_ALL=C sort > "$manifest"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#$root/}"
    base="$(basename "$file")"

    # Microsoft VC++ runtime DLLs ship pre-signed by Microsoft. Do NOT re-sign
    # them. Full chain verification happened on the Windows build runner at
    # copy time (windows_bundle_vcruntime.ps1 uses Get-AuthenticodeSignature
    # against the Windows trusted root store). Here we only probe the signer
    # string as a sanity guard — macOS OpenSSL lacks Microsoft Root CA and
    # cannot perform chain validation, so we accept the upstream verification.
    if is_microsoft_vcruntime_dll "$base"; then
      echo "  → skip-sign (Microsoft-signed) $rel"
      if ! probe_microsoft_signer_string "$file"; then
        echo "ERROR: $rel matches Microsoft VC++ runtime name but signer string is not Microsoft" >&2
        exit 1
      fi
      skipped=$((skipped + 1))
      continue
    fi

    tmp="${file}.signed"
    echo "  → signing $rel"
    sign_pe_file "$file" "$tmp"
    mv "$tmp" "$file"
    echo "  → verifying $rel"
    verify_pe_file "$file"
    count=$((count + 1))
  done < "$manifest"

  rm -f "$manifest"

  echo "  → signed $count file(s); skipped $skipped Microsoft-signed runtime file(s)"

  if [ "$count" -eq 0 ]; then
    echo "ERROR: no Windows PE files (*.exe, *.dll) found under $root" >&2
    exit 1
  fi
}

verify_pe_tree() {
  local root="$1"
  local manifest
  local count=0
  local skipped=0
  local file rel base

  manifest="$(mktemp)"
  find "$root" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print | LC_ALL=C sort > "$manifest"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#$root/}"
    base="$(basename "$file")"

    # Microsoft VC++ runtime DLLs: skip strict osslsigncode chain verify on
    # macOS (no Microsoft Root CA in trust store); only probe signer string.
    # Mirror of sign_pe_tree_in_place — full chain verified upstream at P1
    # copy time on the Windows build runner.
    if is_microsoft_vcruntime_dll "$base"; then
      echo "  → verify-probe (Microsoft-signed) $rel"
      if ! probe_microsoft_signer_string "$file"; then
        echo "ERROR: $rel matches Microsoft VC++ runtime name but signer string is not Microsoft" >&2
        exit 1
      fi
      skipped=$((skipped + 1))
      continue
    fi

    echo "  → verifying $rel"
    verify_pe_file "$file"
    count=$((count + 1))
  done < "$manifest"

  rm -f "$manifest"

  echo "  → verified $count file(s); probed $skipped Microsoft-signed runtime file(s)"

  if [ "$count" -eq 0 ] && [ "$skipped" -eq 0 ]; then
    echo "ERROR: no Windows PE files (*.exe, *.dll) found under $root" >&2
    exit 1
  fi
}
