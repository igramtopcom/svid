# Mac→Windows QA Orchestration

Mac-side toolchain for driving the Windows QA box (`ssvid-qa` =
`qa@192.168.31.75`) from the Claude Code session on macOS.

All scripts assume:

1. SSH config alias `ssvid-qa` is configured in `~/.ssh/config` (done).
2. SSH public key `~/.ssh/id_ed25519.pub` is installed in
   `C:\Users\qa\.ssh\authorized_keys` on the Windows box
   (or `C:\ProgramData\ssh\administrators_authorized_keys` if `qa` is
   a member of the Administrators group).
3. Windows working directory is `C:\QA\Snakeloader\{artifacts,scripts,logs}`.

## Bootstrap (one-time, requires one credential transfer)

Pick exactly one path to install the Mac's SSH public key on the
Windows box. After that, every operation below is non-interactive.

### Path A — Mac terminal (preferred)

```
ssh-copy-id -i ~/.ssh/id_ed25519.pub qa@192.168.31.75
```

Single password prompt. Password is read by ssh into the kernel stdin,
not written to disk, not echoed to terminal, not stored in this repo.

### Path B — Local Windows agent

If a local agent or operator is already on the Windows box, append the
Mac's public key to the appropriate authorized_keys file. The key
content lives in `~/.ssh/id_ed25519.pub` on the Mac.

For non-admin `qa`:

```powershell
Add-Content -Path C:\Users\qa\.ssh\authorized_keys -Value '<pubkey>'
icacls C:\Users\qa\.ssh\authorized_keys /inheritance:r /grant:r 'qa:F' 'SYSTEM:F'
```

For admin `qa` (Windows OpenSSH special rule):

```powershell
Add-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value '<pubkey>'
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant:r 'Administrators:F' 'SYSTEM:F'
```

### Verify

After either path:

```
ssh ssvid-qa "whoami; hostname; [System.Environment]::OSVersion.Version"
```

Expected: prints user/host/OS without password prompt.

## Scripts (post-bootstrap)

| Script | Role |
| --- | --- |
| `inventory.sh` | One-shot read-only probe; renders `docs/windows-qa-machine-inventory-*.md` |
| `push.sh <artifact>` | Upload artifact to `C:\QA\Snakeloader\artifacts\` |
| `smoke.sh <brand> <installer>` | Wrap `scripts/windows_qa_smoke.ps1` over SSH |
| `pull_logs.sh` | Pull `C:\QA\Snakeloader\logs\*` back to `/private/tmp/qa-runs/<ts>/` |
| `clean.sh` | Uninstall residue, clear temp logs, kill lingering processes |

All scripts:

- Fail fast (`set -euo pipefail`).
- Have hard timeouts on the SSH side (no hung sessions).
- Print explicit PASS/FAIL with exit code.
- Never store credentials.

## Defense-in-depth

The Windows box is also accessible to a local agent (Gemini Antigravity)
running inside `C:\Users\nguye\.gemini\...`. The Mac-side toolchain
treats that agent as a peer, not a dependency — every smoke output must
be verifiable via SSH-pulled logs from `C:\QA\Snakeloader\logs\`, never
solely from the peer agent's sandbox.
