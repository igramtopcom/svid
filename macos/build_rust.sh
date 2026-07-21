#!/bin/bash
set -e

echo "Building Rust library for macOS..."

# Get project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
NATIVE_DIR="$PROJECT_ROOT/native"

# Determine build mode
if [ "$CONFIGURATION" = "Release" ]; then
    PROFILE="release"
    PROFILE_FLAG="--release"
    # Sentry telemetry for Rust panics + anyhow errors. Release builds get
    # the full crash-reporting stack by default. Override by exporting
    # RUST_TELEMETRY=0 for diagnostic builds; CI release pipelines must
    # leave the default to maintain crash visibility.
    if [ -z "${RUST_TELEMETRY:-}" ] || [ "$RUST_TELEMETRY" = "1" ]; then
        FEATURE_FLAGS="--features telemetry"
    else
        FEATURE_FLAGS=""
        echo "WARNING: Rust telemetry disabled by RUST_TELEMETRY=$RUST_TELEMETRY"
    fi
else
    PROFILE="debug"
    PROFILE_FLAG=""
    # Debug builds skip the sentry crate by default to keep `cargo check`
    # fast. Set RUST_TELEMETRY=1 to opt in (e.g. to test panic reporting
    # locally before shipping).
    if [ "${RUST_TELEMETRY:-0}" = "1" ]; then
        FEATURE_FLAGS="--features telemetry"
    else
        FEATURE_FLAGS=""
    fi
fi

echo "Configuration: $PROFILE${FEATURE_FLAGS:+ (with $FEATURE_FLAGS)}"

# Navigate to Rust directory
cd "$NATIVE_DIR"

# Determine target and build
if [ "$RUST_UNIVERSAL" = "1" ]; then
    # CI: universal binary already built by workflow, just use it
    echo "Using pre-built universal binary"
    RUST_LIB="$NATIVE_DIR/target/universal-apple-darwin/$PROFILE/libnative.dylib"
else
    # Local dev: build for current architecture only
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        TARGET="aarch64-apple-darwin"
    else
        TARGET="x86_64-apple-darwin"
    fi
    echo "Building for: $TARGET"
    cargo build $PROFILE_FLAG --target "$TARGET" $FEATURE_FLAGS
    RUST_LIB="$NATIVE_DIR/target/$TARGET/$PROFILE/libnative.dylib"
fi
FRAMEWORK_DIR="$SCRIPT_DIR/native.framework"

# Clean and recreate framework from scratch
echo "Creating framework structure..."
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Versions/A/Resources"

# Copy dylib
cp "$RUST_LIB" "$FRAMEWORK_DIR/Versions/A/native"
chmod +x "$FRAMEWORK_DIR/Versions/A/native"

# Create Info.plist
cat > "$FRAMEWORK_DIR/Versions/A/Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>native</string>
	<key>CFBundleIdentifier</key>
	<string>com.svid.app.native</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>native</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>10.15</string>
</dict>
</plist>
EOF

# Create framework symlinks
cd "$FRAMEWORK_DIR"
ln -sf Versions/A/native native
ln -sf Versions/A/Resources Resources
ln -sf A Versions/Current

# Update install name
install_name_tool -id "@rpath/native.framework/Versions/A/native" "$FRAMEWORK_DIR/Versions/A/native"

# Sign the binary only (not the framework bundle) to avoid codesign creating rogue symlinks
codesign --force --sign - "$FRAMEWORK_DIR/Versions/A/native"

echo "✓ Framework created at: $FRAMEWORK_DIR"

# Verify no rogue symlinks
if [ -L "$FRAMEWORK_DIR/Versions/A/A" ] || [ -L "$FRAMEWORK_DIR/Versions/A/Resources/Resources" ]; then
    echo "ERROR: Rogue symlinks detected in framework!"
    exit 1
fi

# If running from Xcode, also copy to app bundle
if [ -n "$BUILT_PRODUCTS_DIR" ]; then
    DEST_FRAMEWORK="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Frameworks/native.framework"
    echo "Copying to app bundle: $DEST_FRAMEWORK"

    # Remove old framework if exists
    rm -rf "$DEST_FRAMEWORK"

    # Copy framework
    cp -R "$FRAMEWORK_DIR" "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Frameworks/"

    echo "✓ Framework copied to app bundle"
fi

echo "✓ Rust library built successfully"
