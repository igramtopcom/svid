#!/usr/bin/env bash
# Mac→Windows wrapper around scripts/windows_qa_smoke.ps1.
# Runs the canonical smoke harness on the Windows QA box over SSH,
# captures exit code + log location, optionally pulls logs locally.
#
# Two modes:
#   --silent   (default) — SSH non-interactive session. Good for
#              installer-execution / payload-scan / WER smoke.
#   --visible  — schedule task /IT in active desktop session.
#              Required for tests that need a real UI (UAC prompts,
#              SmartScreen UX, Inno [Run] visible relaunch).
#
# Usage:
#   scripts/qa/smoke.sh --brand ssvid --installer SSvid-1.3.9-windows-x64-setup.exe
#   scripts/qa/smoke.sh --brand vidcombo --installer VidCombo-1.6.6-windows-x64-setup.exe --visible
#   scripts/qa/smoke.sh --brand ssvid --installer ... --launch-timeout 90 --pull-logs

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

BRAND=""
INSTALLER=""
MODE="silent"
LAUNCH_TIMEOUT=60
PULL_LOGS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --brand) BRAND="$2"; shift 2 ;;
        --installer) INSTALLER="$2"; shift 2 ;;
        --visible) MODE="visible"; shift ;;
        --silent) MODE="silent"; shift ;;
        --launch-timeout) LAUNCH_TIMEOUT="$2"; shift 2 ;;
        --pull-logs) PULL_LOGS=true; shift ;;
        -h|--help)
            sed -n '2,/^set/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) qa_fail "unknown arg: $1" ;;
    esac
done

[[ -n "$BRAND" ]] || qa_fail "--brand <ssvid|vidcombo> required"
[[ "$BRAND" == "ssvid" || "$BRAND" == "vidcombo" ]] || qa_fail "brand must be ssvid or vidcombo"
[[ -n "$INSTALLER" ]] || qa_fail "--installer <filename-in-artifacts> required"

qa_assert_ssh_ready

# Ensure scripts/windows_qa_smoke.ps1 is current on the Windows box.
REPO="$(cd "$HERE/../.." && pwd)"
SMOKE_PS1="$REPO/scripts/windows_qa_smoke.ps1"
[[ -f "$SMOKE_PS1" ]] || qa_fail "missing local: $SMOKE_PS1"

qa_log "Syncing windows_qa_smoke.ps1 to QA box…"
qa_pwsh "New-Item -ItemType Directory -Force -Path '${QA_WIN_SCRIPTS}' | Out-Null"
scp "${QA_SSH_OPTS[@]}" "$SMOKE_PS1" "${QA_HOST}:/C:/QA/Snakeloader/scripts/windows_qa_smoke.ps1"

REMOTE_INSTALLER="${QA_WIN_ARTIFACTS}\\${INSTALLER}"
qa_log "Smoke target: $REMOTE_INSTALLER  (brand=$BRAND mode=$MODE timeout=${LAUNCH_TIMEOUT}s)"

# Pre-check installer present on Windows.
PRESENT=$(qa_pwsh "if (Test-Path '${REMOTE_INSTALLER}') { 'yes' } else { 'no' }" | tr -d '\r\n ')
[[ "$PRESENT" == "yes" ]] || qa_fail "installer not on Windows: ${REMOTE_INSTALLER}. Run scripts/qa/push.sh first."

LOG_REMOTE="${QA_WIN_LOGS}\\smoke-${BRAND}-$(date +%Y%m%d-%H%M%S).log"
qa_pwsh "New-Item -ItemType Directory -Force -Path '${QA_WIN_LOGS}' | Out-Null"

if [[ "$MODE" == "silent" ]]; then
    qa_log "Running silent smoke via SSH (non-interactive session)…"
    set +e
    qa_ssh "pwsh -NoProfile -ExecutionPolicy Bypass -File '${QA_WIN_SCRIPTS}\\windows_qa_smoke.ps1' -Installer '${REMOTE_INSTALLER}' -Brand ${BRAND} -LaunchTimeoutSeconds ${LAUNCH_TIMEOUT} 2>&1 | Tee-Object -FilePath '${LOG_REMOTE}'"
    RC=$?
    set -e
else
    qa_log "Running visible smoke via Scheduled Task /IT (active desktop session)…"
    TASKNAME="SnakeloaderSmoke-${BRAND}-$$"
    CMDFILE="${QA_WIN_SCRIPTS}\\run-smoke-${BRAND}.cmd"

    # Build a .cmd entry point that runs the smoke and writes a marker
    # file so we can detect completion (Scheduled Task fire-and-forget).
    qa_pwsh "Set-Content -Path '${CMDFILE}' -Encoding ASCII -Value @'
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File ${QA_WIN_SCRIPTS}\\windows_qa_smoke.ps1 -Installer ${REMOTE_INSTALLER} -Brand ${BRAND} -LaunchTimeoutSeconds ${LAUNCH_TIMEOUT} > ${LOG_REMOTE} 2>&1
echo %ERRORLEVEL% > ${QA_WIN_LOGS}\\smoke-${BRAND}-exitcode.txt
'@"

    qa_pwsh "schtasks /Create /TN '${TASKNAME}' /TR '${CMDFILE}' /SC ONCE /ST 23:59 /RU '%USERNAME%' /IT /F | Out-Null; schtasks /Run /TN '${TASKNAME}' | Out-Null"

    qa_log "Task launched. Polling for completion (max ${LAUNCH_TIMEOUT}+120s)…"
    DEADLINE=$(( $(date +%s) + LAUNCH_TIMEOUT + 120 ))
    RC=124
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        DONE=$(qa_pwsh "if (Test-Path '${QA_WIN_LOGS}\\smoke-${BRAND}-exitcode.txt') { Get-Content '${QA_WIN_LOGS}\\smoke-${BRAND}-exitcode.txt' } else { '' }" | tr -d '\r\n ')
        if [[ -n "$DONE" ]]; then
            RC=$DONE
            break
        fi
        sleep 5
    done
    qa_pwsh "schtasks /Delete /TN '${TASKNAME}' /F 2>&1 | Out-Null" || true
fi

qa_log "Smoke remote log: ${LOG_REMOTE}"
qa_log "Smoke exit code: $RC"

if [[ "$PULL_LOGS" == "true" ]]; then
    TS=$(date +%Y%m%d-%H%M%S)
    LOCAL_DIR="/private/tmp/qa-runs/${TS}-${BRAND}"
    mkdir -p "$LOCAL_DIR"
    qa_download "${LOG_REMOTE}" "${LOCAL_DIR}/" || qa_log "  (log download warning)"
    qa_log "Logs pulled: ${LOCAL_DIR}"
fi

if [[ "$RC" == "0" ]]; then
    qa_log "PASS"
    exit 0
else
    qa_log "FAIL (exit=$RC)"
    exit "$RC"
fi
