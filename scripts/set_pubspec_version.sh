#!/usr/bin/env bash
# Override pubspec.yaml version at CI build time so binaries, installers, and
# packaging scripts all agree with the workflow_dispatch input. Without this,
# every build tool reads pubspec directly and a cross-version multi-brand
# release (e.g. Svid 1.3.5 + VidCombo 1.6.2) bricks the auto-updater because
# the tag says one thing and the embedded version says another.
#
# Usage:
#   scripts/set_pubspec_version.sh <version> [build_number]
#
# If build_number is omitted, the existing +N suffix in pubspec.yaml is kept.
# If pubspec has no +N suffix either, no build number is written.
set -euo pipefail

NEW_VERSION="${1:?usage: set_pubspec_version.sh <version> [build_number]}"
BUILD_NUMBER="${2:-}"
PUBSPEC="${PUBSPEC_PATH:-pubspec.yaml}"

if [ ! -f "$PUBSPEC" ]; then
  echo "set_pubspec_version: $PUBSPEC not found (cwd=$(pwd))" >&2
  exit 1
fi

CURRENT_LINE=$(grep -E '^version:[[:space:]]' "$PUBSPEC" | head -n 1)
if [ -z "$CURRENT_LINE" ]; then
  echo "set_pubspec_version: no 'version:' line in $PUBSPEC" >&2
  exit 1
fi

# Extract existing build suffix (digits after +) if any.
EXISTING_BUILD=$(echo "$CURRENT_LINE" | sed -E 's/^version:[[:space:]]*[^+[:space:]]+\+?([0-9]*).*/\1/')

if [ -n "$BUILD_NUMBER" ]; then
  FINAL="${NEW_VERSION}+${BUILD_NUMBER}"
elif [ -n "$EXISTING_BUILD" ]; then
  FINAL="${NEW_VERSION}+${EXISTING_BUILD}"
else
  FINAL="${NEW_VERSION}"
fi

# Use -i with a backup extension for portability across BSD sed (macOS) and
# GNU sed (Linux / Git Bash). Then delete the backup.
sed -i.bak -E "s/^version:[[:space:]]*.*/version: ${FINAL}/" "$PUBSPEC"
rm -f "${PUBSPEC}.bak"

echo "pubspec version -> ${FINAL}"
grep -E '^version:' "$PUBSPEC"
