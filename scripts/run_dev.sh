#!/usr/bin/env bash
# run_dev.sh — Local development runner for Svid (Svid)
# Reads credentials from tools/telegram-bridge/.env and passes as --dart-define
# Usage: ./scripts/run_dev.sh [platform] [extra flutter args]
#   platform: macos (default) | linux | windows
#   e.g.: ./scripts/run_dev.sh macos
#         ./scripts/run_dev.sh macos --release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/tools/telegram-bridge/.env"

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

# Source only SUPABASE_* and SENTRY_DSN from .env (ignore other vars)
SUPABASE_URL=""
SUPABASE_ANON_KEY=""
SENTRY_DSN=""

while IFS='=' read -r key value; do
  # Strip quotes and whitespace
  value="${value%\"}"
  value="${value#\"}"
  case "$key" in
    SUPABASE_URL)    SUPABASE_URL="$value" ;;
    SUPABASE_ANON_KEY) SUPABASE_ANON_KEY="$value" ;;
    SENTRY_DSN)      SENTRY_DSN="$value" ;;
  esac
done < "$ENV_FILE"

PLATFORM="${1:-macos}"
shift 1 2>/dev/null || true

echo "==> Running Svid on $PLATFORM with Supabase configured"
echo "    URL: ${SUPABASE_URL:0:40}..."

flutter run -d "$PLATFORM" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  "$@"
