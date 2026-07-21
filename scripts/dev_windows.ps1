# scripts/dev_windows.ps1 — Unified dev runner for SSvid + VidCombo on Windows.
#
# Mirrors scripts/dev.sh (which is macOS-only) so the Windows workflow has
# the same one-shot brand-switch + version-override + build behaviour. The
# big reason to use this instead of running flutter build directly:
#
#   pubspec.yaml `version:` is the CI/release anchor (currently 1.3.7+12).
#   The shipped website/version.json publishes 1.3.8 / VidCombo 1.6.5 as
#   "latest" — so any dev build that uses the bare pubspec version will
#   trigger the in-app update prompt the moment startup_service polls the
#   release manifest. We bypass it by passing --dart-define=APP_VERSION=...
#   set to a value at or above the public latest, which AppConstants.init
#   reads with priority over PackageInfo.
#
# Usage:
#   scripts\dev_windows.ps1                     # ssvid release (default)
#   scripts\dev_windows.ps1 ssvid               # ssvid release
#   scripts\dev_windows.ps1 vidcombo            # vidcombo release
#   scripts\dev_windows.ps1 ssvid debug         # ssvid debug build
#   scripts\dev_windows.ps1 vidcombo release    # vidcombo release build
#
# Optional env vars:
#   SSVID_DEV_VERSION    override the default 1.4.0 dev version for SSvid
#   VIDCOMBO_DEV_VERSION override the default 1.7.1 dev version for VidCombo
#   APP_VERSION          override BOTH brands (escape hatch)
#   SENTRY_DSN           passthrough to Sentry init in the running app
#   CLEAN                set to 1 to wipe build/windows before building
#
# Exit codes:
#   0  build succeeded, exe present in build\windows\x64\runner\<Mode>\
#   1  invalid brand/mode argument
#   2  build failure or missing exe afterwards

[CmdletBinding()]
param(
    [ValidateSet('ssvid', 'vidcombo')]
    [string]$Brand = 'ssvid',
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path

# Dev versions kept above the shipped website/version.json to suppress the
# in-app update prompt during testing. Keep these bumped whenever the
# public latest changes.
switch ($Brand) {
    'ssvid'    { $defaultVersion = if ($env:SSVID_DEV_VERSION)    { $env:SSVID_DEV_VERSION }    else { '1.4.0' } }
    'vidcombo' { $defaultVersion = if ($env:VIDCOMBO_DEV_VERSION) { $env:VIDCOMBO_DEV_VERSION } else { '1.7.1' } }
}
$appVersion = if ($env:APP_VERSION) { $env:APP_VERSION } else { $defaultVersion }

Write-Host ''
Write-Host ('=' * 72)
Write-Host ("dev_windows.ps1: brand={0} mode={1} app_version={2}" -f $Brand, $Mode, $appVersion)
Write-Host ('=' * 72)
Write-Host ''

# Step 1 — Switch brand config (icons, CMakeLists, brand_config.h, etc.)
# set_brand.sh is bash; on Windows we resolve git-bash explicitly so this
# works whether or not the caller has bash on PATH.
Write-Host "[1/2] Switching brand to $Brand..." -ForegroundColor Cyan
$bashCandidates = @(
    (Get-Command bash -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe'
)
$bashExe = $bashCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bashExe) {
    Write-Error "Could not locate bash.exe (looked for it on PATH and under Program Files\Git). Install Git for Windows or run set_brand.sh manually first."
    exit 2
}
& $bashExe (Join-Path $ScriptDir 'set_brand.sh') $Brand
if ($LASTEXITCODE -ne 0) {
    Write-Error "set_brand.sh failed for $Brand"
    exit 2
}
Write-Host ''

# Auto-clean when the build cache was produced by a different brand.
# CMake bakes BINARY_NAME (= brand exe name) into its generated build
# files, so a stale cache from the other brand makes the generator
# expression `$<TARGET_FILE_DIR:<other>>` unresolvable and the build
# aborts. Detect by checking which brand exe (or .vcxproj) is on disk.
$buildWindows = Join-Path $RepoRoot 'build\windows'
$expectedExe = if ($Brand -eq 'ssvid') { 'ssvid.exe' } else { 'vidcombo.exe' }
$otherExe = if ($Brand -eq 'ssvid') { 'vidcombo.exe' } else { 'ssvid.exe' }
$existingExe = Join-Path $buildWindows ("x64\runner\$(if ($Mode -eq 'release') { 'Release' } else { 'Debug' })\$otherExe")
$existingProject = Join-Path $buildWindows ("x64\runner\$($otherExe -replace '\.exe$','').vcxproj")
$brandMismatch = (Test-Path $existingExe) -or (Test-Path $existingProject)
if ($env:CLEAN -eq '1' -or $brandMismatch) {
    if ($brandMismatch) {
        Write-Host "Detected build cache from the other brand — cleaning build\windows to avoid CMake cache mismatch..." -ForegroundColor Yellow
    } else {
        Write-Host "CLEAN=1 set — removing build\windows..." -ForegroundColor Yellow
    }
    Remove-Item -Recurse -Force $buildWindows -ErrorAction SilentlyContinue
}

# Step 2 — Flutter build with brand + version override
Write-Host "[2/2] Building Flutter Windows $Mode for $Brand..." -ForegroundColor Cyan
Push-Location $RepoRoot
try {
    $defines = @(
        "--dart-define=BRAND=$Brand",
        "--dart-define=APP_VERSION=$appVersion"
    )
    if ($env:SENTRY_DSN) {
        $defines += "--dart-define=SENTRY_DSN=$env:SENTRY_DSN"
    }
    $modeFlag = if ($Mode -eq 'release') { '--release' } else { '--debug' }
    & flutter build windows $modeFlag @defines
    if ($LASTEXITCODE -ne 0) {
        Write-Error "flutter build windows failed (exit $LASTEXITCODE)"
        exit 2
    }
} finally {
    Pop-Location
}

# Verify exe present
$modeDir = if ($Mode -eq 'release') { 'Release' } else { 'Debug' }
$exeName = if ($Brand -eq 'ssvid') { 'ssvid.exe' } else { 'vidcombo.exe' }
$exePath = Join-Path $RepoRoot ("build\windows\x64\runner\$modeDir\$exeName")
if (-not (Test-Path $exePath)) {
    Write-Error "Expected exe missing after build: $exePath"
    exit 2
}

Write-Host ''
Write-Host ('=' * 72)
Write-Host ("Build OK: {0}" -f $exePath) -ForegroundColor Green
Write-Host ("Size:     {0:N0} bytes" -f (Get-Item $exePath).Length)
Write-Host ''
Write-Host "Next steps:" -ForegroundColor Cyan
if ($Mode -eq 'release') {
    Write-Host "  Smoke gate:     pwsh -File scripts\windows_bundle_smoke.ps1 -Brand $Brand -Mode Release -StrictExit"
    Write-Host "  Installer:      & 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' /DMyAppVersion=$appVersion scripts\installer_windows.iss"
}
Write-Host ('=' * 72)
exit 0
