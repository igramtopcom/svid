#!/usr/bin/env bash
# dev.sh — Unified dev runner for SSvid + VidCombo (multi-brand desktop)
#
# Replaces the 4-step manual incantation:
#   scripts/set_brand.sh <brand> && \
#   CONFIGURATION=<mode> bash macos/build_rust.sh && \
#   [fvm flutter clean && fvm flutter build macos --release ...] || \
#   fvm flutter run -d macos --dart-define=BRAND=<brand>
#
# Usage:
#   scripts/dev.sh                     # ssvid debug (default)
#   scripts/dev.sh ssvid               # ssvid debug
#   scripts/dev.sh vidcombo            # vidcombo debug
#   scripts/dev.sh ssvid release       # ssvid release build + verify
#   scripts/dev.sh vidcombo release    # vidcombo release build + verify
#
# Notes:
#   - Hot restart is BROKEN for native plugins (media_kit). Use full restart.
#   - SENTRY_DSN may be set in env; otherwise crash reporting is off in dev.

set -euo pipefail

BRAND="${1:-ssvid}"
MODE="${2:-debug}"

# Validate brand
case "$BRAND" in
  ssvid|vidcombo) ;;
  *)
    echo "ERROR: unknown brand '$BRAND'. Use 'ssvid' or 'vidcombo'." >&2
    exit 1
    ;;
esac

# Validate mode
case "$MODE" in
  debug|release) ;;
  *)
    echo "ERROR: unknown mode '$MODE'. Use 'debug' or 'release'." >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Resolve flutter command (prefer fvm if available)
if command -v fvm &>/dev/null; then
  FLUTTER="fvm flutter"
else
  FLUTTER="flutter"
fi

# Optional Sentry DSN passthrough
SENTRY_ARG=()
if [[ -n "${SENTRY_DSN:-}" ]]; then
  SENTRY_ARG+=(--dart-define=SENTRY_DSN="$SENTRY_DSN")
fi

# Local dev builds should identify themselves as the current production (or
# release-candidate) version for the active brand. CI/release workflows rewrite
# pubspec.yaml directly; dev.sh uses a dart-define so switching brands does not
# dirty pubspec on every run.
case "$BRAND" in
  ssvid) DEFAULT_APP_VERSION="${SSVID_DEV_VERSION:-1.4.0}" ;;
  vidcombo) DEFAULT_APP_VERSION="${VIDCOMBO_DEV_VERSION:-1.7.1}" ;;
esac
APP_VERSION="${APP_VERSION:-$DEFAULT_APP_VERSION}"
VERSION_ARG=(--dart-define=APP_VERSION="$APP_VERSION")

echo "==> dev.sh: brand=$BRAND mode=$MODE flutter=$FLUTTER app_version=$APP_VERSION"
echo

# Step 1 — Switch brand config (icons, xcconfig, CMakeLists, brand_config.h)
echo "[1/3] Switching brand to $BRAND..."
bash "$SCRIPT_DIR/set_brand.sh" "$BRAND"
echo

# Step 2 — Build native Rust dylib for current arch
echo "[2/3] Building Rust native library ($MODE)..."
if [[ "$MODE" == "release" ]]; then
  CONFIGURATION=Release bash "$PROJECT_DIR/macos/build_rust.sh"
else
  CONFIGURATION=Debug bash "$PROJECT_DIR/macos/build_rust.sh"
fi
echo

# Step 3 — Run or build Flutter
if [[ "$MODE" == "release" ]]; then
  echo "[3/3] Building Flutter macOS release for $BRAND..."
  $FLUTTER clean
  $FLUTTER build macos --release \
    --dart-define=BRAND="$BRAND" \
    "${VERSION_ARG[@]}" \
    ${SENTRY_ARG[@]+"${SENTRY_ARG[@]}"}

  # Verify native.framework binary exists (CI gatekeeper for FFI integrity)
  NATIVE_BIN="build/macos/Build/Products/Release/${BRAND}.app/Contents/Frameworks/native.framework/native"
  if [[ -f "$NATIVE_BIN" ]]; then
    echo
    echo "OK  native.framework binary present: $NATIVE_BIN"
    echo "    size: $(du -h "$NATIVE_BIN" | cut -f1)"
  else
    echo
    echo "ERROR: native.framework binary missing at $NATIVE_BIN" >&2
    exit 1
  fi

  echo
  echo "==> Release build ready. Package with:"
  echo "    bash scripts/package_macos.sh $BRAND"
else
  echo "[3/3] Running $BRAND on macOS (debug)..."
  echo "    Hot reload OK. Hot restart broken for media_kit — use full restart (q + re-run)."
  echo
  exec $FLUTTER run -d macos \
    --dart-define=BRAND="$BRAND" \
    "${VERSION_ARG[@]}" \
    ${SENTRY_ARG[@]+"${SENTRY_ARG[@]}"}
fi
