#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

echo "==> Runtime smoke wave"
echo
echo "[1/2] Playback + subtitle regressions"
"${FLUTTER[@]}" test \
  test/features/player/presentation/widgets/subtitle_search_sheet_test.dart \
  test/features/player/domain/services/external_subtitle_scan_service_test.dart \
  test/features/player/data/datasources/ffmpeg_datasource_test.dart \
  test/features/converter/data/datasources/conversion_datasource_test.dart
echo
echo "[2/2] Download queue lifecycle regressions"
"${FLUTTER[@]}" test \
  test/features/downloads/presentation/providers/downloads_notifier_retry_test.dart \
  test/features/downloads/data/datasources/download_local_datasource_test.dart
echo
echo "Runtime smoke wave passed."
