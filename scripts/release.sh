#!/bin/bash
# =============================================================================
# SSvid Release Script — Local Build + Package
# Usage: bash scripts/release.sh [platform] [--skip-test]
#   platform: macos | windows | linux | all (default: current platform)
#   --skip-test: Skip running tests (for iteration speed)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
DIST_DIR="$PROJECT_ROOT/dist"

# Parse version from pubspec.yaml
VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//')
BUILD_NUMBER=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed 's/.*+//')

echo "================================================"
echo "  SSvid Release Pipeline v${VERSION}+${BUILD_NUMBER}"
echo "================================================"

# Parse args
PLATFORM="${1:-auto}"
SKIP_TEST=false
for arg in "$@"; do
    case $arg in
        --skip-test) SKIP_TEST=true ;;
    esac
done

# Auto-detect platform
if [ "$PLATFORM" = "auto" ]; then
    case "$(uname -s)" in
        Darwin*) PLATFORM="macos" ;;
        Linux*)  PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *) echo "ERROR: Unknown platform"; exit 1 ;;
    esac
fi

echo "Platform: $PLATFORM"
echo "Version:  $VERSION+$BUILD_NUMBER"
echo ""

# Create dist directory
mkdir -p "$DIST_DIR"

# ===== Step 1: Dependencies =====
echo "[1/6] Installing dependencies..."
cd "$PROJECT_ROOT"
flutter pub get

# ===== Step 2: Code generation =====
echo "[2/6] Generating code..."
dart run build_runner build --delete-conflicting-outputs

# ===== Step 3: Analyze =====
echo "[3/6] Analyzing..."
flutter analyze --no-fatal-infos

# ===== Step 4: Test =====
if [ "$SKIP_TEST" = false ]; then
    echo "[4/6] Running tests..."
    flutter test --reporter compact
    echo "  Tests passed."
else
    echo "[4/6] Skipping tests (--skip-test)"
fi

# ===== Step 5: Build =====
echo "[5/6] Building $PLATFORM release..."

case "$PLATFORM" in
    macos)
        # Build Rust
        CONFIGURATION=Release bash macos/build_rust.sh
        # Build Flutter
        flutter build macos --release
        echo "  Built: build/macos/Build/Products/Release/ssvid.app"
        ;;
    linux)
        # Build Rust
        bash linux/build_rust.sh release
        # Build Flutter
        flutter build linux --release
        echo "  Built: build/linux/x64/release/bundle/"
        ;;
    windows)
        echo "  Use scripts\\release.bat on Windows"
        exit 1
        ;;
esac

# ===== Step 6: Package =====
echo "[6/6] Packaging..."

case "$PLATFORM" in
    macos)
        bash "$SCRIPT_DIR/package_macos.sh"
        ;;
    linux)
        bash "$SCRIPT_DIR/package_linux.sh"
        ;;
esac

# ===== Summary =====
echo ""
echo "================================================"
echo "  Release artifacts in: dist/"
echo "================================================"
ls -lh "$DIST_DIR"/SSvid-* 2>/dev/null || echo "  (no artifacts yet)"
echo ""
echo "Done."
