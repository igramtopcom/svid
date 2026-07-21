#!/usr/bin/env bash
# Shared helpers for Mac→Windows QA orchestration scripts.
# Source this from every scripts/qa/*.sh entry point.

set -euo pipefail

QA_HOST="${QA_HOST:-svid-qa}"
QA_WIN_ROOT="${QA_WIN_ROOT:-C:\\QA\\Snakeloader}"
QA_WIN_ARTIFACTS="${QA_WIN_ROOT}\\artifacts"
QA_WIN_LOGS="${QA_WIN_ROOT}\\logs"
QA_WIN_SCRIPTS="${QA_WIN_ROOT}\\scripts"

QA_SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=4
)

# Run a one-shot command on the Windows QA box via SSH.
# Usage: qa_ssh "<command>"
qa_ssh() {
    ssh "${QA_SSH_OPTS[@]}" "$QA_HOST" "$@"
}

# Run a PowerShell command on the Windows QA box.
# Usage: qa_pwsh "<powershell-source>"
qa_pwsh() {
    local src="$1"
    qa_ssh "powershell -NoProfile -ExecutionPolicy Bypass -Command \"$src\""
}

# Verify SSH key-based auth is working. Exit 1 with guidance if not.
qa_assert_ssh_ready() {
    if ! qa_ssh "echo READY" >/dev/null 2>&1; then
        echo "ERROR: ssh ${QA_HOST} failed in BatchMode (no password fallback)."
        echo "Bootstrap required — see scripts/qa/README.md"
        exit 1
    fi
}

# scp upload local file → Windows artifacts dir.
qa_upload() {
    local local_path="$1"
    local dest_name="${2:-$(basename "$local_path")}"
    scp "${QA_SSH_OPTS[@]}" "$local_path" \
        "${QA_HOST}:${QA_WIN_ARTIFACTS}\\${dest_name}"
}

# scp download Windows file → local path.
qa_download() {
    local remote_path="$1"
    local local_path="$2"
    scp "${QA_SSH_OPTS[@]}" "${QA_HOST}:${remote_path}" "$local_path"
}

qa_log() {
    printf '[qa] %s\n' "$*" >&2
}

qa_fail() {
    printf '[qa] FAIL: %s\n' "$*" >&2
    exit 1
}
