#!/usr/bin/env bash

set -euo pipefail

STARTUP_DURATION_SECONDS="${1:-5}"

if [[ ! "$STARTUP_DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$STARTUP_DURATION_SECONDS" -lt 5 ]]; then
  echo "ERROR: startup duration must be an integer >= 5 seconds." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APPINFO="$ROOT_DIR/macos/Runner/Configs/AppInfo.xcconfig"

BRAND_PATHS=(
  "LICENSE"
  "linux/CMakeLists.txt"
  "macos/Runner/Assets.xcassets/AppIcon.appiconset"
  "macos/Runner/Configs/AppInfo.xcconfig"
  "windows/CMakeLists.txt"
  "windows/runner/brand_config.h"
  "windows/runner/resources/app_icon.ico"
)

cd "$ROOT_DIR"

if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

baseline_brand="$(
  sed -n 's/^#include "brands\/\(.*\)\.xcconfig"/\1/p' "$APPINFO" | head -n 1
)"
if [[ -z "$baseline_brand" ]]; then
  baseline_brand="ssvid"
fi

REPORT_FILE="/tmp/production_readiness_$(date +%Y%m%d_%H%M%S).log"

log_section() {
  echo
  echo "================================================"
  echo "$1"
  echo "================================================"
}

summarize_brand_log() {
  local brand="$1"
  local log_file="/tmp/${brand}_startup.log"

  if [[ ! -f "$log_file" ]]; then
    echo "[$brand] startup log missing: $log_file"
    return 1
  fi

  local first_frame
  local post_frame
  local background
  first_frame="$(rg '\[Startup\].*first_frame:' "$log_file" | tail -n 1 || true)"
  post_frame="$(rg '\[Startup\].*post_frame:' "$log_file" | tail -n 1 || true)"
  background="$(rg '\[Startup\].*background:' "$log_file" | tail -n 1 || true)"

  echo "[$brand] first frame:"
  echo "${first_frame:-  missing}"
  echo "[$brand] post frame:"
  echo "${post_frame:-  missing}"
  echo "[$brand] background:"
  echo "${background:-  missing}"
}

{
  echo "Production Readiness Wave"
  echo "Repo: $ROOT_DIR"
  echo "Baseline brand: $baseline_brand"
  echo "Startup duration: ${STARTUP_DURATION_SECONDS}s"
} | tee "$REPORT_FILE"

log_section "[1/6] Flutter Analyze"
"${FLUTTER[@]}" analyze --no-pub | tee -a "$REPORT_FILE"

log_section "[2/6] Flutter Test"
"${FLUTTER[@]}" test | tee -a "$REPORT_FILE"

log_section "[3/6] Runtime Smoke"
bash "$SCRIPT_DIR/run_runtime_smoke_tests.sh" | tee -a "$REPORT_FILE"

log_section "[4/6] SSvid Startup Profile"
bash "$SCRIPT_DIR/profile_startup_macos.sh" ssvid "$STARTUP_DURATION_SECONDS" | tee -a "$REPORT_FILE"

log_section "[5/6] VidCombo Startup Profile"
bash "$SCRIPT_DIR/profile_startup_macos.sh" vidcombo "$STARTUP_DURATION_SECONDS" | tee -a "$REPORT_FILE"

log_section "[6/6] Drift Check"
if ! git diff --quiet -- "${BRAND_PATHS[@]}" || ! git diff --cached --quiet -- "${BRAND_PATHS[@]}"; then
  echo "ERROR: brand-managed files drifted during verification." | tee -a "$REPORT_FILE"
  git status --short | tee -a "$REPORT_FILE"
  exit 1
fi

{
  echo "Baseline brand restored: $baseline_brand"
  echo
  echo "Startup summary"
  summarize_brand_log ssvid
  summarize_brand_log vidcombo
  echo
  echo "Report file: $REPORT_FILE"
} | tee -a "$REPORT_FILE"
