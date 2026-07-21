#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  node build.js
fi

node scripts/audit-landing.mjs "$@"
