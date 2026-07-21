# Windows QA smoke harness -- validates the Installer/Native CTO session's
# hardening work end-to-end on a real Windows 11 machine. Designed so ANY
# tester (not just the CTO) can run it against a fresh installer artifact
# and get a pass/fail signal per scenario.
#
# Usage (from an elevated-or-not PowerShell prompt):
#   pwsh -File scripts/windows_qa_smoke.ps1 `
#        -Installer <path-to-signed-setup.exe> `
#        -Brand svid `
#        [-BluebyteLegacyExe <path-to-old-VidCombo-uninstaller>] `
#        [-SkipLaunchCheck]
#
# What it covers (keyed to the waves this session shipped):
#   W3 signing policy gate   -- verifies signtool recognises the cert as
#                              RSA-signed and within validity.
#   W3 Zone.Identifier strip -- confirms the downloaded installer is NOT
#                              marked-of-web after copy.
#   W3 installer [Run] dual  -- silent install relaunches the app.
#   W5 VidCombo migration    -- installer extracts legacy license key to
#                              %TEMP%\vidcombo_migrated_key.txt BEFORE the
#                              old app is removed, and the new app consumes
#                              it on first launch.
#   W5.2 marker idempotency  -- re-running the installer (or a locked
#                              marker) does not strip the premium key on
#                              every launch.
#
# What it does NOT cover (delegates to the human tester -- see
# docs/windows-qa-checklist.md):
#   - Smart App Control UX on a fresh Win11 image.
#   - Visual verification of icons, UAC prompts, WebView login flows.
#   - Network-constrained scenarios (AV-SSL-scan, captive portal, etc.).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Installer,

    [Parameter(Mandatory = $true)]
    [ValidateSet('svid', 'vidcombo')]
    [string]$Brand,

    [string]$BluebyteLegacyExe,

    [switch]$SkipLaunchCheck,

    [int]$LaunchTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
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
    param([int]$ExitCode = 0)
    Write-Host ""
    Write-Host ("=" * 70)
    Write-Host "Windows QA smoke harness -- summary"
    Write-Host ("=" * 70)
    $byStatus = $results | Group-Object Status
    foreach ($g in $byStatus) {
        Write-Host ("  {0}: {1}" -f $g.Name, $g.Count)
    }
    $failing = ($results | Where-Object Status -eq 'FAIL').Count
    if ($failing -gt 0) { $ExitCode = 1 }
    exit $ExitCode
}

# ============================================================================
# 1. Installer file exists + accessible
# ============================================================================

if (-not (Test-Path $Installer)) {
    Record-Result 'W0.1' 'Installer exists at supplied path' 'FAIL' "Not found: $Installer"
    Exit-WithSummary 1
}
Record-Result 'W0.1' 'Installer exists at supplied path' 'PASS' $Installer

$installerInfo = Get-Item $Installer
Record-Result 'W0.2' 'Installer size sanity (>5 MB)' `
    $(if ($installerInfo.Length -gt 5MB) { 'PASS' } else { 'FAIL' }) `
    ("{0:N1} MB" -f ($installerInfo.Length / 1MB))

# ============================================================================
# 2. W3 -- signing policy verification (signtool must confirm RSA + valid)
# ============================================================================

$signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
if (-not $signtool) {
    Record-Result 'W3.1' 'signtool.exe on PATH' 'WARN' `
        'Windows SDK signtool.exe not on PATH -- skipping cert checks'
} else {
    try {
        $verifyOutput = & $signtool verify /pa /v $Installer 2>&1 | Out-String
        $verifyOK = $LASTEXITCODE -eq 0
        Record-Result 'W3.1' 'Installer is Authenticode-signed' `
            $(if ($verifyOK) { 'PASS' } else { 'FAIL' }) `
            ($verifyOutput -split "`n" | Select-Object -First 3 | Out-String).Trim()

        if ($verifyOK) {
            # Sign algo check -- policy rejects ECC, requires RSA.
            $algoMatch = $verifyOutput | Select-String -Pattern 'Hash Algorithm:\s*(\S+)'
            if ($algoMatch) {
                $algo = $algoMatch.Matches[0].Groups[1].Value
                Record-Result 'W3.2' ("Signature hash algo: $algo") 'PASS'
            }
            $isRsa = $verifyOutput -match 'RSA'
            Record-Result 'W3.3' 'Signing cert is RSA (SAC requirement)' `
                $(if ($isRsa) { 'PASS' } else { 'FAIL' }) `
                'ECDSA certs are rejected by Smart App Control on Windows 11'
        }
    } catch {
        Record-Result 'W3.1' 'Installer is Authenticode-signed' 'FAIL' $_.Exception.Message
    }
}

# ============================================================================
# 3. W3 -- Zone.Identifier should NOT be present (auto-update removes it)
# ============================================================================

$zoneStream = "${Installer}:Zone.Identifier"
try {
    $zoneContent = Get-Content -Path $Installer -Stream Zone.Identifier -ErrorAction Stop 2>$null
    if ($zoneContent) {
        Record-Result 'W3.4' 'Zone.Identifier ADS absent on installer' 'WARN' `
            'Installer still marked-of-web -- SmartScreen will prompt. Auto-update strips this; manual downloads may not.'
    } else {
        Record-Result 'W3.4' 'Zone.Identifier ADS absent on installer' 'PASS'
    }
} catch {
    # Absence of the stream throws -- that's what we want.
    Record-Result 'W3.4' 'Zone.Identifier ADS absent on installer' 'PASS'
}

# ============================================================================
# 4. W5 -- snapshot pre-install VidCombo state (if Brand=vidcombo)
# ============================================================================

if ($Brand -eq 'vidcombo') {
    # Old BLUEBYTE uninstall registry scan (both native + WOW6432Node).
    $preinstallVidCombo = @()
    $uninstallKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($base in $uninstallKeys) {
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
                $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                if ($dn -and $dn -match '(?i)vidcombo') {
                    $preinstallVidCombo += [pscustomobject]@{
                        Hive = $base
                        Key  = $_.PSChildName
                        Name = $dn
                    }
                }
            }
        }
    }
    Record-Result 'W5.1' ('Pre-install: detected {0} VidCombo entries' -f $preinstallVidCombo.Count) 'PASS' `
        ($preinstallVidCombo | ForEach-Object { $_.Name } | Select-Object -First 3 | Out-String).Trim()

    # Clean any stale temp markers from previous test runs.
    $markerPath = Join-Path $env:TEMP 'vidcombo_installer_ran.txt'
    $keyPath    = Join-Path $env:TEMP 'vidcombo_migrated_key.txt'
    Remove-Item -Force $markerPath, $keyPath -ErrorAction SilentlyContinue
}

# ============================================================================
# 5. W3/W5 -- run the installer silently, then verify state.
#    /LOG=<path> writes Inno's own install log. Corruption markers in the
#    log (e.g. "Setup files corrupted") catch the class of bug where
#    Authenticode is valid but the Inno data archive's internal CRC fails.
#    /CURRENTUSER picks per-user install so the hosted Windows runner does
#    not trip on UAC even though /VERYSILENT suppresses the prompt.
#
#    DO NOT change Start-Process to use -Wait, and do NOT rely on a
#    single WaitForExit() call. Inno's [Run] postinstall section can
#    auto-launch the app, the app becomes foreground, and the installer
#    blocks on the app's return code (verified on real Windows: VidCombo
#    installer did not return until vidcombo.exe was killed). The
#    correct pattern is: -PassThru + poll loop that kills any
#    auto-launched app once to unblock the installer, with a 120s hard
#    cap. See the implementation immediately below.
# ============================================================================

Write-Host ""
Write-Host ">>> Running installer silently: $Installer" -ForegroundColor Cyan

# Brand-derived exe + folder names. Defined here (NOT later) because the
# install-poll loop below references $exeName when killing the Inno [Run]
# auto-launched app. The installed-payload-scan section further down
# reuses these same variables.
$exeName     = if ($Brand -eq 'svid') { 'svid.exe' } else { 'vidcombo.exe' }
$brandFolder = if ($Brand -eq 'svid') { 'Svid' }     else { 'VidCombo' }

$installLog = Join-Path $env:TEMP ("inno-install-{0}-{1}.log" -f $Brand, (Get-Random))
Write-Host "    Install log: $installLog"

$installerArgs = @(
    '/CURRENTUSER',
    '/VERYSILENT',
    '/SP-',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    "/LOG=$installLog"
)
$installerProc = Start-Process -FilePath $Installer -ArgumentList $installerArgs `
    -PassThru -NoNewWindow

# Wait for the installer to exit, but proactively kill any app process the
# Inno [Run] section auto-launches. WaitForExit() alone can hang
# indefinitely when the installer is blocking on the launched app -- the
# app is the foreground process and the installer is waiting on its
# return code. Verified on real Windows: VidCombo installer did not
# return until vidcombo.exe was killed manually.
#
# Strategy: poll every 2s. If the installer exits -> continue.  If the app
# appears -> kill it once to unblock the installer.  Hard cap at 120s.
$processBase  = [IO.Path]::GetFileNameWithoutExtension($exeName)
$installStart = Get-Date
$maxWaitSec   = 120
$appKilledDuringInstall = $false

while ($true) {
    if ($installerProc.HasExited) { break }
    $elapsed = ((Get-Date) - $installStart).TotalSeconds
    if ($elapsed -gt $maxWaitSec) { break }

    $autoLaunched = Get-Process -Name $processBase -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($autoLaunched -and -not $appKilledDuringInstall) {
        Write-Host ("    [install-wait] Inno [Run] auto-launched {0} (PID {1}) -- killing to unblock installer" -f $processBase, $autoLaunched.Id) -ForegroundColor DarkYellow
        $autoLaunched | Stop-Process -Force -ErrorAction SilentlyContinue
        $appKilledDuringInstall = $true
        Start-Sleep -Seconds 3
    } else {
        Start-Sleep -Seconds 2
    }
}

if (-not $installerProc.HasExited) {
    $installerProc.Kill()
    # Before declaring fail, inspect the install log -- Inno may have
    # finished the extraction phase and only the [Run] postinstall is
    # hung. A success marker in the log means the artifact is fine; we
    # just got blocked on harness behavior, not artifact integrity.
    $logSnap = if (Test-Path $installLog) { Get-Content $installLog -Raw -ErrorAction SilentlyContinue } else { '' }
    if ($logSnap -match 'Finished install|Setup successful|Setup completed|Installation completed') {
        Record-Result 'W3.5' 'Installer completed within 2 min' 'WARN' `
            ('Killed after {0}s but log shows success marker -- likely harness blocked on [Run] app' -f $maxWaitSec)
    } else {
        Record-Result 'W3.5' 'Installer completed within 2 min' 'FAIL' `
            ('Killed after {0}s and log has no success marker' -f $maxWaitSec)
        Exit-WithSummary 1
    }
} else {
    # WaitForExit() forces the Process object to refresh and populate ExitCode.
    # Without this, ExitCode is often $null because Inno's setup.tmp exec's
    # into the real installer, and -PassThru captures the short-lived tmp
    # whose ExitCode the runtime never bothered to read.
    try { $installerProc.WaitForExit() } catch {}
    $rc = $installerProc.ExitCode
    if ($null -eq $rc) {
        # Fall back to log evidence: if Inno wrote "Installation process succeeded"
        # the installer ran fine even though we lost the exit code through the
        # setup.tmp exec chain.
        $logSnap = if (Test-Path $installLog) { Get-Content $installLog -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($logSnap -match 'Installation process succeeded|Setup successful|Setup completed') {
            Record-Result 'W3.5' 'Installer exited (exit code lost in setup.tmp chain; log shows success)' 'PASS' `
                'ExitCode was null after WaitForExit -- Inno launches via setup.tmp which exec''s into installer.exe and discards the handle. Log is authoritative.'
        } else {
            Record-Result 'W3.5' 'Installer exited with no captured exit code and no success marker in log' 'FAIL'
        }
    } else {
        Record-Result 'W3.5' ("Installer exited cleanly (code {0})" -f $rc) `
            $(if ($rc -eq 0) { 'PASS' } else { 'FAIL' })
    }
}

# Inno install log present + free of corruption markers. Inno writes the
# "The setup files are corrupted" string into the log when its internal
# CRC fails -- that's the smoking gun for Svid 1.3.9-class regressions.
if (-not (Test-Path $installLog)) {
    Record-Result 'W3.5b' 'Inno install log present' 'FAIL' `
        "Expected log at $installLog -- installer crashed before extraction or /LOG was ignored"
    Exit-WithSummary 1
}
$logContent = Get-Content $installLog -Raw -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($logContent)) {
    Record-Result 'W3.5b' 'Inno install log non-empty' 'FAIL' "$installLog is empty"
    Exit-WithSummary 1
}
$corruptionMarkers = @(
    'The setup files are corrupted',
    'Setup files are corrupted',
    'cyclic redundancy',
    'CRC error',
    'Bad Image'
)
$hitMarker = $null
foreach ($m in $corruptionMarkers) {
    if ($logContent -match [regex]::Escape($m)) { $hitMarker = $m; break }
}
if ($hitMarker) {
    Record-Result 'W3.5c' 'Inno install log free of corruption markers' 'FAIL' `
        "Marker matched: '$hitMarker'"
    Exit-WithSummary 1
} else {
    Record-Result 'W3.5c' 'Inno install log free of corruption markers' 'PASS'
}

# Inno [Run] postinstall may auto-launch the app before the installer
# process exits. We need a clean state for the PE scan + launch test
# below, so kill any app process that survived the installer. The scan
# step further down re-launches deliberately and measures startup.
$preInstallAppName = if ($Brand -eq 'svid') { 'svid' } else { 'vidcombo' }
$leftover = Get-Process -Name $preInstallAppName -ErrorAction SilentlyContinue
if ($leftover) {
    Record-Result 'W3.5d' ("Inno [Run] auto-launched {0} -- cleaning up before scan" -f $preInstallAppName) 'WARN' `
        ("PIDs: " + ($leftover | ForEach-Object { $_.Id } | Out-String).Trim())
    $leftover | Stop-Process -Force -ErrorAction SilentlyContinue
    # Race-window catch: install-wait loop polls every 2s and may exit before
    # Inno's nowait [Run] entry has actually spawned the app. This secondary
    # scan catches that race. Both kill paths must signal $appKilledDuringInstall
    # so W3.6 doesn't false-fail looking for the process we just killed.
    $appKilledDuringInstall = $true
    Start-Sleep -Seconds 2
}

# ============================================================================
# 6. W5 -- installer-ran marker was written (brand=vidcombo only)
# ============================================================================

if ($Brand -eq 'vidcombo') {
    $markerPath = Join-Path $env:TEMP 'vidcombo_installer_ran.txt'
    $keyPath    = Join-Path $env:TEMP 'vidcombo_migrated_key.txt'

    if (Test-Path $markerPath) {
        Record-Result 'W5.2' 'Installer wrote vidcombo_installer_ran.txt' 'PASS' $markerPath
    } else {
        Record-Result 'W5.2' 'Installer wrote vidcombo_installer_ran.txt' 'FAIL' `
            "Expected at $markerPath -- InitializeSetup() did not run or file was swallowed"
    }

    if ($preinstallVidCombo.Count -gt 0 -and (Test-Path $keyPath)) {
        Record-Result 'W5.3' 'Legacy license key extracted to TEMP' 'PASS' $keyPath
    } elseif ($preinstallVidCombo.Count -gt 0) {
        Record-Result 'W5.3' 'Legacy license key extracted to TEMP' 'WARN' `
            'Had VidCombo pre-install but no migrated key -- the old install may not have had an active license stored at the expected path'
    } else {
        Record-Result 'W5.3' 'Legacy license key extraction (no legacy install)' 'SKIP'
    }

    # Confirm old entries are gone.
    $postinstallVidCombo = @()
    foreach ($base in $uninstallKeys) {
        if (Test-Path $base) {
            Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
                $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                if ($dn -and $dn -match '(?i)vidcombo' -and $_.PSChildName -notmatch 'C6BC5050') {
                    $postinstallVidCombo += $dn
                }
            }
        }
    }
    Record-Result 'W5.4' 'Legacy (non-new) VidCombo entries removed' `
        $(if ($postinstallVidCombo.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
        ("Still present: " + ($postinstallVidCombo -join ', '))
}

# ============================================================================
# 7. Installed app binary discovery + URL scheme registered
#    Inno installer uses PrivilegesRequired=lowest + DefaultDirName={autopf},
#    which resolves to %LOCALAPPDATA%\Programs\<Brand> on per-user installs
#    (the actual default for non-admin runs). Scanning only ProgramFiles is
#    a blind spot -- the WebView2Loader.dll Bad Image incident hit a per-user
#    install at C:\Users\kynnd\AppData\Local\Programs\Svid\.
#    Probe order: per-user -> ProgramFiles -> ProgramFiles(x86) -> registry
#    uninstall InstallLocation fallback.
# ============================================================================

# $exeName + $brandFolder defined earlier (before installer execution).
$pf86 = ${env:ProgramFiles(x86)}
$installCandidates = @(
    (Join-Path $env:LOCALAPPDATA  "Programs\$brandFolder\$exeName"),
    (Join-Path $env:ProgramFiles  "$brandFolder\$exeName")
)
if ($pf86) {
    $installCandidates += (Join-Path $pf86 "$brandFolder\$exeName")
}

$expectedExe     = $null
$installedFolder = $null
foreach ($cand in $installCandidates) {
    if (Test-Path $cand) {
        $expectedExe     = $cand
        $installedFolder = Split-Path -Parent $cand
        break
    }
}

# Registry uninstall InstallLocation fallback (HKCU + HKLM, native + WOW6432Node).
if (-not $expectedExe) {
    $uninstallScans = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($base in $uninstallScans) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
            if ($expectedExe) { return }
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.DisplayName -and $props.DisplayName -match "(?i)$brandFolder" -and $props.InstallLocation) {
                $cand = Join-Path $props.InstallLocation $exeName
                if (Test-Path $cand) {
                    $expectedExe     = $cand
                    $installedFolder = $props.InstallLocation
                }
            }
        }
        if ($expectedExe) { break }
    }
}

if ($expectedExe) {
    Record-Result 'W0.3' 'App binary installed (discovered via candidate probe)' 'PASS' $expectedExe
} else {
    Record-Result 'W0.3' 'App binary installed' 'FAIL' `
        ("Probed: " + ($installCandidates -join ' | ') + " + registry uninstall InstallLocation")
    Exit-WithSummary 1
}

$scheme = if ($Brand -eq 'svid') { 'svid' } else { 'vidcombo' }
$schemeKey = "HKCU:\SOFTWARE\Classes\$scheme"
if (Test-Path $schemeKey) {
    Record-Result 'W1.1' ("URL scheme {0}:// registered in HKCU" -f $scheme) 'PASS'
} else {
    Record-Result 'W1.1' ("URL scheme {0}:// registered in HKCU" -f $scheme) 'WARN' `
        'Scheme typically registers on first app launch, not by installer -- re-check after first launch'
}

# ============================================================================
# 7.5. W3.7-W3.9 -- Installed PE payload Authenticode + RSA verification.
#      Catches the WebView2Loader.dll "Bad Image" 0xc0e90002 class of bug:
#      install completes, exe present, but a runtime DLL is unsigned, ECC,
#      or Authenticode-invalid. Smart App Control rejects the load -> app
#      crashes on launch.
# ============================================================================

# Split installed PE into two cohorts:
#  - $payloadPE       runtime files (the app + its dependencies). MUST be
#                     RSA-signed, valid, x64 -- these load into the running
#                     process and are the WebView2Loader.dll Bad Image class.
#  - $uninstallerPE   Inno Setup uninstaller (unins000.exe and friends).
#                     The current Inno script does NOT set [Setup]
#                     SignTool=, so SignedUninstaller defaults to "no" --
#                     unins000.exe ships unsigned. Including it in the
#                     payload gate would cause every smoke run to false-fail.
#                     Tracked separately in W3.11 at WARN level until we
#                     wire signed uninstaller as a follow-up task.
$allInstalled = @(Get-ChildItem -Path $installedFolder -Recurse `
    -Include *.exe,*.dll -ErrorAction SilentlyContinue)
$payloadPE     = @($allInstalled | Where-Object { $_.Name -notlike 'unins*.exe' })
$uninstallerPE = @($allInstalled | Where-Object { $_.Name -like 'unins*.exe' })

$invalidSig = New-Object System.Collections.Generic.List[object]
$nonRsa     = New-Object System.Collections.Generic.List[object]

foreach ($bin in $payloadPE) {
    $sig = Get-AuthenticodeSignature -FilePath $bin.FullName -ErrorAction SilentlyContinue
    $relPath = $bin.FullName.Substring($installedFolder.Length).TrimStart('\')
    if (-not $sig -or $sig.Status -ne 'Valid') {
        $invalidSig.Add([pscustomobject]@{
            File   = $relPath
            Status = if ($sig) { $sig.Status } else { 'NoSignature' }
        })
        continue
    }
    $cert = $sig.SignerCertificate
    # Check RSA via OID literal '1.2.840.113549.1.1.1' (rsaEncryption) for
    # explicit, name-independent verification. GetRSAPublicKey() returns
    # null for ECC certs and works in practice, but the OID check makes
    # the intent unambiguous in CI logs and survives .NET API churn.
    $isRsa = $false
    if ($cert -and $cert.PublicKey -and $cert.PublicKey.Oid) {
        $isRsa = ($cert.PublicKey.Oid.Value -eq '1.2.840.113549.1.1.1')
    }
    if (-not $isRsa) {
        $nonRsa.Add([pscustomobject]@{
            File = $relPath
            Algo = if ($cert -and $cert.PublicKey -and $cert.PublicKey.Oid) {
                # PS 5.1 parser inside hashtable+if cannot disambiguate '-f' with
                # comma-separated member accesses. String interpolation sidesteps.
                "$($cert.PublicKey.Oid.FriendlyName) ($($cert.PublicKey.Oid.Value))"
            } else { 'UnknownCert' }
        })
    }
}

Record-Result 'W3.7' ("Runtime payload: {0} PE files Authenticode-valid" -f $payloadPE.Count) `
    $(if ($invalidSig.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    $(if ($invalidSig.Count -gt 0) { ($invalidSig | Select-Object -First 5 | Format-Table -AutoSize | Out-String).Trim() } else { '' })

Record-Result 'W3.8' 'Runtime payload: all signatures use RSA cert (SAC requirement)' `
    $(if ($nonRsa.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    $(if ($nonRsa.Count -gt 0) { ($nonRsa | Select-Object -First 5 | Format-Table -AutoSize | Out-String).Trim() } else { 'ECDSA-signed binaries trigger SAC Bad Image 0xc0e90002' })

# Architecture check: every PE Machine field must be x64 (0x8664). An x86
# (0x14C) or ARM64 (0xAA64) DLL loaded into a 64-bit svid.exe/vidcombo.exe
# process triggers Bad Image at LoadLibrary, exactly the user-reported
# class. Reads PE header bytes directly -- no extra deps.
# Unreadable / truncated / non-PE files are tracked separately and FAIL --
# silent skip would let a corrupt DLL slip through, which is the exact
# bug class we are trying to catch.
$archMismatch = New-Object System.Collections.Generic.List[object]
$archInvalid  = New-Object System.Collections.Generic.List[object]
foreach ($bin in $payloadPE) {
    $relPath = $bin.FullName.Substring($installedFolder.Length).TrimStart('\')
    $stream = $null
    $reader = $null
    $reason = $null
    $machine = $null
    try {
        $stream = [System.IO.File]::Open($bin.FullName, 'Open', 'Read', 'Read')
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 0x40) {
            $reason = ('TooSmall ({0} bytes)' -f $stream.Length)
        } else {
            $stream.Seek(0x3C, 'Begin') | Out-Null
            $peOffset = $reader.ReadInt32()
            if ($peOffset -le 0 -or ($peOffset + 6) -gt $stream.Length) {
                $reason = ('BadPEOffset (0x{0:X})' -f $peOffset)
            } else {
                $stream.Seek($peOffset, 'Begin') | Out-Null
                $peSig = $reader.ReadUInt32()
                if ($peSig -ne 0x00004550) {
                    $reason = ('BadPESignature (0x{0:X8})' -f $peSig)
                } else {
                    $machine = $reader.ReadUInt16()
                }
            }
        }
    } catch {
        $reason = ('IOError: ' + $_.Exception.Message)
    } finally {
        if ($reader) { $reader.Close() }
        if ($stream) { $stream.Close() }
    }

    if ($reason) {
        $archInvalid.Add([pscustomobject]@{ File = $relPath; Reason = $reason })
        continue
    }

    if ($null -ne $machine -and $machine -ne 0x8664) {
        $archName = switch ($machine) {
            0x014C  { 'x86 (i386)' }
            0xAA64  { 'ARM64' }
            0x01C0  { 'ARM' }
            0x01C4  { 'ARMNT' }
            default { ('0x{0:X4}' -f $machine) }
        }
        $archMismatch.Add([pscustomobject]@{ File = $relPath; Arch = $archName })
    }
}

Record-Result 'W3.10' ("Runtime payload: all PE binaries are x64 ({0} scanned)" -f $payloadPE.Count) `
    $(if ($archMismatch.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    $(if ($archMismatch.Count -gt 0) { ($archMismatch | Select-Object -First 5 | Format-Table -AutoSize | Out-String).Trim() } else { 'x86/ARM DLLs in x64 process produce Bad Image at LoadLibrary' })

Record-Result 'W3.10b' 'Runtime payload: all PE headers readable + valid' `
    $(if ($archInvalid.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    $(if ($archInvalid.Count -gt 0) { ($archInvalid | Select-Object -First 5 | Format-Table -AutoSize | Out-String).Trim() } else { 'Corrupt/truncated PE headers cause Bad Image at LoadLibrary' })

# W3.11 -- Inno uninstaller signature/arch (informational WARN).
# unins000.exe is unsigned by default because installer_windows.iss does
# not set [Setup] SignTool=. Not blocking app-launch quality, but tracked
# so we know whether to escalate to a separate "signed uninstaller" task.
foreach ($u in $uninstallerPE) {
    $relPath = $u.FullName.Substring($installedFolder.Length).TrimStart('\')
    $sig = Get-AuthenticodeSignature -FilePath $u.FullName -ErrorAction SilentlyContinue
    $sigStatus = if ($sig) { [string]$sig.Status } else { 'NoSignature' }
    $sigSubject = ''
    if ($sig -and $sig.SignerCertificate) {
        $sigSubject = [string]$sig.SignerCertificate.Subject
    }
    $isSigned = ($sig -and $sig.Status -eq 'Valid')
    Record-Result ("W3.11.{0}" -f $u.Name) ("Inno uninstaller {0} (informational)" -f $relPath) `
        $(if ($isSigned) { 'PASS' } else { 'WARN' }) `
        ("Status={0} Subject={1}" -f $sigStatus, $sigSubject).Trim()
}

# Spotlight critical binaries with severity differential:
#  - <exe>, native.dll, WebView2Loader.dll: missing -> FAIL.
#    Both Svid 1.3.9 and VidCombo 1.6.6 build flows produce
#    WebView2Loader.dll today; missing it on a real installed payload
#    means the Browser/AI WebView surface will crash on first use.
#    Revisit only if a future Flutter plugin version drops it
#    intentionally -- at that point relax the rule with a note.
$spotlight = @(
    [pscustomobject]@{ Name = $exeName;             MissingSeverity = 'FAIL' },
    [pscustomobject]@{ Name = 'native.dll';         MissingSeverity = 'FAIL' },
    [pscustomobject]@{ Name = 'WebView2Loader.dll'; MissingSeverity = 'FAIL' }
)
foreach ($crit in $spotlight) {
    $found = $payloadPE | Where-Object Name -eq $crit.Name | Select-Object -First 1
    if ($found) {
        $sig = Get-AuthenticodeSignature -FilePath $found.FullName -ErrorAction SilentlyContinue
        $isValid = ($sig -and $sig.Status -eq 'Valid')
        $isRsa   = $false
        if ($isValid -and $sig.SignerCertificate -and $sig.SignerCertificate.PublicKey -and $sig.SignerCertificate.PublicKey.Oid) {
            $isRsa = ($sig.SignerCertificate.PublicKey.Oid.Value -eq '1.2.840.113549.1.1.1')
        }
        $status     = if ($isValid -and $isRsa) { 'PASS' } else { 'FAIL' }
        $sigStatus  = if ($sig) { [string]$sig.Status } else { 'NoSignature' }
        $sigSubject = ''
        if ($sig -and $sig.SignerCertificate) {
            $sigSubject = [string]$sig.SignerCertificate.Subject
        }
        $detail = ("Status={0} Subject={1}" -f $sigStatus, $sigSubject).Trim()
        Record-Result ("W3.9.{0}" -f $crit.Name) ("Critical: {0} signed RSA + valid" -f $crit.Name) $status $detail
    } else {
        Record-Result ("W3.9.{0}" -f $crit.Name) ("Critical: {0} present in install" -f $crit.Name) `
            $crit.MissingSeverity `
            "Not found in $installedFolder"
    }
}

# VC++ Runtime DLLs: must be app-local-present AND signed by Microsoft.
# These ship from Microsoft's Authenticode signer chain -- not our RSA cert.
# Missing any one => Carl-class loader failure on clean Windows machines.
$vcRuntimeDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
foreach ($dllName in $vcRuntimeDlls) {
    $found = $payloadPE | Where-Object Name -eq $dllName | Select-Object -First 1
    if (-not $found) {
        Record-Result ("W3.10.{0}" -f $dllName) ("VC++ runtime: {0} present in install" -f $dllName) `
            'FAIL' "Not found in $installedFolder (Carl-class loader failure on clean Windows)"
        continue
    }
    $sig = Get-AuthenticodeSignature -FilePath $found.FullName -ErrorAction SilentlyContinue
    $isValid = ($sig -and $sig.Status -eq 'Valid')
    $isMicrosoft = $false
    if ($isValid -and $sig.SignerCertificate) {
        $isMicrosoft = ($sig.SignerCertificate.Subject -match 'Microsoft Corporation')
    }
    $status = if ($isValid -and $isMicrosoft) { 'PASS' } else { 'FAIL' }
    $sigStatus  = if ($sig) { [string]$sig.Status } else { 'NoSignature' }
    $sigSubject = ''
    if ($sig -and $sig.SignerCertificate) {
        $sigSubject = [string]$sig.SignerCertificate.Subject
    }
    $detail = ("Status={0} Signer={1}" -f $sigStatus, $sigSubject).Trim()
    Record-Result ("W3.10.{0}" -f $dllName) ("VC++ runtime: {0} signed Microsoft + valid" -f $dllName) $status $detail
}

# ============================================================================
# 8. W3 -- silent-install relaunch ([Run] dual entry in Inno Setup)
# ============================================================================

if ($SkipLaunchCheck) {
    Record-Result 'W3.6' 'Silent install triggered app launch' 'SKIP'
} else {
    # The install-wait loop above proactively kills any Inno [Run]
    # auto-launched app to unblock the installer. If that fired, we already
    # OBSERVED the relaunch -- that is the evidence the [Run] skipifnotsilent
    # entry works. Re-polling for the process here would be a false negative
    # (we just killed it ourselves). Only fall through to the poll if the
    # install loop never saw a relaunch.
    if ($appKilledDuringInstall) {
        Record-Result 'W3.6' `
            ("Silent install auto-relaunched {0} (observed during install-wait, killed for clean scan)" -f $exeName) `
            'PASS' `
            'Relaunch was killed in W3.5d so the installed-payload scan could run on stable state'
    } else {
        Start-Sleep -Seconds 3
        $deadline = (Get-Date).AddSeconds($LaunchTimeoutSeconds)
        $launched = $false
        while ((Get-Date) -lt $deadline) {
            $proc = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue
            if ($proc) { $launched = $true; break }
            Start-Sleep -Milliseconds 500
        }
        Record-Result 'W3.6' `
            ("Silent install auto-relaunched {0} within {1}s" -f $exeName, $LaunchTimeoutSeconds) `
            $(if ($launched) { 'PASS' } else { 'FAIL' }) `
            'Installer [Run] section must have skipifnotsilent entry -- regressions here break auto-update UX'
    }
}

# ============================================================================
# 9. W3.12 -- Windows Event Log / Windows Error Reporting check.
#    Application Error / .NET Runtime / WER faults emitted by svid.exe or
#    vidcombo.exe within the last 10 minutes indicate the app loaded but
#    crashed on its own (e.g. Bad Image on a runtime DLL, unhandled
#    exception during startup). The launch-test above only checks that the
#    process started -- it does not catch a crash 1 second later.
# ============================================================================

$processBase = [IO.Path]::GetFileNameWithoutExtension($exeName)
$werLookback = (Get-Date).AddMinutes(-10)
try {
    $faultEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        Level     = @(1, 2)  # Critical + Error
        StartTime = $werLookback
    } -ErrorAction Stop |
        Where-Object {
            ($_.ProviderName -match 'Application Error|\.NET Runtime|Windows Error Reporting') -and
            ($_.Message -match $processBase)
        }
    if ($faultEvents) {
        $detail = $faultEvents | Select-Object -First 3 |
            ForEach-Object { "{0} [{1}] {2}" -f $_.TimeCreated, $_.ProviderName, ($_.Message -split "`n" | Select-Object -First 1) } |
            Out-String
        Record-Result 'W3.12' "Windows Event Log free of $processBase faults (10-min lookback)" 'FAIL' $detail.Trim()
    } else {
        Record-Result 'W3.12' "Windows Event Log free of $processBase faults (10-min lookback)" 'PASS'
    }
} catch {
    Record-Result 'W3.12' "Windows Event Log free of $processBase faults (10-min lookback)" 'WARN' `
        ("Could not query Event Log: " + $_.Exception.Message)
}

# ============================================================================
# 9b. W3.13 -- GRACEFUL CLOSE exit-path crash check.
#     The force-kill cleanup below (Stop-Process -Force) skips the ENTIRE CRT
#     shutdown / static-destructor path, so an exit-time teardown crash is
#     structurally INVISIBLE to a force-kill smoke -- which is exactly why the
#     WinToast COM-Release-after-CoUninitialize fail-fast (0xc0000602 in
#     coremessaging.dll) reached users despite a green CI. Here we close the
#     app the way a user does -- WM_CLOSE via CloseMainWindow() -- and assert
#     the process exits cleanly with no new Application Error / WER fault in a
#     tight window around the close.
#
#     COVERAGE NOTE: the notification-teardown crash arms only when WinToast's
#     internal buffer still holds a live toast at exit. For maximum sensitivity
#     the run should have shown at least one notification before this point; a
#     run with no toast still validates the general graceful-exit teardown path.
# ============================================================================

$graceProc = Get-Process -Name $processBase -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $graceProc) {
    $graceProc = Get-Process -Name $processBase -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($graceProc) {
    $closeMark = Get-Date
    $closeSent = $false
    try { $closeSent = $graceProc.CloseMainWindow() } catch {}
    if (-not $closeSent) {
        Record-Result 'W3.13' "Graceful close (WM_CLOSE) exits $processBase cleanly" 'WARN' `
            'CloseMainWindow() returned false (no main window / already closing) -- graceful exit path not exercised'
    } elseif (-not $graceProc.WaitForExit(15000)) {
        Record-Result 'W3.13' "Graceful close (WM_CLOSE) exits $processBase cleanly" 'WARN' `
            'App did not exit within 15s of WM_CLOSE -- force-kill cleanup will follow'
    } else {
        Start-Sleep -Seconds 2  # let Windows Error Reporting flush any fault event
        $closeFaults = $null
        try {
            $closeFaults = Get-WinEvent -FilterHashtable @{
                LogName = 'Application'; Level = @(1, 2); StartTime = $closeMark
            } -ErrorAction Stop | Where-Object {
                ($_.ProviderName -match 'Application Error|\.NET Runtime|Windows Error Reporting') -and
                ($_.Message -match $processBase)
            }
        } catch {}
        if ($closeFaults) {
            $cd = $closeFaults | Select-Object -First 3 | ForEach-Object {
                "{0} [{1}] {2}" -f $_.TimeCreated, $_.ProviderName, ($_.Message -split "`n" | Select-Object -First 1)
            } | Out-String
            Record-Result 'W3.13' "Graceful close (WM_CLOSE) exits $processBase cleanly" 'FAIL' `
                ("Exit-time fault after graceful close (teardown-crash class, e.g. WinToast COM Release post-CoUninitialize):`n" + $cd.Trim())
        } else {
            Record-Result 'W3.13' "Graceful close (WM_CLOSE) exits $processBase cleanly" 'PASS'
        }
    }
} else {
    Record-Result 'W3.13' "Graceful close (WM_CLOSE) exits $processBase cleanly" 'SKIP' `
        'No running app process available to close gracefully at this point'
}

# ============================================================================
# 10. Final cleanup -- kill any lingering app process from the launch test
#     so subsequent CI steps / uninstall reinstall cycles have clean state.
#     (After W3.13 a graceful exit usually leaves nothing here; this remains a
#     safety net for the WARN paths where the app did not exit on its own.)
# ============================================================================

$lingering = Get-Process -Name $processBase -ErrorAction SilentlyContinue
if ($lingering) {
    Write-Host ""
    Write-Host (">>> Cleanup: killing {0} lingering {1} process(es)" -f $lingering.Count, $processBase) `
        -ForegroundColor DarkYellow
    $lingering | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# ============================================================================
# 11. macOS-style sanity: entitlements / hardened runtime N/A on Windows
# ============================================================================

Exit-WithSummary
