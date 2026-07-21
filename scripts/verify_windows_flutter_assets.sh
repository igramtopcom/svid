#!/usr/bin/env bash
# Verifies that a Windows Flutter runner bundle contains runtime assets that
# the app loads by explicit path. This catches packaging artifacts where source
# assets exist in the repo but are missing from data/flutter_assets at runtime.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <windows-bundle-root>" >&2
  exit 2
fi

ROOT="$1"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: bundle root not found: $ROOT" >&2
  exit 1
fi

ASSET_ROOTS=()
while IFS= read -r asset_root; do
  ASSET_ROOTS+=("$asset_root")
done < <(find "$ROOT" -type d -path "*/data/flutter_assets" 2>/dev/null | sort)

if [[ ${#ASSET_ROOTS[@]} -eq 0 ]]; then
  echo "ERROR: no data/flutter_assets directory found under $ROOT" >&2
  exit 1
fi

REQUIRED_ASSETS=(
  "assets/icons/platforms/facebook.svg"
  "assets/icons/platforms/instagram.svg"
  "assets/icons/platforms/other.svg"
  "assets/icons/platforms/pinterest.svg"
  "assets/icons/platforms/reddit.svg"
  "assets/icons/platforms/tiktok.svg"
  "assets/icons/platforms/x.svg"
  "assets/icons/platforms/youtube.svg"
)

errors=0

for asset_root in "${ASSET_ROOTS[@]}"; do
  echo "Flutter asset bundle: $asset_root"
  for asset in "${REQUIRED_ASSETS[@]}"; do
    if [[ ! -s "$asset_root/$asset" ]]; then
      echo "  FAIL: missing or empty $asset" >&2
      errors=$((errors + 1))
    else
      echo "  OK   $asset"
    fi
  done
done

if (( errors > 0 )); then
  echo "verify_windows_flutter_assets: $errors missing asset(s)" >&2
  exit 1
fi

echo "verify_windows_flutter_assets: OK (${#ASSET_ROOTS[@]} bundle(s) checked)"
