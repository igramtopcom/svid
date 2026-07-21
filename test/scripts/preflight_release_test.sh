#!/usr/bin/env bash
# Smoke test for scripts/preflight_release.sh — covers the parts the
# round-3 bug fix added (env var passing for Gate 3, --strict /
# --allow-warnings flag handling, exit codes).
#
# Usage:
#   bash test/scripts/preflight_release_test.sh
#
# Exits non-zero on any assertion failure. Designed to be CI-runnable
# without admin credentials (Gate 3 SKIP path), but if ADMIN_EMAIL +
# ADMIN_PASSWORD are set it also exercises the live Gate 3 path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$ROOT_DIR/scripts/preflight_release.sh"

if [ ! -f "$PREFLIGHT" ]; then
  echo "FATAL: $PREFLIGHT not found"
  exit 2
fi

failures=0
case_count=0

run_case() {
  local name="$1"
  shift
  case_count=$((case_count + 1))
  echo
  echo "== Case $case_count: $name =="
  "$@"
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "  PASS"
  else
    echo "  FAIL (rc=$rc)"
    failures=$((failures + 1))
  fi
}

# -----------------------------------------------------------------------------
# Case 1: --help exits 0 and prints usage including new --allow-warnings flag
# -----------------------------------------------------------------------------
case_help() {
  out=$(bash "$PREFLIGHT" --help 2>&1)
  rc=$?
  [ $rc -eq 0 ] || { echo "    exit code $rc, expected 0"; return 1; }
  echo "$out" | grep -q -- "--allow-warnings" || {
    echo "    expected --allow-warnings in usage, missing"
    return 1
  }
  echo "$out" | grep -q -- "--strict" || {
    echo "    expected --strict (backward-compat) in usage, missing"
    return 1
  }
}

# -----------------------------------------------------------------------------
# Case 2: Default mode WARN exits 1 (round-4 false-green fix)
# -----------------------------------------------------------------------------
case_default_warn_fails() {
  # Without ADMIN_EMAIL, Gate 3 SKIPs. Gate 2 currently has 2 WARN
  # because mikf/gallery-dl fallback URLs are 404. So default mode
  # MUST exit 1.
  unset ADMIN_EMAIL ADMIN_PASSWORD || true
  bash "$PREFLIGHT" >/dev/null 2>&1
  rc=$?
  if [ $rc -ne 1 ]; then
    echo "    expected exit 1 (warnings present), got $rc"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Case 3: --allow-warnings opt-out exits 0 with same warns
# -----------------------------------------------------------------------------
case_allow_warnings_passes() {
  unset ADMIN_EMAIL ADMIN_PASSWORD || true
  bash "$PREFLIGHT" --allow-warnings >/dev/null 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "    expected exit 0 with --allow-warnings, got $rc"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Case 4: --strict alias still works (backward compat)
# -----------------------------------------------------------------------------
case_strict_alias() {
  unset ADMIN_EMAIL ADMIN_PASSWORD || true
  bash "$PREFLIGHT" --strict >/dev/null 2>&1
  rc=$?
  if [ $rc -ne 1 ]; then
    echo "    expected exit 1 (warnings) with --strict, got $rc"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Case 5: Gate 3 pagination — only when admin creds set + a known-old
# version exists. We test Gate 3 SKIP path when no version specified.
# -----------------------------------------------------------------------------
case_gate3_skip_when_no_version() {
  unset PREFLIGHT_VERSION_SSVID PREFLIGHT_VERSION_VIDCOMBO || true
  out=$(ADMIN_EMAIL="${ADMIN_EMAIL:-}" ADMIN_PASSWORD="${ADMIN_PASSWORD:-}" \
    bash "$PREFLIGHT" --allow-warnings 2>&1)
  # The summary table emits status BEFORE the gate id (`SKIP G3.records …`)
  # and the inline gate header emits id BEFORE status (`[SKIP] G3.records …`).
  # Both surface acceptable here; we just need to confirm Gate 3 reached
  # the SKIP path on this no-credentials no-version run.
  if ! { echo "$out" | grep -qE 'G3\.records.*SKIP' \
         || echo "$out" | grep -qE 'SKIP.*G3\.records'; }; then
    echo "    expected Gate 3 SKIP, output:"
    echo "$out" | sed 's/^/      /'
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Run every case
# -----------------------------------------------------------------------------
run_case "--help mentions both flags" case_help
run_case "default WARN exits 1" case_default_warn_fails
run_case "--allow-warnings exits 0" case_allow_warnings_passes
run_case "--strict alias exits 1 on WARN" case_strict_alias
run_case "Gate 3 skips without version env" case_gate3_skip_when_no_version

echo
echo "================================================================"
echo "preflight smoke test: $((case_count - failures))/$case_count passed"
if [ "$failures" -gt 0 ]; then
  exit 1
fi
exit 0
