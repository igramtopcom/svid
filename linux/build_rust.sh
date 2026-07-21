#!/bin/bash
set -e

echo "Building Rust library for Linux..."

# Get project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
NATIVE_DIR="$PROJECT_ROOT/native"

# Determine build mode + Sentry telemetry feature.
# Release builds enable telemetry by default (override with RUST_TELEMETRY=0
# for diagnostic builds). Debug builds skip telemetry to keep `cargo check`
# fast (override with RUST_TELEMETRY=1 to test panic reporting locally).
if [ "$1" = "release" ]; then
    PROFILE="release"
    PROFILE_FLAG="--release"
    if [ -z "${RUST_TELEMETRY:-}" ] || [ "$RUST_TELEMETRY" = "1" ]; then
        FEATURE_FLAGS="--features telemetry"
    else
        FEATURE_FLAGS=""
        echo "WARNING: Rust telemetry disabled by RUST_TELEMETRY=$RUST_TELEMETRY"
    fi
else
    PROFILE="debug"
    PROFILE_FLAG=""
    if [ "${RUST_TELEMETRY:-0}" = "1" ]; then
        FEATURE_FLAGS="--features telemetry"
    else
        FEATURE_FLAGS=""
    fi
fi

echo "Configuration: $PROFILE${FEATURE_FLAGS:+ (with $FEATURE_FLAGS)}"

# Navigate to Rust directory
cd "$NATIVE_DIR"

# Build for current architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    TARGET="aarch64-unknown-linux-gnu"
else
    TARGET="x86_64-unknown-linux-gnu"
fi

echo "Building for: $TARGET"

# Build
cargo build $PROFILE_FLAG --target "$TARGET" $FEATURE_FLAGS

# Copy .so to linux directory
RUST_LIB="$NATIVE_DIR/target/$TARGET/$PROFILE/libnative.so"
DEST="$SCRIPT_DIR/libnative.so"

if [ -f "$RUST_LIB" ]; then
    cp "$RUST_LIB" "$DEST"
    echo "✓ libnative.so copied to $DEST"
else
    echo "ERROR: libnative.so not found at $RUST_LIB"
    exit 1
fi

echo "✓ Rust library built successfully"
