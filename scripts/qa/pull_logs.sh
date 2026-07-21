#!/usr/bin/env bash
# Pull C:\QA\Snakeloader\logs\* from Windows QA box back to Mac.
#
# Usage: scripts/qa/pull_logs.sh [destination-dir]
# Default destination: /private/tmp/qa-runs/<YYYYmmdd-HHMMSS>/

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

TS=$(date +%Y%m%d-%H%M%S)
DEST="${1:-/private/tmp/qa-runs/${TS}}"
mkdir -p "$DEST"

qa_assert_ssh_ready

qa_log "Pulling logs → $DEST"

# List + pull each file individually (scp -r over Windows OpenSSH is flaky).
FILES=$(qa_pwsh "Get-ChildItem '${QA_WIN_LOGS}' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name" | tr -d '\r')

if [[ -z "$FILES" ]]; then
    qa_log "(no logs found on remote)"
    exit 0
fi

COUNT=0
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    scp "${QA_SSH_OPTS[@]}" "${QA_HOST}:/C:/QA/Snakeloader/logs/${f}" "$DEST/" 2>/dev/null && COUNT=$((COUNT+1)) || qa_log "  warn: pull failed: $f"
done <<< "$FILES"

qa_log "Pulled $COUNT log(s) → $DEST"
ls -lh "$DEST" >&2
