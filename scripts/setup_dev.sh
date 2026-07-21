#!/usr/bin/env bash
# setup_dev.sh — First-time development environment setup for SSvid Desktop
#
# Run this script once after cloning or pulling the repository to generate
# all required Dart source files (Freezed, Riverpod, Drift).
#
# Usage:
#   chmod +x scripts/setup_dev.sh
#   ./scripts/setup_dev.sh
#
# Why this is needed:
#   This project uses code generation (Freezed, Riverpod, Drift) whose
#   output files (*.g.dart, *.freezed.dart) are excluded from git via
#   .gitignore. They must be regenerated locally after each clone/pull.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> [1/2] Installing Flutter dependencies..."
flutter pub get

echo "==> [2/2] Generating Freezed / Riverpod / Drift code..."
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "✅ Setup complete. You can now run the app:"
echo "   ./scripts/run_dev.sh macos"
echo "   flutter run -d linux"
echo ""
echo "Verify the setup is clean:"
echo "   flutter analyze lib/   # should report: No issues found"
echo "   flutter test           # should pass all tests"
