#!/usr/bin/env bash
# Read-only Windows QA inventory probe.
# Renders docs/windows-qa-machine-inventory-<YYYY-MM-DD>.md based on
# live SSH probes. Idempotent — re-run anytime to refresh.
#
# Usage: scripts/qa/inventory.sh [--output <path>]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=_lib.sh
source "$HERE/_lib.sh"

OUT="${1:-$REPO/docs/windows-qa-machine-inventory-$(date +%Y-%m-%d).md}"

qa_log "Probing $QA_HOST (output: $OUT)"
qa_assert_ssh_ready

probe() {
    local label="$1"; shift
    local ps_src="$*"
    qa_log "  $label"
    qa_ssh "powershell -NoProfile -ExecutionPolicy Bypass -Command \"$ps_src\"" 2>/dev/null || echo "(probe failed: $label)"
}

OS=$(probe "OS Caption + Build" '(Get-CimInstance Win32_OperatingSystem) | Select-Object Caption,Version,BuildNumber | Format-List | Out-String')
HOSTINFO=$(probe "Hostname / User" 'hostname; whoami; (Get-CimInstance Win32_ComputerSystem).Domain')
PSV=$(probe "PowerShell Versions" '"PS 5.1: " + $PSVersionTable.PSVersion.ToString(); try { (pwsh -v) } catch { "PS 7: not installed" }')
NET=$(probe ".NET Framework" '(Get-ItemProperty HKLM:\SOFTWARE\Microsoft\NET\ Framework\ Setup\NDP\v4\Full\ -Name Release).Release')
WV2=$(probe "WebView2 Runtime" 'Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\* -ErrorAction SilentlyContinue | ForEach-Object { (Get-ItemProperty $_.PSPath).pv } | Select-Object -First 3')
DEF=$(probe "Defender + RTP" 'Get-MpComputerStatus | Select-Object AMServiceEnabled,RealTimeProtectionEnabled,AntivirusEnabled,IsTamperProtected | Format-List | Out-String')
SAC=$(probe "Smart App Control" 'try { (Get-MpComputerStatus).SmartAppControlState } catch { "SmartAppControlState not exposed (likely Win10)" }')
SS=$(probe "SmartScreen policy" 'Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\System -ErrorAction SilentlyContinue | Select-Object EnableSmartScreen | Format-List | Out-String')
DISK=$(probe "Disk free" 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,1)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,1)}} | Format-Table | Out-String')
INSTALLED=$(probe "Installed Svid/VidCombo" '
$paths = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
         "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
         "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "(?i)svid|vidcombo|snakeloader" } |
    Select-Object DisplayName,DisplayVersion,Publisher,InstallLocation |
    Format-List | Out-String')
QADIR=$(probe "QA working dir" 'if (Test-Path C:\QA\Snakeloader) { Get-ChildItem C:\QA\Snakeloader -Recurse -Depth 2 -Force | Select-Object Mode,LastWriteTime,Length,FullName | Format-Table -AutoSize | Out-String } else { "C:\QA\Snakeloader does not exist" }')
SECTIGO=$(probe "Sectigo R36 root trust" 'Get-ChildItem Cert:\LocalMachine\CA, Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match "Sectigo Public Code Signing CA R36|USERTrust RSA" } | Select-Object Subject,NotAfter,Thumbprint | Format-List | Out-String')
LOCALE=$(probe "Locale + TZ" '(Get-WinSystemLocale).Name; (Get-TimeZone).Id')
SSHD=$(probe "OpenSSH server config" 'Get-Service sshd | Select-Object Status,StartType | Format-List | Out-String; Get-Content C:\ProgramData\ssh\sshd_config -ErrorAction SilentlyContinue | Select-String "^(PubkeyAuth|PasswordAuth|AllowGroups|AllowUsers|Match|AuthorizedKeys)" | Out-String')

cat > "$OUT" <<EOF
# Windows QA Machine Inventory

Generated: $(date -u "+%Y-%m-%d %H:%M:%S UTC") (UTC+7: $(date "+%Y-%m-%d %H:%M:%S"))
Source: scripts/qa/inventory.sh on Mac, probed live via SSH to \`$QA_HOST\`.

## Host

\`\`\`
$HOSTINFO
\`\`\`

## OS

\`\`\`
$OS
\`\`\`

## Runtime stacks

PowerShell:
\`\`\`
$PSV
\`\`\`

.NET Framework release key: \`$NET\` (533320+ = .NET 4.8, 533325+ = 4.8.1)

WebView2 Runtime versions present:
\`\`\`
$WV2
\`\`\`

## Trust + AV state

Defender:
\`\`\`
$DEF
\`\`\`

Smart App Control: $SAC

SmartScreen policy:
\`\`\`
$SS
\`\`\`

Sectigo / USERTrust roots:
\`\`\`
$SECTIGO
\`\`\`

## OpenSSH server (return path)

\`\`\`
$SSHD
\`\`\`

## Disk

\`\`\`
$DISK
\`\`\`

## Installed Svid / VidCombo residue

\`\`\`
$INSTALLED
\`\`\`

## QA working directory

\`\`\`
$QADIR
\`\`\`

## Locale

\`\`\`
$LOCALE
\`\`\`

## Notes

- This machine is Windows 10. It is valid for installer/runtime/signature
  smoke. It is NOT a Win11 Smart App Control final gate.
- For SAC ON final gate, a Win11 box with SAC enabled is still required.
EOF

qa_log "Inventory written: $OUT"
