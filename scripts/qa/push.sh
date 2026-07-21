#!/usr/bin/env bash
# Upload an artifact to the Windows QA box and verify SHA-256.
#
# Usage: scripts/qa/push.sh <local-file> [remote-filename]
#
# Default remote dir: C:\QA\Snakeloader\artifacts\
# Verifies SHA-256 on Windows side via Get-FileHash to catch
# truncation/corruption mid-flight (scp does not checksum by default).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <local-file> [remote-filename]" >&2
    exit 2
fi

LOCAL="$1"
REMOTE_NAME="${2:-$(basename "$LOCAL")}"

[[ -f "$LOCAL" ]] || qa_fail "local file not found: $LOCAL"

qa_assert_ssh_ready

LOCAL_SHA=$(shasum -a 256 "$LOCAL" | awk '{print toupper($1)}')
SIZE_MB=$(du -m "$LOCAL" | awk '{print $1}')
qa_log "Uploading $LOCAL (${SIZE_MB} MB) → ${QA_WIN_ARTIFACTS}\\${REMOTE_NAME}"
qa_log "  SHA-256 (local): $LOCAL_SHA"

# Ensure target dir exists.
qa_pwsh "New-Item -ItemType Directory -Force -Path '${QA_WIN_ARTIFACTS}' | Out-Null"

# scp upload. Note: Windows OpenSSH scp uses POSIX-style paths over the wire.
REMOTE_POSIX="/C:/QA/Snakeloader/artifacts/${REMOTE_NAME}"
scp "${QA_SSH_OPTS[@]}" "$LOCAL" "${QA_HOST}:${REMOTE_POSIX}"

REMOTE_SHA=$(qa_pwsh "(Get-FileHash -Path '${QA_WIN_ARTIFACTS}\\${REMOTE_NAME}' -Algorithm SHA256).Hash" | tr -d '\r\n ')

qa_log "  SHA-256 (remote): $REMOTE_SHA"
if [[ "$LOCAL_SHA" == "$REMOTE_SHA" ]]; then
    qa_log "PASS hash match"
else
    qa_fail "hash mismatch — corruption mid-flight. Local=$LOCAL_SHA Remote=$REMOTE_SHA"
fi
