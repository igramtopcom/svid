#!/usr/bin/env bash
# verify_brand_assets.sh — Standalone pre-build gate for brand assets.
#
# Catches the class of bug that produced VidCombo Bug 2 (notification logo
# was wrong because app_icon_1024.png was actually 512×512 — iconutil silently
# dropped it and macOS fell back to a generic icon at retina sizes).
#
# Run manually before push:
#   bash scripts/verify_brand_assets.sh
#
# Or per-brand:
#   bash scripts/verify_brand_assets.sh svid
#
# Exits 1 on any failure. Safe to run anywhere — only reads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BRANDS_DIR="$ROOT_DIR/assets/brands"

# Brands to check (default: all)
if [[ $# -gt 0 ]]; then
  BRANDS=("$@")
else
  BRANDS=(svid vidcombo)
fi

# Required files per brand
REQUIRED_FILES=(
  "app_icon.png"
  "app_icon.ico"
  "logo.png"
  "tray_icon_macos.png"
  "tray_icon_linux.png"
  "tray_icon_windows.ico"
)

# Minimum dimensions: app_icon must be ≥ 1024² (Apple Store + iconutil safety)
MIN_APP_ICON_SIZE=1024

errors=0

check_dim() {
  local file="$1"
  local min="$2"
  if ! command -v sips &>/dev/null; then
    return 0  # Skip dimension check on non-macOS hosts
  fi
  local w h
  w=$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  if [[ -z "$w" || -z "$h" ]]; then
    echo "  FAIL: cannot read dimensions of $file" >&2
    return 1
  fi
  if (( w < min || h < min )); then
    echo "  FAIL: $file is ${w}x${h}, need ≥ ${min}x${min}" >&2
    return 1
  fi
  echo "  OK   $(basename "$file") ${w}x${h}"
  return 0
}

check_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "  FAIL: missing $file" >&2
    return 1
  fi
  return 0
}

check_ico_sizes() {
  local file="$1"
  shift

  if ! command -v od &>/dev/null; then
    echo "  FAIL: od not found, cannot check ICO sizes for $(basename "$file")" >&2
    return 1
  fi

  local header=()
  header=($(od -An -t u1 -N 6 "$file"))
  if [[ ${#header[@]} -ne 6 ]]; then
    echo "  FAIL: cannot read ICO header for $file" >&2
    return 1
  fi

  if [[ "${header[0]}" -ne 0 || "${header[1]}" -ne 0 ||
        "${header[2]}" -ne 1 || "${header[3]}" -ne 0 ]]; then
    echo "  FAIL: $file is not a Windows ICO file" >&2
    return 1
  fi

  local count=$((header[4] + header[5] * 256))
  if (( count <= 0 )); then
    echo "  FAIL: $file has no icon entries" >&2
    return 1
  fi

  local entries=()
  entries=($(od -An -t u1 -j 6 -N $((count * 16)) "$file"))
  if [[ ${#entries[@]} -lt $((count * 16)) ]]; then
    echo "  FAIL: cannot read ICO directory entries for $file" >&2
    return 1
  fi

  local found=" "
  local i width height
  for ((i = 0; i < count; i++)); do
    width="${entries[$((i * 16))]}"
    height="${entries[$((i * 16 + 1))]}"
    [[ "$width" -eq 0 ]] && width=256
    [[ "$height" -eq 0 ]] && height=256
    if [[ "$width" -ne "$height" ]]; then
      echo "  FAIL: $file has non-square ICO entry ${width}x${height}" >&2
      return 1
    fi
    found+="$width "
  done

  local missing=0
  local required
  for required in "$@"; do
    if [[ "$found" != *" $required "* ]]; then
      echo "  FAIL: $file missing ${required}x${required} entry" >&2
      missing=1
    fi
  done
  if (( missing > 0 )); then
    return 1
  fi

  echo "  OK   $(basename "$file") ICO sizes:$found"
  return 0
}

for brand in "${BRANDS[@]}"; do
  brand_dir="$BRANDS_DIR/$brand"
  echo "Brand: $brand"

  if [[ ! -d "$brand_dir" ]]; then
    echo "  FAIL: brand directory not found: $brand_dir" >&2
    errors=$((errors + 1))
    continue
  fi

  # Required files exist
  for f in "${REQUIRED_FILES[@]}"; do
    if ! check_exists "$brand_dir/$f"; then
      errors=$((errors + 1))
    fi
  done

  # app_icon.png must be ≥1024² to survive iconutil pipeline
  if [[ -f "$brand_dir/app_icon.png" ]]; then
    if ! check_dim "$brand_dir/app_icon.png" "$MIN_APP_ICON_SIZE"; then
      errors=$((errors + 1))
    fi
  fi

  # Website/admin logo surfaces use the same source logo. Require at least
  # 512² so favicons and dashboard avatars do not upscale from a tiny raster.
  if [[ -f "$brand_dir/logo.png" ]]; then
    if ! check_dim "$brand_dir/logo.png" 512; then
      errors=$((errors + 1))
    fi
  fi

  # Linux tray/icon surfaces need a real raster with enough pixels for HiDPI
  # panels. The app icon check above covers platform launchers; this catches
  # accidental tiny tray exports.
  if [[ -f "$brand_dir/tray_icon_linux.png" ]]; then
    if ! check_dim "$brand_dir/tray_icon_linux.png" 64; then
      errors=$((errors + 1))
    fi
  fi

  if [[ -f "$brand_dir/tray_icon_macos.png" ]]; then
    if ! check_dim "$brand_dir/tray_icon_macos.png" 16; then
      errors=$((errors + 1))
    fi
  fi

  # Windows taskbar/start-menu shell uses different icon sizes depending on DPI,
  # pinned shortcut state, and taskbar mode. Require the full standard set so a
  # future brand asset cannot regress to a generic placeholder on some machines.
  if [[ -f "$brand_dir/app_icon.ico" ]]; then
    if ! check_ico_sizes "$brand_dir/app_icon.ico" 16 24 32 48 64 128 256; then
      errors=$((errors + 1))
    fi
  fi

  # Windows tray icons are consumed separately from the app icon. Require the
  # standard tray/taskbar small-size set so the shell never falls back to a
  # blurry nearest-neighbour scale.
  if [[ -f "$brand_dir/tray_icon_windows.ico" ]]; then
    if ! check_ico_sizes "$brand_dir/tray_icon_windows.ico" 16 24 32 48 64; then
      errors=$((errors + 1))
    fi
  fi

  echo
done

if (( errors > 0 )); then
  echo "verify_brand_assets: $errors error(s)" >&2
  exit 1
fi

echo "verify_brand_assets: OK (${#BRANDS[@]} brand(s) checked)"
