#!/usr/bin/env bash
# Reset Windows QA box state between smoke runs.
# Uninstalls Svid/VidCombo if present, kills lingering processes,
# clears %TEMP%\inno-install-*.log and C:\QA\Snakeloader\logs\*.
#
# Usage: scripts/qa/clean.sh [--brand svid|vidcombo|all] [--keep-logs]
# Default: --brand all, logs are cleared.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

BRAND="all"
KEEP_LOGS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --brand) BRAND="$2"; shift 2 ;;
        --keep-logs) KEEP_LOGS=true; shift ;;
        *) qa_fail "unknown arg: $1" ;;
    esac
done

qa_assert_ssh_ready
qa_log "Cleaning Windows QA state (brand=$BRAND keep-logs=$KEEP_LOGS)"

# Brand → match patterns for installed apps / processes.
case "$BRAND" in
    svid) PAT_INST='svid'; PAT_PROC='svid' ;;
    vidcombo) PAT_INST='vidcombo'; PAT_PROC='vidcombo' ;;
    all) PAT_INST='svid|vidcombo|snakeloader'; PAT_PROC='svid|vidcombo' ;;
    *) qa_fail "brand must be svid|vidcombo|all" ;;
esac

# Kill lingering app processes (idempotent).
qa_log "  Killing processes matching: $PAT_PROC"
qa_pwsh "Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.ProcessName -match '(?i)${PAT_PROC}' } | Stop-Process -Force -ErrorAction SilentlyContinue" || true

# Uninstall via per-user Inno uninstaller (matches installer's /CURRENTUSER).
qa_log "  Uninstalling apps matching: $PAT_INST"
qa_pwsh "
\$paths = 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
         'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
         'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
Get-ItemProperty \$paths -ErrorAction SilentlyContinue |
    Where-Object { \$_.DisplayName -match '(?i)${PAT_INST}' } |
    ForEach-Object {
        \$us = \$_.UninstallString
        if (\$us) {
            \$us = \$us -replace '\"',''
            Write-Host \"  Uninstall: \$(\$_.DisplayName) → \$us\"
            Start-Process -FilePath \$us -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -ErrorAction SilentlyContinue
        }
    }
"

# Clear Inno installer temp logs.
qa_log "  Clearing %TEMP%\\inno-install-*.log"
qa_pwsh "Remove-Item -Force -ErrorAction SilentlyContinue \$env:TEMP\\inno-install-*.log" || true

# Clear smoke logs unless --keep-logs.
if [[ "$KEEP_LOGS" == "false" ]]; then
    qa_log "  Clearing ${QA_WIN_LOGS}\\*"
    qa_pwsh "Get-ChildItem '${QA_WIN_LOGS}' -File -ErrorAction SilentlyContinue | Remove-Item -Force" || true
fi

qa_log "Clean complete."
