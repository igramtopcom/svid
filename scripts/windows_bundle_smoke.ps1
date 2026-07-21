# scripts/windows_bundle_smoke.ps1
#
# Bundle-level Windows smoke test for Svid Desktop.
#
# What this is (and is NOT):
#   * IS: a fast, deterministic check that a Flutter Windows BUNDLE
#     (build/windows/x64/runner/{Debug|Release}/...) is launchable,
#     branded correctly, has the right native dependencies, and reaches
#     "first_frame_presented" without fatal log lines.
#   * IS NOT: an installer test. For signed-installer + Smart App Control
#     + Inno [Run] + legacy migration coverage, see scripts/windows_qa_smoke.ps1
#     -- that script remains the CI release gate.
#
# Why both: the installer smoke needs YubiKey signing + Inno output and is
# expensive to run locally. This bundle smoke runs against an unsigned
# debug or release bundle in seconds, so agents (and humans) get a tight
# inner-loop signal on Windows.
#
# Coverage (scenario id naming follows windows_qa_smoke.ps1 conventions
# with a B prefix for "bundle"):
#   B0  Bundle root exists; exe + native.dll + flutter_windows.dll present.
#   B1  Brand identity: exe filename matches BRAND, VersionInfo ProductName
#       + FileDescription + CompanyName match BRAND. Release builds additionally
#       delegate to verify_windows_metadata.ps1 (the canonical metadata gate).
#   B2  Brand assets present + brand_config.h matches BRAND.
#   B3  flutter_assets present (AssetManifest.json + a known platform icon).
#   B4  Launch + ready-marker: spawn the exe, wait for "first_frame_presented"
#       in the brand-scoped log file, scan for FATAL lines, terminate cleanly.
#       Skipped when -NoLaunch is passed (CI without a desktop session).
#
# Usage:
#   pwsh -File scripts/windows_bundle_smoke.ps1 -Brand svid -Mode Debug
#   pwsh -File scripts/windows_bundle_smoke.ps1 -Brand vidcombo -Mode Release `
#        -LaunchTimeoutSeconds 90
#   pwsh -File scripts/windows_bundle_smoke.ps1 -Brand svid -Mode Release -DryRun
#   pwsh -File scripts/windows_bundle_smoke.ps1 -Brand svid -Mode Debug -NoLaunch
#
# Exit codes:
#   0  all scenarios PASS or WARN/SKIP (no FAIL)
#   1  any scenario FAIL
#   2  parameter / environment problem (bundle not found, etc.)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('svid', 'vidcombo')]
    [string]$Brand,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Debug', 'Release')]
    [string]$Mode,

    [string]$BundleDir,

    [int]$LaunchTimeoutSeconds = 60,

    [switch]$NoLaunch,

    [switch]$DryRun,

    # When set, B4.5 promotes a "had to Kill the process" outcome from WARN
    # to FAIL. Default is WARN because the bundle smoke's primary intent is
    # boot, not graceful-shutdown -- but release sweeps should pass -StrictExit
    # to enforce clean termination as a gate.
    [switch]$StrictExit
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $ScriptRoot '..')).Path

# ----------------------------------------------------------------------------
# Result table -- shared format with scripts/windows_qa_smoke.ps1
# ----------------------------------------------------------------------------
$results = [System.Collections.Generic.List[object]]::new()

function Record-Result {
    param(
        [string]$Id,
        [string]$Description,
        [ValidateSet('PASS', 'FAIL', 'SKIP', 'WARN')][string]$Status,
        [string]$Detail = ''
    )
    $results.Add([pscustomobject]@{
        Id          = $Id
        Description = $Description
        Status      = $Status
        Detail      = $Detail
    })
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1} -- {2}" -f $Status, $Id, $Description) -ForegroundColor $color
    if ($Detail) {
        Write-Host ("         {0}" -f $Detail) -ForegroundColor DarkGray
    }
}

function Exit-WithSummary {
    param([int]$DefaultExitCode = 0)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host ("Windows bundle smoke -- {0} / {1}" -f $Brand, $Mode)
    Write-Host ('=' * 72)
    $byStatus = $results | Group-Object Status
    foreach ($g in $byStatus) {
        Write-Host ("  {0,-4} {1}" -f $g.Name, $g.Count)
    }
    $failing = ($results | Where-Object Status -eq 'FAIL').Count
    if ($failing -gt 0) { exit 1 }
    exit $DefaultExitCode
}

# ----------------------------------------------------------------------------
# Brand expectations -- single source of truth lives in scripts/set_brand.sh.
# Keep these in sync when set_brand.sh changes.
# ----------------------------------------------------------------------------
if ($Brand -eq 'vidcombo') {
    $expectedExeName       = 'vidcombo.exe'
    $expectedProductName   = 'VidCombo Desktop'
    $expectedDescription   = 'VidCombo Desktop'
    $expectedCompanyName   = 'Bui Xuan Mai'
    $expectedBrandNameHdr  = 'VidCombo'
    $expectedAppSupportDir = 'VidCombo Desktop'
    $brandLogPrefix        = 'vidcombo'
} else {
    $expectedExeName       = 'svid.exe'
    $expectedProductName   = 'Svid Desktop'
    $expectedDescription   = 'Svid Desktop'
    $expectedCompanyName   = 'Bui Xuan Mai'
    $expectedBrandNameHdr  = 'Svid'
    $expectedAppSupportDir = 'Svid Desktop'
    $brandLogPrefix        = 'svid'
}

if (-not $BundleDir) {
    $BundleDir = Join-Path $RepoRoot ("build/windows/x64/runner/" + $Mode)
}
$BundleDir = [System.IO.Path]::GetFullPath($BundleDir)

Write-Host ''
Write-Host ('=' * 72)
Write-Host ("Windows bundle smoke -- brand={0} mode={1}" -f $Brand, $Mode)
Write-Host ("  bundle: {0}" -f $BundleDir)
Write-Host ("  launch: {0}" -f ($(if ($NoLaunch) { 'skipped (-NoLaunch)' } else { "timeout ${LaunchTimeoutSeconds}s" })))
Write-Host ('=' * 72)
Write-Host ''

if ($DryRun) {
    Record-Result 'B?.dry' 'Dry-run -- printed plan, no checks executed' 'SKIP'
    Exit-WithSummary 0
}

# ============================================================================
# B0 Bundle root + required binaries
# ============================================================================
if (-not (Test-Path $BundleDir)) {
    Record-Result 'B0.1' 'Bundle directory exists' 'FAIL' "Not found: $BundleDir. Run scripts/set_brand.sh $Brand && fvm flutter build windows --$($Mode.ToLower()) --dart-define=BRAND=$Brand"
    Exit-WithSummary 2
}
Record-Result 'B0.1' 'Bundle directory exists' 'PASS' $BundleDir

$exePath = Join-Path $BundleDir $expectedExeName
if (-not (Test-Path $exePath)) {
    # Possible cause: brand mismatch -- the bundle was built with the *other* brand.
    $otherExe = if ($Brand -eq 'svid') { 'vidcombo.exe' } else { 'svid.exe' }
    $otherFound = Test-Path (Join-Path $BundleDir $otherExe)
    $hint = if ($otherFound) {
        "Found '$otherExe' instead. Run 'scripts/set_brand.sh $Brand' before building, or pass --dart-define=BRAND=$Brand to flutter build."
    } else {
        "Expected $expectedExeName at $exePath -- bundle may be stale or for a different brand."
    }
    Record-Result 'B0.2' 'Brand exe present in bundle' 'FAIL' $hint
    Exit-WithSummary 1
}
Record-Result 'B0.2' 'Brand exe present in bundle' 'PASS' $expectedExeName

# Required native dependencies. These must ride with every Flutter Windows
# bundle; missing any one => runtime DLL-not-found crash at startup.
$requiredDlls = @(
    @{ Name = 'native.dll';            Reason = 'Rust FFI (flutter_rust_bridge)' },
    @{ Name = 'flutter_windows.dll';   Reason = 'Flutter engine on Windows' },
    @{ Name = 'WebView2Loader.dll';    Reason = 'In-app browser + auth WebViews' },
    @{ Name = 'msvcp140.dll';          Reason = 'MSVC C++ standard library (Carl-class app-local runtime)' },
    @{ Name = 'vcruntime140.dll';      Reason = 'MSVC C runtime (Carl-class app-local runtime)' },
    @{ Name = 'vcruntime140_1.dll';    Reason = 'MSVC C++ EH runtime (Carl-class pre-launch loader failure)' }
)
foreach ($dll in $requiredDlls) {
    $dllPath = Join-Path $BundleDir $dll.Name
    if (Test-Path $dllPath) {
        $size = (Get-Item -LiteralPath $dllPath).Length
        Record-Result ('B0.3.' + $dll.Name) ("Required DLL present -- " + $dll.Reason) 'PASS' ("{0} ({1:N0} bytes)" -f $dll.Name, $size)
    } else {
        Record-Result ('B0.3.' + $dll.Name) ("Required DLL missing -- " + $dll.Reason) 'FAIL' "Expected at $dllPath"
    }
}

# ============================================================================
# B1 Brand identity (VersionInfo + filename + metadata gate)
# ============================================================================
$versionInfo = (Get-Item -LiteralPath $exePath).VersionInfo

function Compare-Field {
    param([string]$Field, [string]$Actual, [string]$Expected, [string]$Id)
    if ([string]::IsNullOrWhiteSpace($Actual)) {
        Record-Result $Id "VersionInfo $Field set" 'FAIL' "Field is empty"
        return
    }
    if ($Actual.TrimEnd() -ne $Expected.TrimEnd()) {
        Record-Result $Id "VersionInfo $Field matches brand" 'FAIL' "expected='$Expected' actual='$Actual'"
        return
    }
    Record-Result $Id "VersionInfo $Field matches brand" 'PASS' $Actual
}

Compare-Field 'ProductName'    $versionInfo.ProductName    $expectedProductName 'B1.1'
Compare-Field 'FileDescription' $versionInfo.FileDescription $expectedDescription 'B1.2'
Compare-Field 'CompanyName'    $versionInfo.CompanyName    $expectedCompanyName 'B1.3'

# For Release builds, defer to the canonical metadata gate. It enforces a
# stricter set including AppUserModelID embedded as UTF-16. We skip this for
# Debug because debug bundles intentionally don't get the windres metadata
# pipeline (the runner.rc inputs are wired into Release builds only).
if ($Mode -eq 'Release') {
    $verifyMetadata = Join-Path $ScriptRoot 'verify_windows_metadata.ps1'
    if (Test-Path $verifyMetadata) {
        try {
            & pwsh -NoProfile -File $verifyMetadata -Brand $Brand -ExePath $exePath
            if ($LASTEXITCODE -eq 0) {
                Record-Result 'B1.4' 'verify_windows_metadata.ps1 passes' 'PASS'
            } else {
                Record-Result 'B1.4' 'verify_windows_metadata.ps1 passes' 'FAIL' "Exit code $LASTEXITCODE"
            }
        } catch {
            Record-Result 'B1.4' 'verify_windows_metadata.ps1 passes' 'FAIL' $_.Exception.Message
        }
    } else {
        Record-Result 'B1.4' 'verify_windows_metadata.ps1 available' 'WARN' 'Script not found; delegated metadata check skipped'
    }
} else {
    Record-Result 'B1.4' 'verify_windows_metadata.ps1 (Release-only)' 'SKIP' 'Debug bundles skip windres metadata gate'
}

# ============================================================================
# B2 Brand assets + brand_config.h
# ============================================================================
$brandIcon = Join-Path $RepoRoot ("assets/brands/$Brand/app_icon.ico")
if (Test-Path $brandIcon) {
    Record-Result 'B2.1' 'Brand app icon present in assets/brands/' 'PASS' $brandIcon
} else {
    Record-Result 'B2.1' 'Brand app icon present in assets/brands/' 'FAIL' "Missing $brandIcon"
}

$brandHeader = Join-Path $RepoRoot 'windows/runner/brand_config.h'
if (Test-Path $brandHeader) {
    $headerContent = Get-Content -LiteralPath $brandHeader -Raw
    $expectedDefine = "#define BRAND_NAME `"$expectedBrandNameHdr`""
    if ($headerContent -match [regex]::Escape($expectedDefine)) {
        Record-Result 'B2.2' 'windows/runner/brand_config.h matches brand' 'PASS' "$expectedDefine"
    } else {
        # Pull the actual BRAND_NAME for diagnostic context.
        $m = [regex]::Match($headerContent, '#define\s+BRAND_NAME\s+"([^"]+)"')
        $actual = if ($m.Success) { $m.Groups[1].Value } else { '<not found>' }
        Record-Result 'B2.2' 'windows/runner/brand_config.h matches brand' 'FAIL' "expected BRAND_NAME=$expectedBrandNameHdr, header has BRAND_NAME=$actual. Run scripts/set_brand.sh $Brand and rebuild."
    }
} else {
    Record-Result 'B2.2' 'windows/runner/brand_config.h exists' 'FAIL' "Run scripts/set_brand.sh $Brand to generate"
}

# Mirror the runner-resource icon check that windres consumes on Release builds.
$runnerIcon = Join-Path $RepoRoot 'windows/runner/resources/app_icon.ico'
if (Test-Path $runnerIcon) {
    if (Test-Path $brandIcon) {
        $runnerHash = (Get-FileHash -LiteralPath $runnerIcon -Algorithm SHA256).Hash
        $brandHash = (Get-FileHash -LiteralPath $brandIcon -Algorithm SHA256).Hash
        if ($runnerHash -eq $brandHash) {
            Record-Result 'B2.3' 'windows/runner/resources/app_icon.ico matches brand' 'PASS' $runnerIcon
        } else {
            Record-Result 'B2.3' 'windows/runner/resources/app_icon.ico matches brand' 'FAIL' "Run scripts/set_brand.sh $Brand before building. runner=$runnerHash brand=$brandHash"
        }
    } else {
        Record-Result 'B2.3' 'windows/runner/resources/app_icon.ico matches brand' 'FAIL' "Missing brand icon: $brandIcon"
    }
} else {
    Record-Result 'B2.3' 'windows/runner/resources/app_icon.ico matches brand' 'FAIL' 'Run scripts/set_brand.sh to copy from assets/brands/'
}

# ============================================================================
# B3 flutter_assets sanity
# ============================================================================
$flutterAssets = Join-Path $BundleDir 'data\flutter_assets'
if (-not (Test-Path $flutterAssets)) {
    Record-Result 'B3.1' 'data/flutter_assets exists' 'FAIL' "Missing $flutterAssets -- bundle is incomplete (flutter build did not run, or output dir is wrong)"
} else {
    Record-Result 'B3.1' 'data/flutter_assets exists' 'PASS'

    $manifest = Join-Path $flutterAssets 'AssetManifest.json'
    if (Test-Path $manifest) {
        Record-Result 'B3.2' 'AssetManifest.json present' 'PASS'
    } else {
        Record-Result 'B3.2' 'AssetManifest.json present' 'FAIL'
    }

    # Spot-check one platform icon -- if this is missing the in-app browser
    # platform chips fall back to placeholder squares. Same set that
    # verify_windows_flutter_assets.sh enforces, but bundle-local.
    $youtubeIcon = Join-Path $flutterAssets 'assets/icons/platforms/youtube.svg'
    if (Test-Path $youtubeIcon) {
        Record-Result 'B3.3' 'Platform icon assets shipped (spot-check youtube.svg)' 'PASS'
    } else {
        Record-Result 'B3.3' 'Platform icon assets shipped (spot-check youtube.svg)' 'WARN' "Missing $youtubeIcon -- run scripts/verify_windows_flutter_assets.sh for full list"
    }
}

# ============================================================================
# B4 Launch + ready-marker
# ============================================================================
if ($NoLaunch) {
    Record-Result 'B4.0' 'Launch test' 'SKIP' '-NoLaunch flag set'
    Exit-WithSummary 0
}

# AppData path mirror of lib/core/logging/app_logger.dart line 138-154.
# getApplicationSupportDirectory() on Windows resolves to
# %APPDATA%\<CompanyName>\<ProductName>\, and the logger writes to
# <that>/logs/<brand>_<YYYY-MM-DD>.log.
$dateStr = (Get-Date).ToString('yyyy-MM-dd')
$logDir = Join-Path $env:APPDATA ("{0}\{1}\logs" -f $expectedCompanyName, $expectedAppSupportDir)
$logFile = Join-Path $logDir ("{0}_{1}.log" -f $brandLogPrefix, $dateStr)
$preLaunchSize = if (Test-Path $logFile) { (Get-Item -LiteralPath $logFile).Length } else { 0 }
$werBaseline = Get-Date

Write-Host ("[INFO] Log target: {0} (pre-size={1})" -f $logFile, $preLaunchSize)

$proc = $null
try {
    $proc = Start-Process -FilePath $exePath -WorkingDirectory $BundleDir -PassThru -WindowStyle Minimized -ErrorAction Stop
    Record-Result 'B4.1' "Launched $expectedExeName (pid $($proc.Id))" 'PASS'
} catch {
    Record-Result 'B4.1' "Launch $expectedExeName" 'FAIL' $_.Exception.Message
    Exit-WithSummary 1
}

# Wait for "first_frame_presented" log line (the canonical ready signal --
# emitted by lib/main.dart line 481 via StartupProfiler.mark()). If it
# doesn't appear within $LaunchTimeoutSeconds, the app either crashed in
# early init or the log file path is wrong.
$deadline = (Get-Date).AddSeconds($LaunchTimeoutSeconds)
$readyMarker = $false
$startingMarker = $false
$lastSize = $preLaunchSize
$crashed = $false
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) {
        $crashed = $true
        break
    }
    if (Test-Path $logFile) {
        $size = (Get-Item -LiteralPath $logFile).Length
        if ($size -gt $lastSize) {
            $tail = Get-Content -LiteralPath $logFile -Tail 400 -ErrorAction SilentlyContinue
            if ($tail -match 'starting\.\.\.') { $startingMarker = $true }
            if ($tail -match 'first_frame_presented' -or $tail -match 'first_frame:') {
                $readyMarker = $true
                break
            }
            $lastSize = $size
        }
    }
    Start-Sleep -Milliseconds 500
}

if ($crashed) {
    $exit = $proc.ExitCode
    Record-Result 'B4.2' 'Process stays alive through startup' 'FAIL' "Process exited early with code $exit"
    if (Test-Path $logFile) {
        Write-Host '--- Last 40 log lines ---' -ForegroundColor DarkGray
        Get-Content -LiteralPath $logFile -Tail 40 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }
    }
    Exit-WithSummary 1
}

if ($startingMarker) {
    Record-Result 'B4.2' "'<brand> starting...' marker logged" 'PASS'
} else {
    Record-Result 'B4.2' "'<brand> starting...' marker logged" 'WARN' "Marker not seen -- check log file path resolution. Log target: $logFile"
}

if ($readyMarker) {
    Record-Result 'B4.3' "'first_frame_presented' marker reached" 'PASS'
} else {
    Record-Result 'B4.3' "'first_frame_presented' marker reached" 'FAIL' "Timed out after ${LaunchTimeoutSeconds}s waiting for first frame. App may be hung in early init."
}

# Fatal-line scan. The `logger` package PrettyPrinter does NOT write the
# string 'FATAL' by default in our config (printEmojis=true, but
# levelEmojis[Level.fatal] is '' in logger 2.x). ANSI colors are stripped
# before write (see _AppLogOutput line 203). So the only reliable signal
# is the message-text emitted by `appLogger.fatal(...)` at each call site.
#
# Known fatal call sites in this app (grep `appLogger.fatal(` under lib/):
#   lib/main.dart:273  'CRITICAL: Rust bridge init failed ...'
#   lib/main.dart:571  'Failed to initialize Rust bridge'
#   lib/main.dart:606  'Failed to initialize DownloadManager'
#
# Extend $fatalPatterns when adding new fatal call sites in main-thread
# boot code. We deliberately do NOT scan for 'Error:' or 'Stack Trace:'
# because those also appear on `appLogger.error(...)` and would cause
# false positives.
$fatalPatterns = @(
    'CRITICAL:',
    'Failed to initialize Rust bridge',
    'Failed to initialize DownloadManager',
    '\[FATAL\]',         # belt-and-suspenders for future logger config changes
    '\bFATAL\b'
)
if (Test-Path $logFile) {
    $stream = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
    try {
        if ($stream.Length -gt $preLaunchSize) {
            $stream.Seek($preLaunchSize, 'Begin') | Out-Null
            $reader = New-Object System.IO.StreamReader($stream)
            $newContent = $reader.ReadToEnd()
            $combined = '(' + ($fatalPatterns -join ')|(') + ')'
            $fatalLines = $newContent -split "`n" | Where-Object { $_ -match $combined }
            if ($fatalLines.Count -gt 0) {
                $sample = ($fatalLines | Select-Object -First 3) -join ' | '
                Record-Result 'B4.4' 'No fatal markers in startup log' 'FAIL' $sample
            } else {
                Record-Result 'B4.4' 'No fatal markers in startup log' 'PASS' ("matched none of: " + ($fatalPatterns -join ', '))
            }
        } else {
            Record-Result 'B4.4' 'No fatal markers in startup log' 'WARN' 'Log file did not grow during launch -- path resolution may be wrong (see B4.2 detail)'
        }
    } finally {
        $stream.Dispose()
    }
} else {
    Record-Result 'B4.4' 'No fatal markers in startup log' 'WARN' "Log file not found at $logFile -- the app may have crashed before _initLogFile ran"
}

# Close behaviour. CPO standard (Discord/Slack/Telegram pattern): X / Alt+F4
# / CloseMainWindow hide the window to tray and KEEP the process running so
# downloads continue. Only an explicit tray "Quit" menu actually terminates.
# So this gate now asserts: CloseMainWindow → process stays alive + window
# hidden (= hide-to-tray working). The legacy "process must exit within 5s"
# behaviour was the pre-close-to-tray invariant and is no longer valid.
#
# A separate B4.7 force-kills the process so the smoke run leaves the system
# clean for the next iteration; that path also re-checks WER to catch any
# crash-on-kernel-kill.
try {
    if ($proc.HasExited) {
        # Pre-CloseMainWindow exit means the app crashed or quit by itself
        # during startup — that's the failure case we care about.
        Record-Result 'B4.5' 'Window hides to tray on CloseMainWindow' 'FAIL' "Process exited unexpectedly before CloseMainWindow (code $($proc.ExitCode))"
    } else {
        $proc.CloseMainWindow() | Out-Null
        # Give the Dart-side onWindowClose listener a moment to call
        # windowManager.hide(). Don't wait for exit — exit is the WRONG
        # outcome here.
        Start-Sleep -Milliseconds 1500
        $proc.Refresh()
        if ($proc.HasExited) {
            # Process exited on CloseMainWindow means the close-to-tray
            # branch was bypassed, or _shouldQuit was somehow set, or the
            # close hung and a downstream path force-exited.
            $exitStatus = if ($StrictExit) { 'FAIL' } else { 'WARN' }
            Record-Result 'B4.5' 'Window hides to tray on CloseMainWindow' $exitStatus "Process exited on CloseMainWindow (exit $($proc.ExitCode)) -- expected hide-to-tray (process alive, window hidden)"
        } else {
            Record-Result 'B4.5' 'Window hides to tray on CloseMainWindow' 'PASS' "Process alive after CloseMainWindow (hide-to-tray working)"
        }
    }
} catch {
    Record-Result 'B4.5' 'Window hides to tray on CloseMainWindow' 'WARN' $_.Exception.Message
}

# Force-kill cleanup so the smoke run doesn't leave a hidden process
# accumulating across iterations. This is also a stress test: did the
# hidden process develop any crash during its brief hidden lifetime?
try {
    if (-not $proc.HasExited) {
        $proc.Kill()
        $proc.WaitForExit(5000) | Out-Null
        Record-Result 'B4.5b' 'Force-kill of hidden process clean' 'PASS' 'Process terminated by Kill (cleanup for next iteration)'
    } else {
        Record-Result 'B4.5b' 'Force-kill of hidden process clean' 'SKIP' 'Process already exited'
    }
} catch {
    Record-Result 'B4.5b' 'Force-kill of hidden process clean' 'WARN' $_.Exception.Message
}

# Windows can report a process as terminated while the termination was actually
# an APPCRASH. Treat post-launch WER/Application Error records for this exe as
# a hard failure so crash-on-exit cannot pass as a clean close.
$werEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $werBaseline } -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.ProviderName -match 'Application Error|Windows Error Reporting') -and
        ($_.Message -match [regex]::Escape($expectedExeName))
    })
if ($werEvents.Count -gt 0) {
    $sample = $werEvents |
        Select-Object -First 3 |
        ForEach-Object {
            $message = ($_.Message -replace '\s+', ' ')
            "{0:o} {1}: {2}" -f $_.TimeCreated, $_.ProviderName, $message.Substring(0, [Math]::Min(260, $message.Length))
        }
    Record-Result 'B4.6' "No WER/AppCrash records for $expectedExeName" 'FAIL' ($sample -join ' | ')
} else {
    Record-Result 'B4.6' "No WER/AppCrash records for $expectedExeName" 'PASS'
}

Exit-WithSummary 0
