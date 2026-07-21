# bootstrap_windows_build_lab.ps1
#
# Run ONCE on the Windows QA box (192.168.31.75) to provision a full
# local build+test lab for ssvid-desktop (Flutter + Rust MSVC + Inno).
#
# Idempotent: re-running is safe; only installs what's missing.
# ASCII-only: avoids PowerShell 5.1 UTF-8-no-BOM parsing issues
# (lesson from commit 957c2f64 in main repo).
#
# Phases:
#   0. Self-elevate UAC if not already admin
#   1. Install Mac orchestrator pubkey into authorized_keys
#   2. Ensure winget is available + accepted
#   3. winget installs: Git, GitHub CLI, PowerShell 7, 7zip, CMake,
#      Ninja, Inno Setup, VS Build Tools 2022 (Desktop C++ workload),
#      Windows SDK, Sysinternals (handle.exe for diagnostics)
#   4. Rust MSVC toolchain via rustup-init.exe
#   5. FVM (Flutter Version Manager) via dart pub global, then Flutter 3.29.3
#   6. Verify all tools, write version table to log
#
# Usage (from elevated or non-elevated PowerShell):
#   pwsh -NoProfile -ExecutionPolicy Bypass -File bootstrap_windows_build_lab.ps1
#   # or, if PowerShell 7 not yet installed:
#   powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap_windows_build_lab.ps1

[CmdletBinding()]
param(
    [switch]$SkipUacElevation,
    [switch]$SkipVsBuildTools,
    [string]$FlutterVersion = '3.29.3'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ===========================================================================
# Constants
# ===========================================================================

$MAC_PUBKEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1yRDH7PvrGxppE/VFOO8Sul691MUSth8AHEPetf7MA macos-claude-orchestrator-20260512'

$LOG_DIR = 'C:\QA\Snakeloader\logs'
$LOG_FILE = Join-Path $LOG_DIR ("bootstrap-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

# Phase tracking
$Script:phaseResults = @()

# ===========================================================================
# Helpers
# ===========================================================================

function Write-Phase {
    param([string]$Msg, [string]$Color = 'Cyan')
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LOG_FILE -Value $line -Encoding ASCII
}

function Write-Ok {
    param([string]$Msg)
    $line = "[{0:HH:mm:ss}]   OK  {1}" -f (Get-Date), $Msg
    Write-Host $line -ForegroundColor Green
    Add-Content -Path $LOG_FILE -Value $line -Encoding ASCII
}

function Write-Warn {
    param([string]$Msg)
    $line = "[{0:HH:mm:ss}]   WARN {1}" -f (Get-Date), $Msg
    Write-Host $line -ForegroundColor Yellow
    Add-Content -Path $LOG_FILE -Value $line -Encoding ASCII
}

function Write-Fail {
    param([string]$Msg)
    $line = "[{0:HH:mm:ss}]   FAIL {1}" -f (Get-Date), $Msg
    Write-Host $line -ForegroundColor Red
    Add-Content -Path $LOG_FILE -Value $line -Encoding ASCII
}

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine + ';' + $user) -replace ';;', ';'
}

function Test-Command {
    param([string]$Name)
    $null = Get-Command $Name -ErrorAction SilentlyContinue
    return $?
}

function Invoke-Winget {
    param([string[]]$Args, [string]$Label)
    Write-Phase "winget $($Args -join ' ')"
    $proc = Start-Process -FilePath 'winget' -ArgumentList $Args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Write-Ok "$Label installed"
        return $true
    }
    elseif ($proc.ExitCode -eq -1978335189) {
        # APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
        Write-Ok "$Label already installed"
        return $true
    }
    else {
        Write-Warn "$Label winget exit $($proc.ExitCode)"
        return $false
    }
}

# ===========================================================================
# Phase 0: UAC self-elevate
# ===========================================================================

New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
Write-Phase "=== bootstrap_windows_build_lab.ps1 starting ===" 'Magenta'
Write-Phase "Log: $LOG_FILE" 'Gray'

if (-not (Test-IsAdmin)) {
    if ($SkipUacElevation) {
        Write-Warn "Not running as admin and -SkipUacElevation set. Some installs may fail."
    }
    else {
        Write-Phase "Re-launching with UAC elevation..." 'Yellow'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($SkipVsBuildTools) { $argList += '-SkipVsBuildTools' }
        if ($FlutterVersion -ne '3.29.3') { $argList += @('-FlutterVersion', $FlutterVersion) }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
        exit 0
    }
}
else {
    Write-Ok "Running with Administrator rights"
}

# ===========================================================================
# Phase 1: Install Mac pubkey into authorized_keys
# ===========================================================================

Write-Phase "Phase 1: SSH key authorization" 'Magenta'

# Detect whether current user is an Administrator. Windows OpenSSH reads
# admin user keys from C:\ProgramData\ssh\administrators_authorized_keys,
# NOT from %USERPROFILE%\.ssh\authorized_keys.
$qaUser = [Environment]::UserName
$adminGroup = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
               ForEach-Object { $_.Name }) -join "`n"
$qaIsAdmin = $adminGroup -match "(?i)\\$qaUser$"

if ($qaIsAdmin) {
    $authKeysFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
    Write-Phase "  qa user is Administrator -> writing to $authKeysFile" 'Yellow'
}
else {
    $authKeysFile = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
    Write-Phase "  qa user is non-admin -> writing to $authKeysFile"
}

$authKeysDir = Split-Path -Parent $authKeysFile
if (-not (Test-Path $authKeysDir)) {
    New-Item -ItemType Directory -Force -Path $authKeysDir | Out-Null
}

# Idempotent: only append if pubkey not already present
$existing = if (Test-Path $authKeysFile) { Get-Content -Path $authKeysFile -ErrorAction SilentlyContinue } else { @() }
if ($existing -contains $MAC_PUBKEY) {
    Write-Ok "Mac pubkey already authorized"
}
else {
    Add-Content -Path $authKeysFile -Value $MAC_PUBKEY -Encoding ASCII
    Write-Ok "Mac pubkey appended"
}

# Lock down permissions per Windows OpenSSH requirements
if ($qaIsAdmin) {
    icacls $authKeysFile /inheritance:r /grant:r 'Administrators:F' 'SYSTEM:F' 2>&1 | Out-Null
}
else {
    icacls $authKeysFile /inheritance:r /grant:r "${qaUser}:F" 'SYSTEM:F' 2>&1 | Out-Null
}
Write-Ok "authorized_keys ACL hardened"

# Ensure sshd is running with PubkeyAuthentication on
$sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshd) {
    if ($sshd.Status -ne 'Running') {
        Start-Service sshd
        Write-Ok "sshd service started"
    }
    if ($sshd.StartType -ne 'Automatic') {
        Set-Service -Name sshd -StartupType Automatic
        Write-Ok "sshd set to Automatic startup"
    }
}
else {
    Write-Warn "sshd service not installed. Installing OpenSSH.Server..."
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction SilentlyContinue | Out-Null
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
    New-NetFirewallRule -Name 'sshd' -DisplayName 'OpenSSH Server (sshd)' -Enabled True `
        -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null
    Write-Ok "OpenSSH Server installed + firewall opened"
}

# ===========================================================================
# Phase 2: winget readiness
# ===========================================================================

Write-Phase "Phase 2: winget readiness" 'Magenta'

if (-not (Test-Command winget)) {
    Write-Fail "winget not found. Install 'App Installer' from Microsoft Store, then re-run."
    Write-Fail "https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1"
    exit 2
}
Write-Ok "winget present: $(winget --version)"

# Accept source agreements once (silent)
winget source update --accept-source-agreements --disable-interactivity 2>&1 | Out-Null

# ===========================================================================
# Phase 3: Core dev tools via winget
# ===========================================================================

Write-Phase "Phase 3: Core dev tools" 'Magenta'

$wingetPackages = @(
    @{ Id = 'Git.Git';                            Label = 'Git for Windows' },
    @{ Id = 'GitHub.cli';                         Label = 'GitHub CLI (gh)' },
    @{ Id = 'Microsoft.PowerShell';               Label = 'PowerShell 7' },
    @{ Id = '7zip.7zip';                          Label = '7-Zip' },
    @{ Id = 'Kitware.CMake';                      Label = 'CMake' },
    @{ Id = 'Ninja-build.Ninja';                  Label = 'Ninja' },
    @{ Id = 'JRSoftware.InnoSetup';               Label = 'Inno Setup 6' }
)

foreach ($pkg in $wingetPackages) {
    Invoke-Winget -Label $pkg.Label -Args @(
        'install', '--id', $pkg.Id,
        '--silent', '--accept-source-agreements', '--accept-package-agreements',
        '--scope', 'machine'
    ) | Out-Null
}

Refresh-Path

# ===========================================================================
# Phase 4: Visual Studio 2022 Build Tools + Windows SDK
# ===========================================================================

Write-Phase "Phase 4: VS Build Tools 2022 + Windows SDK" 'Magenta'

if ($SkipVsBuildTools) {
    Write-Warn "Skipping VS Build Tools per -SkipVsBuildTools"
}
else {
    # VS Build Tools is special: winget install + override with workload list
    $vsArgs = @(
        'install', '--id', 'Microsoft.VisualStudio.2022.BuildTools',
        '--silent', '--accept-source-agreements', '--accept-package-agreements',
        '--override',
        '--quiet --wait --norestart --nocache ' +
        '--add Microsoft.VisualStudio.Workload.VCTools ' +
        '--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ' +
        '--add Microsoft.VisualStudio.Component.Windows11SDK.22621 ' +
        '--add Microsoft.VisualStudio.Component.VC.CMake.Project'
    )
    Invoke-Winget -Label 'VS Build Tools 2022' -Args $vsArgs | Out-Null
}

Refresh-Path

# ===========================================================================
# Phase 5: Rust MSVC toolchain via rustup-init
# ===========================================================================

Write-Phase "Phase 5: Rust MSVC toolchain" 'Magenta'

if (Test-Command rustc) {
    Write-Ok "rustc already present: $(rustc --version)"
}
else {
    $rustupInit = Join-Path $env:TEMP 'rustup-init.exe'
    Write-Phase "Downloading rustup-init.exe..."
    Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile $rustupInit -UseBasicParsing
    Write-Phase "Running rustup-init (-y --default-toolchain stable --default-host x86_64-pc-windows-msvc)..."
    & $rustupInit -y --default-toolchain stable --default-host x86_64-pc-windows-msvc --no-modify-path
    Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue
    # rustup installs to %USERPROFILE%\.cargo\bin
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    if (-not ($env:Path -split ';' -contains $cargoBin)) {
        [Environment]::SetEnvironmentVariable('Path', $env:Path + ";$cargoBin", 'User')
        $env:Path += ";$cargoBin"
    }
    Write-Ok "Rust installed: $(rustc --version)"
}

# Ensure the x86_64-pc-windows-msvc target (default on Windows but explicit is safer)
& rustup target add x86_64-pc-windows-msvc 2>&1 | Out-Null
Write-Ok "Rust target x86_64-pc-windows-msvc ready"

# ===========================================================================
# Phase 6: FVM + Flutter 3.29.3
# ===========================================================================

Write-Phase "Phase 6: FVM + Flutter $FlutterVersion" 'Magenta'

# FVM via standalone install script (no dart-pub-global churn)
$fvmInstaller = 'https://github.com/leoafarias/fvm/raw/main/scripts/install.ps1'
if (Test-Command fvm) {
    Write-Ok "fvm already present: $(fvm --version)"
}
else {
    Write-Phase "Installing FVM via official PowerShell installer..."
    Invoke-Expression (Invoke-WebRequest -Uri $fvmInstaller -UseBasicParsing).Content
    Refresh-Path
    if (Test-Command fvm) {
        Write-Ok "fvm installed: $(fvm --version)"
    }
    else {
        Write-Warn "fvm not on PATH after install. Open a new shell or add %LOCALAPPDATA%\fvm to PATH."
    }
}

# Install the pinned Flutter SDK
if (Test-Command fvm) {
    Write-Phase "fvm install $FlutterVersion ..."
    & fvm install $FlutterVersion
    Write-Ok "Flutter $FlutterVersion installed via FVM"
    # Make it the global default so plain 'fvm flutter' works
    & fvm global $FlutterVersion 2>&1 | Out-Null
    Write-Ok "fvm global -> $FlutterVersion"
}

# ===========================================================================
# Phase 7: Verification
# ===========================================================================

Write-Phase "Phase 7: Verification" 'Magenta'

$tools = @(
    @{ Name = 'git';     Cmd = 'git --version' },
    @{ Name = 'gh';      Cmd = 'gh --version' },
    @{ Name = 'pwsh';    Cmd = 'pwsh -v' },
    @{ Name = 'cmake';   Cmd = 'cmake --version' },
    @{ Name = 'ninja';   Cmd = 'ninja --version' },
    @{ Name = '7z';      Cmd = '7z' },
    @{ Name = 'iscc';    Cmd = 'iscc /?' },
    @{ Name = 'rustc';   Cmd = 'rustc --version' },
    @{ Name = 'cargo';   Cmd = 'cargo --version' },
    @{ Name = 'rustup';  Cmd = 'rustup --version' },
    @{ Name = 'fvm';     Cmd = 'fvm --version' }
)

$verifyResults = @()
foreach ($t in $tools) {
    try {
        $out = & cmd /c "$($t.Cmd) 2>&1 | findstr /v ^$" 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -le 1 -and $out) {
            Write-Ok ("{0,-8} {1}" -f $t.Name, $out)
            $verifyResults += [pscustomobject]@{ Tool = $t.Name; Status = 'OK'; Version = "$out" }
        }
        else {
            Write-Warn ("{0,-8} NOT FOUND on PATH" -f $t.Name)
            $verifyResults += [pscustomobject]@{ Tool = $t.Name; Status = 'MISSING'; Version = '' }
        }
    }
    catch {
        Write-Warn ("{0,-8} probe error: {1}" -f $t.Name, $_.Exception.Message)
        $verifyResults += [pscustomobject]@{ Tool = $t.Name; Status = 'ERROR'; Version = '' }
    }
}

# MSVC cl.exe (special — only available via Developer Command Prompt env)
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsInstall = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsInstall) {
        $cl = Get-ChildItem -Path (Join-Path $vsInstall 'VC\Tools\MSVC') -Filter 'cl.exe' -Recurse -ErrorAction SilentlyContinue |
              Where-Object FullName -match 'x64\\cl\.exe$' | Select-Object -First 1
        if ($cl) {
            Write-Ok "cl.exe   $($cl.FullName)"
            $verifyResults += [pscustomobject]@{ Tool = 'cl.exe (MSVC)'; Status = 'OK'; Version = $cl.FullName }
        }
        else {
            Write-Warn "cl.exe NOT FOUND under $vsInstall"
        }
    }
}

# Windows SDK signtool.exe
$signtool = Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object FullName -match 'x64\\signtool\.exe$' | Sort-Object FullName -Descending | Select-Object -First 1
if ($signtool) {
    Write-Ok "signtool $($signtool.FullName)"
    $verifyResults += [pscustomobject]@{ Tool = 'signtool'; Status = 'OK'; Version = $signtool.FullName }
}
else {
    Write-Warn "signtool.exe NOT FOUND under Windows Kits"
}

# ===========================================================================
# Summary
# ===========================================================================

Write-Phase "=== bootstrap complete ===" 'Magenta'
$verifyResults | Format-Table -AutoSize | Out-String | ForEach-Object { Add-Content -Path $LOG_FILE -Value $_ -Encoding ASCII }

Write-Host ""
Write-Host "Next step (run from Mac):" -ForegroundColor Cyan
Write-Host "  ssh ssvid-qa 'whoami; hostname'  # should succeed without password" -ForegroundColor Gray
Write-Host "  scripts/qa/inventory.sh           # full machine inventory" -ForegroundColor Gray
Write-Host ""
Write-Host "Then run clone+first-build on Windows via SSH from Mac:" -ForegroundColor Cyan
Write-Host "  ssh ssvid-qa 'powershell -File C:\QA\Snakeloader\scripts\clone_and_first_build.ps1 -Brand ssvid'" -ForegroundColor Gray

$failures = ($verifyResults | Where-Object Status -ne 'OK').Count
if ($failures -gt 0) {
    Write-Warn "$failures tool(s) missing. Re-run this script after rebooting or in a new shell."
    exit 1
}
exit 0
