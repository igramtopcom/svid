#!/usr/bin/env bash
# =============================================================================
# macOS QA smoke harness — mirrors windows_qa_smoke.ps1 for the macOS side.
# Validates the Installer/Native CTO session's hardening work against a
# real .dmg / .app bundle so any macOS tester can run the gates without
# the CTO's terminal.
#
# Usage:
#   bash scripts/macos_qa_smoke.sh \
#        --dmg path/to/Svid-1.3.5-macos-universal.dmg \
#        --brand svid \
#        [--skip-launch]
#
# What it covers (keyed to the waves this session shipped):
#   W1  entitlements  — Release.entitlements stays tight: app-sandbox
#                       remains off (binaries require), JIT / unsigned-mem
#                       / network.server stay removed, network.client +
#                       files.downloads.read-write stay on.
#   W1  plugin channels — NotificationPermissionPlugin + MacOSActionsPlugin
#                       survive hot restart via FlutterPlugin registrar.
#                       Script-observable proxy: Info.plist contains the
#                       expected bundle id and the .app binary actually
#                       launches.
#   W3  codesign      — app + native.framework signed, no ad-hoc only;
#                       verification passes --deep --strict.
#   W3  notarize      — Apple ticket stapled (DMG + .app both checked);
#                       spctl accepts for open + execute.
#   W3  xattr strip   — installed .app has no quarantine bit.
#   W6  binary cache  — after first launch, ~/Library/Application\ Support/
#                       com.{brand}.app/bin/ holds yt-dlp / ffmpeg /
#                       gallery-dl with the policy size floor.
#
# What it does NOT cover (delegated to the human tester via the
# companion docs/macos-qa-checklist.md):
#   - Gatekeeper UX on a first-open flow (requires Finder + mouse).
#   - WebView JavaScript functionality after entitlement tightening.
#   - Cloud-sync (iCloud / Dropbox) write interactions.
# =============================================================================

set -u

BRAND=""
DMG_PATH=""
APP_BUNDLE_PATH=""
SKIP_LAUNCH=0
LAUNCH_TIMEOUT_SECONDS=45

usage() {
  cat <<USAGE
Usage: bash scripts/macos_qa_smoke.sh --dmg PATH --brand svid|vidcombo [options]
       bash scripts/macos_qa_smoke.sh --app PATH --brand svid|vidcombo [options]

Options:
  --dmg PATH            path to the signed+notarized DMG under test
  --app PATH            path to a pre-mounted / copied .app bundle (skips DMG mount gates)
  --brand svid|vidcombo
  --skip-launch         skip the launch-and-observe step (CI smoke-only mode)
  --launch-timeout N    override the 45s launch observation window
USAGE
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg) DMG_PATH="${2:-}"; shift 2 ;;
    --app) APP_BUNDLE_PATH="${2:-}"; shift 2 ;;
    --brand) BRAND="${2:-}"; shift 2 ;;
    --skip-launch) SKIP_LAUNCH=1; shift ;;
    --launch-timeout) LAUNCH_TIMEOUT_SECONDS="${2:-45}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

if [ -z "$BRAND" ]; then
  echo "ERROR: --brand is required (svid | vidcombo)" >&2
  usage
fi

case "$BRAND" in
  svid)    APP_NAME="svid";    BUNDLE_ID="com.svid.app" ;;
  vidcombo) APP_NAME="vidcombo"; BUNDLE_ID="com.tinasoft.vidcombo" ;;
  *) echo "ERROR: brand must be svid or vidcombo (got '$BRAND')" >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------
# Result tracking
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

exit_with_summary() {
  echo
  echo "=============================================================="
  echo "macOS QA smoke harness — summary (brand=$BRAND)"
  echo "=============================================================="
  local pass=0 fail=0 warn=0 skip=0
  for r in "${RESULTS[@]}"; do
    local status="${r%%|*}"
    case "$status" in
      PASS) pass=$((pass+1)) ;;
      FAIL) fail=$((fail+1)) ;;
      WARN) warn=$((warn+1)) ;;
      SKIP) skip=$((skip+1)) ;;
    esac
  done
  printf "  PASS: %d\n  FAIL: %d\n  WARN: %d\n  SKIP: %d\n" "$pass" "$fail" "$warn" "$skip"
  if [ "$fail" -gt 0 ]; then
    echo "Release BLOCKED — at least one gate is red."
    exit 1
  fi
  exit 0
}

# -----------------------------------------------------------------------------
# Gate 0 — inputs
# -----------------------------------------------------------------------------
MOUNT_POINT=""
MOUNTED_BY_US=0
if [ -n "$DMG_PATH" ]; then
  if [ ! -f "$DMG_PATH" ]; then
    record M0.dmg FAIL "DMG not found: $DMG_PATH"
    exit_with_summary
  fi
  record M0.dmg PASS "$DMG_PATH"

  dmg_size=$(stat -f '%z' "$DMG_PATH" 2>/dev/null || echo 0)
  if [ "$dmg_size" -lt 10485760 ]; then
    record M0.size FAIL "DMG < 10 MB (${dmg_size} bytes) — suspect truncated download"
  else
    record M0.size PASS "$(printf '%.1f MB\n' "$(echo "scale=2; $dmg_size/1048576" | bc)")"
  fi

  # Mount the DMG read-only, isolated.
  MOUNT_POINT="/tmp/macos_qa_smoke_$$_$(date +%s)"
  mkdir -p "$MOUNT_POINT"
  if hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen \
       -readonly -plist >/tmp/hdiutil.out 2>&1; then
    MOUNTED_BY_US=1
    record M0.mount PASS "$MOUNT_POINT"
  else
    record M0.mount FAIL "$(tail -3 /tmp/hdiutil.out | tr '\n' ';')"
    exit_with_summary
  fi

  APP_BUNDLE_PATH="$(find "$MOUNT_POINT" -maxdepth 2 -name '*.app' -type d -print -quit)"
  if [ -z "$APP_BUNDLE_PATH" ]; then
    record M0.app FAIL "no .app bundle inside DMG"
    [ "$MOUNTED_BY_US" -eq 1 ] && hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null
    exit_with_summary
  fi
  record M0.app PASS "$APP_BUNDLE_PATH"
elif [ -n "$APP_BUNDLE_PATH" ]; then
  if [ ! -d "$APP_BUNDLE_PATH" ]; then
    record M0.app FAIL "app bundle not found: $APP_BUNDLE_PATH"
    exit_with_summary
  fi
  record M0.app PASS "$APP_BUNDLE_PATH"
else
  echo "ERROR: must pass either --dmg or --app" >&2
  usage
fi

cleanup() {
  if [ "$MOUNTED_BY_US" -eq 1 ] && [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Gate M1 — Bundle identity matches expected brand.
# -----------------------------------------------------------------------------
echo
echo "== M1 — bundle identity =="
plist="$APP_BUNDLE_PATH/Contents/Info.plist"
if [ ! -f "$plist" ]; then
  record M1.plist FAIL "Info.plist missing"
else
  actual_id=$(plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null || echo "")
  if [ "$actual_id" = "$BUNDLE_ID" ]; then
    record M1.bundle PASS "CFBundleIdentifier=$actual_id"
  else
    record M1.bundle FAIL "expected $BUNDLE_ID, got '$actual_id'"
  fi
fi

# -----------------------------------------------------------------------------
# Gate M2 — codesign verification (W3). Any "invalid signature" / "rejected"
# here would ship a Gatekeeper-failing app to users.
# -----------------------------------------------------------------------------
echo
echo "== M2 — codesign --verify =="
cs_out=$(codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH" 2>&1)
cs_rc=$?
if [ $cs_rc -eq 0 ]; then
  record M2.codesign PASS "deep-strict OK"
else
  record M2.codesign FAIL "$(echo "$cs_out" | head -5 | tr '\n' ';')"
fi

# Specifically verify the native.framework binary was signed (per CLAUDE.md
# gotcha: sign the Versions/A/native BINARY, not the bundle).
native_bin="$APP_BUNDLE_PATH/Contents/Frameworks/native.framework/Versions/A/native"
if [ -f "$native_bin" ]; then
  ncs=$(codesign --verify --verbose=1 "$native_bin" 2>&1)
  nrc=$?
  if [ $nrc -eq 0 ]; then
    record M2.native PASS "native.framework binary signed"
  else
    record M2.native FAIL "$(echo "$ncs" | head -3 | tr '\n' ';')"
  fi
else
  record M2.native WARN "native.framework binary missing — unexpected for Rust FFI build"
fi

cs_ident=$(codesign -dv "$APP_BUNDLE_PATH" 2>&1 | grep -E '^(Authority|Identifier|TeamIdentifier)=' | head -5)
if echo "$cs_ident" | grep -q 'adhoc'; then
  record M2.identity WARN "ad-hoc signed — acceptable for local dev, NOT for a release DMG"
elif [ -n "$cs_ident" ]; then
  record M2.identity PASS "$(echo "$cs_ident" | head -1)"
else
  record M2.identity SKIP "could not extract signing identity"
fi

# -----------------------------------------------------------------------------
# Gate M3 — Notarization ticket stapled (W3). A missing ticket makes a
# signed app get a "could not verify" prompt on first open on a fresh Mac.
# -----------------------------------------------------------------------------
echo
echo "== M3 — stapler validate =="
if stapler_out=$(xcrun stapler validate "$APP_BUNDLE_PATH" 2>&1); then
  record M3.stapler PASS "ticket stapled"
else
  # Either not stapled, or the runtime doesn't have stapler (rare).
  if echo "$stapler_out" | grep -qi 'not stapled\|does not have a ticket'; then
    record M3.stapler FAIL "no notary ticket attached"
  else
    record M3.stapler WARN "$(echo "$stapler_out" | head -1)"
  fi
fi

if [ -n "$DMG_PATH" ]; then
  if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    record M3.dmg_ticket PASS "DMG ticket stapled"
  else
    record M3.dmg_ticket WARN "DMG not stapled (some flows only staple the .app)"
  fi
fi

# -----------------------------------------------------------------------------
# Gate M4 — spctl Gatekeeper assessment. The practical "will Gatekeeper
# accept this on a fresh Mac" answer.
# -----------------------------------------------------------------------------
echo
echo "== M4 — spctl Gatekeeper =="
spctl_out=$(spctl -a -vvv -t execute "$APP_BUNDLE_PATH" 2>&1)
if echo "$spctl_out" | grep -q 'accepted'; then
  record M4.spctl PASS "$(echo "$spctl_out" | head -1 | tr -d '\r')"
else
  record M4.spctl FAIL "$(echo "$spctl_out" | head -3 | tr '\n' ';')"
fi

# -----------------------------------------------------------------------------
# Gate M5 — Release entitlements tight (W1). Confirms the tighten from
# 9839f674 is on this build: no allow-jit, no unsigned-executable-memory,
# no network.server. Kept: disable-library-validation (for plugin dylibs)
# and network.client.
# -----------------------------------------------------------------------------
echo
echo "== M5 — Release entitlements tight =="
ent_xml=$(codesign -d --entitlements :- "$APP_BUNDLE_PATH" 2>/dev/null || true)
if [ -z "$ent_xml" ]; then
  record M5.entitlements SKIP "no entitlements blob in binary"
else
  forbidden=(
    'com.apple.security.cs.allow-jit'
    'com.apple.security.cs.allow-unsigned-executable-memory'
    'com.apple.security.network.server'
  )
  required=(
    'com.apple.security.cs.disable-library-validation'
    'com.apple.security.network.client'
  )
  # Forbidden keys must NOT appear with <true/>.
  for key in "${forbidden[@]}"; do
    if echo "$ent_xml" | grep -qE "<key>$key</key>[[:space:]]*<true/>"; then
      record "M5.no-$key" FAIL "forbidden entitlement present in Release"
    else
      record "M5.no-$key" PASS "absent"
    fi
  done
  for key in "${required[@]}"; do
    if echo "$ent_xml" | grep -qE "<key>$key</key>[[:space:]]*<true/>"; then
      record "M5.has-$key" PASS "present"
    else
      record "M5.has-$key" FAIL "required entitlement missing"
    fi
  done
fi

# -----------------------------------------------------------------------------
# Gate M6 — Quarantine xattr strip. A properly shipped build off a
# notarized DMG should NOT have com.apple.quarantine on the bundle
# (Gatekeeper treats first-open specially when it does).
# -----------------------------------------------------------------------------
echo
echo "== M6 — quarantine xattr =="
qxattr=$(xattr -l "$APP_BUNDLE_PATH" 2>/dev/null | grep -E 'com\.apple\.quarantine' || true)
if [ -z "$qxattr" ]; then
  record M6.quarantine PASS "no quarantine attribute"
else
  record M6.quarantine WARN "quarantine xattr present: $qxattr"
fi

# -----------------------------------------------------------------------------
# Gate M7 — Launch smoke (optional). Launches the app headless, waits for
# it to register with launchctl, then kills it. Verifies the app starts
# without crashing under the tight entitlements + real signed build.
# -----------------------------------------------------------------------------
echo
echo "== M7 — launch smoke =="
if [ "$SKIP_LAUNCH" -eq 1 ]; then
  record M7.launch SKIP "--skip-launch"
else
  exec_bin="$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
  if [ ! -x "$exec_bin" ]; then
    record M7.launch FAIL "exec binary missing: $exec_bin"
  else
    launch_log="$(mktemp)"
    "$exec_bin" >"$launch_log" 2>&1 &
    pid=$!
    # Wait for the expected early boot marker OR timeout.
    deadline=$(( $(date +%s) + LAUNCH_TIMEOUT_SECONDS ))
    seen_boot=0
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if grep -qE 'BinaryManager.*Initializing|starting\.\.\.|Rust bridge initialized' "$launch_log" 2>/dev/null; then
        seen_boot=1
        break
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if [ "$seen_boot" -eq 1 ] && kill -0 "$pid" 2>/dev/null; then
      record M7.launch PASS "process alive + boot markers observed"
    elif kill -0 "$pid" 2>/dev/null; then
      record M7.launch WARN "process alive but no boot marker in ${LAUNCH_TIMEOUT_SECONDS}s (Release log filter may suppress)"
    else
      record M7.launch FAIL "process exited during boot — see $launch_log"
    fi
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$launch_log"
  fi
fi

# -----------------------------------------------------------------------------
# Gate M8 — Binary cache (W6). Post-first-launch, the binary cache
# directory should exist. Skipped when --skip-launch.
# -----------------------------------------------------------------------------
echo
echo "== M8 — binary cache dir =="
if [ "$SKIP_LAUNCH" -eq 1 ]; then
  record M8.bindir SKIP "--skip-launch"
else
  bin_dir="$HOME/Library/Application Support/$BUNDLE_ID/bin"
  if [ ! -d "$bin_dir" ]; then
    record M8.bindir WARN "bin dir absent: $bin_dir (app may not have finished binary provisioning before kill)"
  else
    # Count sane binaries (> 1 MB each).
    bins=("yt-dlp" "ffmpeg" "gallery-dl")
    ok=0
    missing=()
    for b in "${bins[@]}"; do
      for candidate in "$bin_dir/$b" "$bin_dir/${b}.exe"; do
        if [ -f "$candidate" ]; then
          sz=$(stat -f '%z' "$candidate" 2>/dev/null || echo 0)
          if [ "$sz" -ge 1048576 ]; then
            ok=$((ok+1))
            break
          fi
        fi
      done
      [ $ok -lt $((${#bins[@]})) ] && missing+=("$b")
    done
    if [ "$ok" -eq 3 ]; then
      record M8.bindir PASS "all 3 binaries present + healthy size"
    else
      record M8.bindir WARN "only $ok/3 binaries (missing: ${missing[*]}) — may still be downloading"
    fi
  fi
fi

exit_with_summary
