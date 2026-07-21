#!/usr/bin/env bash

set -euo pipefail

BRAND="${1:-ssvid}"
DURATION_SECONDS="${2:-12}"

case "$BRAND" in
  ssvid|vidcombo) ;;
  *)
    echo "ERROR: unknown brand '$BRAND'. Use 'ssvid' or 'vidcombo'." >&2
    exit 1
    ;;
esac

if [[ ! "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$DURATION_SECONDS" -lt 5 ]]; then
  echo "ERROR: duration must be an integer >= 5 seconds." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APPINFO="$ROOT_DIR/macos/Runner/Configs/AppInfo.xcconfig"
LOCK_DIR="/tmp/snakeloader_startup_profile.lock"

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

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: startup profiling is already running. Wait for the current run to finish before starting another." >&2
  exit 1
fi

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! git diff --quiet -- "${BRAND_PATHS[@]}" || ! git diff --cached --quiet -- "${BRAND_PATHS[@]}"; then
  echo "ERROR: brand-managed files have local changes. Commit or stash them before profiling." >&2
  exit 1
fi

current_brand="$(
  sed -n 's/^#include "brands\/\(.*\)\.xcconfig"/\1/p' "$APPINFO" | head -n 1
)"
if [[ -z "$current_brand" ]]; then
  current_brand="ssvid"
fi

cleanup() {
  if [[ "$current_brand" != "$BRAND" ]]; then
    "$SCRIPT_DIR/set_brand.sh" "$current_brand" >/dev/null
  fi
  release_lock
}
trap cleanup EXIT

if [[ "$current_brand" != "$BRAND" ]]; then
  "$SCRIPT_DIR/set_brand.sh" "$BRAND"
fi

if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

echo "==> Profiling macOS cold start for brand=$BRAND duration=${DURATION_SECONDS}s"
echo
echo "[1/3] Building Rust framework..."
CONFIGURATION=Debug bash "$ROOT_DIR/macos/build_rust.sh"
echo
echo "[2/3] Building macOS debug app..."
"${FLUTTER[@]}" build macos --debug --dart-define=BRAND="$BRAND" --no-pub
echo
echo "[3/3] Launching app and collecting startup log..."

APP_BINARY="$ROOT_DIR/build/macos/Build/Products/Debug/$BRAND.app/Contents/MacOS/$BRAND"
LOG_FILE="/tmp/${BRAND}_startup.log"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "ERROR: app binary not found at $APP_BINARY" >&2
  exit 1
fi

HOME=/tmp "$APP_BINARY" >"$LOG_FILE" 2>&1 &
pid=$!
sleep "$DURATION_SECONDS"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

echo
echo "Startup timeline:"
rg '\[Startup\]' "$LOG_FILE" || echo "No startup profiler lines found in $LOG_FILE"
echo
echo "Full log: $LOG_FILE"
