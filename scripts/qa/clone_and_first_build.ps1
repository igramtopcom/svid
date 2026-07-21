# clone_and_first_build.ps1
#
# Phase B + C of the Windows build-lab setup.
# Clones svid-desktop into C:\Dev\snakeloader, checks out the requested
# branch, runs the full Flutter + Rust + Inno build pipeline for the
# requested brand. Idempotent: re-runs do `git fetch + reset` instead of
# re-cloning, and skip already-built native libs unless --Clean given.
#
# Usage:
#   pwsh -File clone_and_first_build.ps1 -Brand svid
#   pwsh -File clone_and_first_build.ps1 -Brand vidcombo -Branch main
#   pwsh -File clone_and_first_build.ps1 -Brand svid -Clean

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('svid', 'vidcombo')]
    [string]$Brand,

    [string]$Branch = 'feature/floating-capture-v2.2-state-machine',

    [string]$RepoUrl = 'https://github.com/mydinh-studio/svid-desktop.git',

    [string]$RepoDir = 'C:\Dev\snakeloader',

    [switch]$Clean,

    [switch]$SkipBuild,

    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'

$LOG_DIR = 'C:\QA\Snakeloader\logs'
$LOG_FILE = Join-Path $LOG_DIR ("build-{0}-{1:yyyyMMdd-HHmmss}.log" -f $Brand, (Get-Date))
New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null

function Log {
    param([string]$Msg, [string]$Color = 'Cyan')
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LOG_FILE -Value $line -Encoding ASCII
}

function Run {
    param([string]$Cmd, [string]$WorkingDir = $PWD.Path, [switch]$AllowFail)
    Log "  $> $Cmd" 'DarkGray'
    Push-Location $WorkingDir
    try {
        $out = & cmd /c "$Cmd 2>&1"
        $rc = $LASTEXITCODE
        $out | ForEach-Object { Add-Content -Path $LOG_FILE -Value $_ -Encoding ASCII }
        if ($rc -ne 0 -and -not $AllowFail) {
            Log "FAIL exit=$rc : $Cmd" 'Red'
            throw "Command failed (exit $rc): $Cmd"
        }
        return $out
    }
    finally {
        Pop-Location
    }
}

Log "=== clone_and_first_build.ps1 brand=$Brand branch=$Branch ===" 'Magenta'
Log "Log: $LOG_FILE" 'Gray'

# -------------------------------------------------------------------------
# Phase B: clone + checkout
# -------------------------------------------------------------------------

$parent = Split-Path -Parent $RepoDir
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

if (Test-Path (Join-Path $RepoDir '.git')) {
    Log "Repo exists -> git fetch + reset to origin/$Branch"
    Run "git fetch origin" $RepoDir
    Run "git checkout $Branch" $RepoDir
    Run "git reset --hard origin/$Branch" $RepoDir
}
else {
    Log "Cloning $RepoUrl -> $RepoDir"
    # gh auth status check (warn only — public repo may clone anonymously,
    # private repo will fail and prompt for gh auth login).
    $authProbe = & cmd /c 'gh auth status 2>&1'
    if ($LASTEXITCODE -ne 0) {
        Log "  gh not authenticated. If repo is private, run:  gh auth login" 'Yellow'
        Log "  Continuing anyway — will fail at git clone if private." 'Yellow'
    }
    Run "git clone --branch $Branch $RepoUrl `"$RepoDir`"" $parent
}

# Verify branch
$actualBranch = (Run "git rev-parse --abbrev-ref HEAD" $RepoDir | Select-Object -Last 1).Trim()
$actualSha = (Run "git rev-parse --short HEAD" $RepoDir | Select-Object -Last 1).Trim()
Log "Repo: $RepoDir at $actualBranch ($actualSha)" 'Green'

# -------------------------------------------------------------------------
# Phase C: build
# -------------------------------------------------------------------------

if ($SkipBuild) {
    Log "SkipBuild set — stopping after clone." 'Yellow'
    exit 0
}

Push-Location $RepoDir
try {
    # Verify FVM + pinned Flutter version
    Run "fvm install" "" -AllowFail | Out-Null
    Run "fvm flutter --version" $RepoDir | Out-Null

    if ($Clean) {
        Log "Clean build requested"
        Run "fvm flutter clean" $RepoDir -AllowFail | Out-Null
        if (Test-Path "$RepoDir\native\target") {
            Log "  Removing native\target..."
            Remove-Item -Recurse -Force "$RepoDir\native\target"
        }
    }

    Log "Phase C1: flutter pub get"
    Run "fvm flutter pub get" $RepoDir

    Log "Phase C2: build_runner"
    Run "fvm dart run build_runner build --delete-conflicting-outputs" $RepoDir

    # Brand config — set_brand.sh is bash. Windows ships Git Bash with Git for Windows,
    # so we shell out to bash explicitly.
    $gitBash = "${env:ProgramFiles}\Git\bin\bash.exe"
    if (Test-Path $gitBash) {
        Log "Phase C3: set_brand $Brand (via Git Bash)"
        & $gitBash -c "cd '$($RepoDir -replace '\\','/')' && bash scripts/set_brand.sh $Brand" 2>&1 |
            Tee-Object -FilePath $LOG_FILE -Append | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "set_brand.sh failed (exit $LASTEXITCODE)" }
    }
    else {
        Log "Git Bash not found at $gitBash — falling back to manual brand stamp" 'Yellow'
        # Fallback: regenerate windows brand_config.h manually
        # (Documented in scripts/set_brand.sh:108-130)
        throw "Git Bash missing. Reinstall Git for Windows or extend this script with native brand stamp."
    }

    Log "Phase C4: Rust release build (x86_64-pc-windows-msvc)"
    Run "cargo build --release --features telemetry --target x86_64-pc-windows-msvc" "$RepoDir\native"

    # Copy native.dll to where flutter build windows expects it
    $nativeDll = "$RepoDir\native\target\x86_64-pc-windows-msvc\release\native.dll"
    if (Test-Path $nativeDll) {
        Copy-Item -Force $nativeDll "$RepoDir\windows\native.dll"
        Log "  Copied native.dll -> windows\native.dll" 'Green'
    }
    else {
        throw "native.dll not produced at $nativeDll"
    }

    Log "Phase C5: flutter build windows --release"
    Run "fvm flutter build windows --release --dart-define=BRAND=$Brand" $RepoDir

    # Find the built bundle
    $bundleDir = "$RepoDir\build\windows\x64\runner\Release"
    if (-not (Test-Path $bundleDir)) {
        $bundleDir = "$RepoDir\build\windows\runner\Release"  # older Flutter layout
    }
    Log "Bundle: $bundleDir" 'Green'

    if (-not $SkipInstaller) {
        Log "Phase C6: Inno Setup compile (unsigned)"

        # Pull version from pubspec.yaml
        $pubspec = Get-Content "$RepoDir\pubspec.yaml" -Raw
        if ($pubspec -match 'version:\s*(\d+\.\d+\.\d+)') {
            $version = $Matches[1]
        }
        else {
            throw "Cannot parse version: from pubspec.yaml"
        }
        Log "  Version: $version"

        # Compose iscc args (mirror release.yml lines 511-516)
        if ($Brand -eq 'vidcombo') {
            $isccArgs = @(
                "/DMyAppVersion=$version", '/DMyAppName=VidCombo',
                '/DMyAppExeName=vidcombo.exe', '/DMyAppPublisher=VidCombo',
                '/DMyAppCompany=Bui Xuan Mai', '/DMyAppProductName=VidCombo Desktop',
                '/DMyAppFileDescription=VidCombo Desktop Installer',
                '/DMyAppCopyright=Copyright (C) 2026 Bui Xuan Mai. All rights reserved.',
                '/DMyAppURL=https://vidcombo.net',
                '/DMyAppId={{C6BC5050-3D98-47F7-8F1E-3DC53963381A}',
                '/DMyUrlScheme=vidcombo',
                '/DMyAppUserModelId=com.tinasoft.vidcombo.desktop',
                "/DMyBuildSource=$bundleDir",
                'scripts\installer_windows.iss'
            )
        }
        else {
            $isccArgs = @(
                "/DMyAppVersion=$version", '/DMyAppName=Svid',
                '/DMyAppExeName=svid.exe', '/DMyAppPublisher=Svid',
                '/DMyAppCompany=Bui Xuan Mai', '/DMyAppProductName=Svid Desktop',
                '/DMyAppFileDescription=Svid Desktop Installer',
                '/DMyAppCopyright=Copyright (C) 2026 Bui Xuan Mai. All rights reserved.',
                '/DMyAppURL=https://svid.app',
                '/DMyUrlScheme=svid',
                '/DMyAppUserModelId=com.svid.app',
                "/DMyBuildSource=$bundleDir",
                'scripts\installer_windows.iss'
            )
        }
        $iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
        if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
        if (-not (Test-Path $iscc)) { throw "iscc not found. Re-run bootstrap_windows_build_lab.ps1" }
        Log "  ISCC: $iscc"
        & $iscc @isccArgs 2>&1 | Tee-Object -FilePath $LOG_FILE -Append | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "iscc exit $LASTEXITCODE" }

        # Locate produced installer
        $installer = Get-ChildItem -Path "$RepoDir\dist" -Filter '*-windows-x64-setup.exe' -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($installer) {
            Log "Installer: $($installer.FullName) ($([math]::Round($installer.Length/1MB,2)) MB)" 'Green'
            # Stage into C:\QA\Snakeloader\artifacts for smoke runs
            $stagedDir = 'C:\QA\Snakeloader\artifacts'
            New-Item -ItemType Directory -Force -Path $stagedDir | Out-Null
            Copy-Item -Force $installer.FullName $stagedDir
            Log "  Staged -> $stagedDir\$($installer.Name)" 'Green'
        }
        else {
            Log "WARN: installer not found in dist\ — check iscc OutputDir" 'Yellow'
        }
    }
}
finally {
    Pop-Location
}

Log "=== build complete ($Brand) ===" 'Magenta'
exit 0
