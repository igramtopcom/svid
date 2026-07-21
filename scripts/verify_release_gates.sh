#!/usr/bin/env bash
# =============================================================================
# Release gates aggregator — runs every Installer/Native CTO quality gate
# in one invocation. Returns non-zero if ANY gate fails so the script can
# be wired into CI or a local pre-push hook.
#
# Each gate is best-effort and isolated: a missing dependency (docker,
# openssl, cargo, YubiKey cert materials) produces a SKIP instead of a
# FAIL, so a developer on a laptop without the full release toolchain
# still gets a green signal on the gates they CAN run.
#
# Usage:
#   bash scripts/verify_release_gates.sh [--fast]
#
#   --fast   Skip the Docker Inno Setup compile (~30-60s) and the Release
#            build smoke. Useful in a pre-commit loop. CI should NOT pass
#            --fast.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

FAST_MODE=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST_MODE=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# -----------------------------------------------------------------------------
# Result tracking. Each gate records exactly one of: PASS / FAIL / SKIP / WARN.
# -----------------------------------------------------------------------------
declare -a RESULTS=()

record() {
  local id="$1" status="$2" detail="${3:-}"
  RESULTS+=("${status}|${id}|${detail}")
  local color
  case "$status" in
    PASS) color='\033[0;32m' ;;
    FAIL) color='\033[0;31m' ;;
    WARN) color='\033[0;33m' ;;
    SKIP) color='\033[0;90m' ;;
    *)    color='' ;;
  esac
  printf '%b[%s]%b %s' "$color" "$status" '\033[0m' "$id"
  [ -n "$detail" ] && printf ' — %s' "$detail"
  printf '\n'
}

if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

# -----------------------------------------------------------------------------
# Gate 1 — flutter analyze. Any `error` severity is a FAIL; `info` / `warning`
# is surfaced as WARN but does not block.
# -----------------------------------------------------------------------------
echo
echo "== Gate 1 — flutter analyze =="
# `flutter analyze` exits non-zero whenever ANY issue is found — including
# info and warning severities that shouldn't block a release. Classify by
# output content, not exit code: errors block, warnings/info do not.
analyze_out="$(mktemp)"
"${FLUTTER[@]}" analyze --no-pub >"$analyze_out" 2>&1 || true
if grep -qE '^[[:space:]]*error ' "$analyze_out"; then
  record G1.analyze FAIL "error-level issues present"
  grep -E '^[[:space:]]*error ' "$analyze_out" | head -5 | sed 's/^/    /'
elif grep -qE '^[[:space:]]*(warning|info) ' "$analyze_out"; then
  count=$(grep -cE '^[[:space:]]*(warning|info) ' "$analyze_out")
  record G1.analyze WARN "$count non-error issue(s) (acceptable)"
else
  record G1.analyze PASS
fi
rm -f "$analyze_out"

# -----------------------------------------------------------------------------
# Gate 2 — em's locked unit tests. Runs only the test files this session
# landed or hardened; full `flutter test` is slower and exposes pre-
# existing unrelated flakes. CI with full `flutter test` is the umbrella.
# -----------------------------------------------------------------------------
echo
echo "== Gate 2 — locked unit tests =="
test_files=(
  test/core/binaries/binary_downloader_checksum_test.dart
  test/core/services/auto_update_service_test.dart
  test/core/services/startup_profiler_test.dart
  test/core/services/startup_service_vidcombo_cache_test.dart
  test/core/services/tray_service_test.dart
  test/core/services/device_auth_service_test.dart
  test/core/services/window_service_test.dart
  test/features/downloads/data/services/vidcombo_installer_marker_policy_test.dart
  test/features/downloads/data/services/vidcombo_legacy_importer_test.dart
)
present=()
for t in "${test_files[@]}"; do
  [ -f "$t" ] && present+=("$t")
done
if [ "${#present[@]}" -eq 0 ]; then
  record G2.tests SKIP "none of the locked test files exist yet"
else
  test_out="$(mktemp)"
  if "${FLUTTER[@]}" test "${present[@]}" --dart-define=BRAND=svid >"$test_out" 2>&1; then
    passed=$(grep -oE '[0-9]+: All tests passed' "$test_out" | tail -1)
    record G2.tests PASS "${passed:-all green}"
  else
    record G2.tests FAIL "test failures"
    grep -E '(FAIL|Expected:|Actual:)' "$test_out" | head -10 | sed 's/^/    /'
  fi
  rm -f "$test_out"
fi

# -----------------------------------------------------------------------------
# Gate 3 — Windows signing policy preflight. Requires openssl + the
# YubiKey cert materials. Honors SKIP_WINDOWS_SIGNING_POLICY semantics
# as the underlying common.sh does.
# -----------------------------------------------------------------------------
echo
echo "== Gate 3 — Windows signing policy =="
CERT_DIR_DEFAULT="$HOME/Desktop/yubikey-cert"
CERT_DIR="${YUBIKEY_CERT_DIR:-$CERT_DIR_DEFAULT}"
if ! command -v openssl >/dev/null 2>&1; then
  record G3.signing SKIP "openssl not on PATH"
elif [ ! -r "$CERT_DIR/sign_chain.pem" ]; then
  record G3.signing SKIP "signing cert not available at $CERT_DIR/sign_chain.pem"
else
  (
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/windows_signing_common.sh"
    SIGN_CHAIN="$CERT_DIR/sign_chain.pem" enforce_windows_signing_policy
  ) >/tmp/g3.out 2>&1
  if [ $? -eq 0 ]; then
    record G3.signing PASS "$(tail -1 /tmp/g3.out)"
  else
    record G3.signing FAIL "$(tail -3 /tmp/g3.out | tr '\n' ';')"
  fi
  rm -f /tmp/g3.out
fi

# -----------------------------------------------------------------------------
# Gate 4 — Rust cargo check. Ensures Rust side still compiles cleanly
# after any Dart/Flutter change that touched the FRB layer.
# -----------------------------------------------------------------------------
echo
echo "== Gate 4 — Rust cargo check =="
if ! command -v cargo >/dev/null 2>&1; then
  record G4.rust SKIP "cargo not installed"
elif [ ! -f "$ROOT_DIR/native/Cargo.toml" ]; then
  record G4.rust SKIP "native/Cargo.toml missing"
else
  rust_out="$(mktemp)"
  if (cd "$ROOT_DIR/native" && cargo check --quiet) >"$rust_out" 2>&1; then
    record G4.rust PASS
  else
    record G4.rust FAIL "cargo check failed"
    tail -5 "$rust_out" | sed 's/^/    /'
  fi
  rm -f "$rust_out"
fi

# -----------------------------------------------------------------------------
# Gate 5 — Brand asset sanity. Delegates to the existing
# verify_brand_assets.sh which checks icon / plist / xcconfig parity.
# -----------------------------------------------------------------------------
echo
echo "== Gate 5 — Brand assets =="
if [ -x "$SCRIPT_DIR/verify_brand_assets.sh" ]; then
  for brand in svid vidcombo; do
    if bash "$SCRIPT_DIR/verify_brand_assets.sh" "$brand" >/tmp/g5.out 2>&1; then
      record "G5.assets.$brand" PASS
    else
      record "G5.assets.$brand" FAIL
      tail -5 /tmp/g5.out | sed 's/^/    /'
    fi
    rm -f /tmp/g5.out
  done
else
  record G5.assets SKIP "verify_brand_assets.sh missing"
fi

# -----------------------------------------------------------------------------
# Gate 6 — Inno Setup Docker compile. Confirms `installer_windows.iss`
# still compiles for both brands after any iss / BrandConfig change —
# caught the Wave 3 dual-[Run] syntax this way.
# -----------------------------------------------------------------------------
echo
echo "== Gate 6 — Inno Setup compile (svid + vidcombo) =="
if [ "$FAST_MODE" -eq 1 ]; then
  record G6.iscc SKIP "--fast mode"
elif ! command -v docker >/dev/null 2>&1; then
  record G6.iscc SKIP "docker not available"
elif ! docker info >/dev/null 2>&1; then
  record G6.iscc SKIP "docker daemon not running"
else
  STUB_DIR="$ROOT_DIR/.iscc-stub"
  rm -rf "$STUB_DIR" && mkdir -p "$STUB_DIR"
  touch "$STUB_DIR/svid.exe" "$STUB_DIR/vidcombo.exe" \
        "$STUB_DIR/native.dll" "$STUB_DIR/app_icon.ico"

  compile_brand() {
    local brand="$1" version="$2" defs=("${@:3}")
    local out="$(mktemp)"
    if docker run --rm -v "$ROOT_DIR:/work" amake/innosetup \
         "/DMyAppVersion=$version" "/DMyBuildSource=Z:\\work\\.iscc-stub" \
         "${defs[@]}" \
         /work/scripts/installer_windows.iss >"$out" 2>&1; then
      if grep -q 'Successful compile' "$out"; then
        record "G6.iscc.$brand" PASS "$(grep -oE 'Resulting Setup program filename is:.*' "$out" | tail -1)"
      else
        record "G6.iscc.$brand" WARN "no explicit success marker but exit 0"
      fi
    else
      record "G6.iscc.$brand" FAIL
      tail -10 "$out" | sed 's/^/    /'
    fi
    rm -f "$out"
  }

  compile_brand svid "1.0.0" \
    "/DMyAppName=Svid" "/DMyAppExeName=svid.exe" \
    "/DMyAppPublisher=Svid" "/DMyAppCompany=Bui Xuan Mai" \
    "/DMyAppProductName=Svid Desktop" \
    "/DMyAppFileDescription=Svid Desktop Installer" \
    "/DMyAppCopyright=Copyright (C) 2026 Bui Xuan Mai. All rights reserved." \
    "/DMyAppURL=https://svid.app" "/DMyUrlScheme=svid" \
    "/DMyAppUserModelId=com.svid.app"
  compile_brand vidcombo "1.0.0" \
    "/DMyAppName=VidCombo" "/DMyAppExeName=vidcombo.exe" \
    "/DMyAppPublisher=VidCombo" "/DMyAppCompany=Bui Xuan Mai" \
    "/DMyAppProductName=VidCombo Desktop" \
    "/DMyAppFileDescription=VidCombo Desktop Installer" \
    "/DMyAppCopyright=Copyright (C) 2026 Bui Xuan Mai. All rights reserved." \
    "/DMyAppURL=https://vidcombo.net" \
    "/DMyAppId={{C6BC5050-3D98-47F7-8F1E-3DC53963381A}" \
    "/DMyUrlScheme=vidcombo" \
    "/DMyAppUserModelId=com.tinasoft.vidcombo.desktop"

  rm -rf "$STUB_DIR"
  # Clean up test installer artefacts Inno Setup dropped in dist/.
  rm -f "$ROOT_DIR/dist/Svid-1.0.0-windows-x64-setup.exe" \
        "$ROOT_DIR/dist/VidCombo-1.0.0-windows-x64-setup.exe"
fi

# -----------------------------------------------------------------------------
# Summary — aggregate results + final exit code.
# -----------------------------------------------------------------------------
echo
echo "=============================================================="
echo "Release Gates Summary"
echo "=============================================================="
pass=0; fail=0; warn=0; skip=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r status id detail <<<"$r"
  case "$status" in
    PASS) ((pass++)) ;;
    FAIL) ((fail++)) ;;
    WARN) ((warn++)) ;;
    SKIP) ((skip++)) ;;
  esac
done
printf "  PASS: %d\n  FAIL: %d\n  WARN: %d\n  SKIP: %d\n" \
       "$pass" "$fail" "$warn" "$skip"
echo "=============================================================="

if [ "$fail" -gt 0 ]; then
  echo "Release BLOCKED — at least one gate is red."
  exit 1
fi
if [ "$pass" -eq 0 ]; then
  echo "WARN: no gate passed — every gate skipped, probably missing tools."
  exit 2
fi
echo "Release gates: all runnable gates green."
exit 0
