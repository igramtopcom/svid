#!/bin/bash
# =============================================================================
# Multi-Brand macOS Packaging Script — Creates .dmg from Flutter .app bundle
# Usage: bash scripts/package_macos.sh [svid|vidcombo]
# Default: svid
# =============================================================================
set -e

BRAND="${1:-svid}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
DIST_DIR="$PROJECT_ROOT/dist"

# Brand configuration
case "$BRAND" in
  svid)
    APP_NAME="svid"
    DISPLAY_NAME="Svid"
    ;;
  vidcombo)
    APP_NAME="vidcombo"
    DISPLAY_NAME="VidCombo"
    ;;
  *)
    echo "Error: Unknown brand '$BRAND'. Use 'svid' or 'vidcombo'."
    exit 1
    ;;
esac

# Parse version from pubspec.yaml
VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//')

APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${DISPLAY_NAME}-${VERSION}-macos-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg-staging"

echo "Packaging macOS DMG: $DMG_NAME (brand: $BRAND)"

# Verify .app exists
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found. Run 'fvm flutter build macos --release --dart-define=BRAND=$BRAND' first."
    exit 1
fi

mkdir -p "$DIST_DIR"

# Clean previous staging
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"

# Create staging directory with app + Applications symlink
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Fix AppIcon.icns — Xcode generates incomplete .icns (missing 512/1024 sizes)
# which causes macOS to show the default app icon in Dock/Launchpad.
#
# CRITICAL: iconutil silently DROPS files whose actual dimensions don't match
# the filename's declared size. Past bug: VidCombo source was 512x512 but
# `cp` was named app_icon_1024.png → iconutil produced an icns with no 1024
# entry → macOS used the system fallback at retina sizes (the "leaf+heart"
# wrong icon). We now verify dimensions BEFORE and inspect the resulting icns
# AFTER, failing loud on mismatch.
ICON_SRC="$PROJECT_ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICNS_DEST="$STAGING_DIR/${APP_NAME}.app/Contents/Resources/AppIcon.icns"
if [ -d "$ICON_SRC" ]; then
    echo "  Regenerating AppIcon.icns with all sizes..."
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # Mapping: ICON_SRC filename → iconset entry name → expected width
    declare -a ICONSET_MAP=(
      "app_icon_16.png:icon_16x16.png:16"
      "app_icon_32.png:icon_16x16@2x.png:32"
      "app_icon_32.png:icon_32x32.png:32"
      "app_icon_64.png:icon_32x32@2x.png:64"
      "app_icon_128.png:icon_128x128.png:128"
      "app_icon_256.png:icon_128x128@2x.png:256"
      "app_icon_256.png:icon_256x256.png:256"
      "app_icon_512.png:icon_256x256@2x.png:512"
      "app_icon_512.png:icon_512x512.png:512"
      "app_icon_1024.png:icon_512x512@2x.png:1024"
    )

    for entry in "${ICONSET_MAP[@]}"; do
      IFS=':' read -r src_name dest_name expected <<< "$entry"
      src="$ICON_SRC/$src_name"
      dest="$ICONSET_DIR/$dest_name"
      if [ ! -f "$src" ]; then
        echo "  ERROR: missing source $src" >&2
        exit 1
      fi
      actual=$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/ {print $2}')
      if [ "$actual" != "$expected" ]; then
        echo "  ERROR: $src is ${actual}px wide, expected ${expected}px." >&2
        echo "         Run scripts/set_brand.sh $BRAND to regenerate." >&2
        exit 1
      fi
      cp "$src" "$dest"
    done

    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_DEST"

    # Round-trip verify: convert .icns back to iconset and confirm 10 entries.
    # iconutil silently drops mismatched files, so the final count is the only
    # honest signal of completeness.
    VERIFY_DIR="$DIST_DIR/AppIcon.verify.iconset"
    rm -rf "$VERIFY_DIR"
    iconutil -c iconset "$ICNS_DEST" -o "$VERIFY_DIR" 2>/dev/null || {
      echo "  ERROR: iconutil could not round-trip $ICNS_DEST" >&2
      exit 1
    }
    actual_entries=$(ls -1 "$VERIFY_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
    if [ "$actual_entries" != "10" ]; then
      echo "  ERROR: AppIcon.icns has $actual_entries entries, expected 10." >&2
      echo "         iconutil dropped one or more files. Iconset contents:" >&2
      ls -la "$VERIFY_DIR" >&2
      exit 1
    fi
    rm -rf "$VERIFY_DIR" "$ICONSET_DIR"
    echo "  AppIcon.icns regenerated ($(du -h "$ICNS_DEST" | cut -f1), 10/10 entries verified)"
fi

# Code sign (if identity is available)
if [ -n "$MACOS_SIGNING_IDENTITY" ]; then
    echo "  Code signing with: $MACOS_SIGNING_IDENTITY"

    # Use Release.entitlements as-is (no keychain-access-groups injection).
    # Non-sandboxed apps access their own keychain group by default.
    # keychain-access-groups is a RESTRICTED entitlement that requires a
    # provisioning profile for Developer ID distribution — causes AMFI rejection.
    ENTITLEMENTS_SRC="$PROJECT_ROOT/macos/Runner/Release.entitlements"

    codesign --force --deep --sign "$MACOS_SIGNING_IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS_SRC" \
        "$STAGING_DIR/${APP_NAME}.app"
    echo "  Verifying app code signature..."
    codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/${APP_NAME}.app"
    echo "  Code signing complete."
else
    echo "  Skipping code signing (MACOS_SIGNING_IDENTITY not set)"
fi

# Notarize + staple the .app FIRST (before DMG packaging) so the .app
# bundle is offline-portable. Without an .app-level ticket, when a user
# drags the .app out of the mounted DMG into /Applications, the inner
# bundle has no embedded ticket — first launch on that machine triggers
# an online lookup against Apple's notary service (200-500ms latency,
# fails on offline first-runs). Big-tech baseline (Slack/VSCode/Zoom)
# staples both the .app AND the DMG; we now match that.
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
    echo "  Notarizing .app bundle (offline-portable ticket)..."
    APP_ZIP="$DIST_DIR/${APP_NAME}-app-notarize.zip"
    rm -f "$APP_ZIP"
    # `ditto -c -k --keepParent` is the Apple-recommended way to create
    # the zip notarytool accepts (preserves bundle metadata + xattrs that
    # `zip` strips, which would otherwise invalidate the codesign).
    ditto -c -k --keepParent "$STAGING_DIR/${APP_NAME}.app" "$APP_ZIP"

    xcrun notarytool submit "$APP_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait \
        --timeout 30m

    xcrun stapler staple "$STAGING_DIR/${APP_NAME}.app"
    echo "  Verifying stapled .app..."
    xcrun stapler validate "$STAGING_DIR/${APP_NAME}.app"
    rm -f "$APP_ZIP"
    echo "  .app stapled — offline-portable when dragged from DMG."
fi

# Create DMG (now containing the pre-stapled .app)
echo "  Creating DMG..."
hdiutil create -volname "${DISPLAY_NAME} Installer" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Notarize + staple the DMG container itself. The inner .app is already
# notarized+stapled at this point, but the DMG wrapper still needs its
# own ticket so Gatekeeper accepts the DMG before the user opens it.
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
    echo "  Submitting DMG for notarization..."
    # --timeout caps the wait at 30 minutes. Without it, notarytool --wait
    # blocks indefinitely when Apple's notary service stalls (documented
    # outages of 2-12h have happened), which would stall the CI matrix and
    # burn a release slot. Exit non-zero on timeout so the job fails loud
    # instead of hanging until the GitHub Actions 6h job cap.
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait \
        --timeout 30m
    xcrun stapler staple "$DMG_PATH"
    echo "  Verifying stapled DMG..."
    xcrun stapler validate "$DMG_PATH"
    # `stapler validate` is the authoritative proof that Apple's notarization
    # ticket is properly attached. We previously also ran `spctl -a -vv -t open`
    # here, but `-t open` evaluates the file as a *document* — macos-latest CI
    # runners with strict Gatekeeper reject DMG containers under that type
    # because the DMG wrapper itself is not codesigned. End-user experience
    # is unaffected — double-clicking the stapled DMG works because the
    # notarization ticket is embedded.
    echo "  Notarization complete (both .app and DMG stapled)."
else
    echo "  Skipping notarization (APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD not set)"
fi

# Clean up staging
rm -rf "$STAGING_DIR"

echo "  DMG created: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
