# verify_toolchain.ps1
#
# Post-bootstrap sanity probe. Prints version of every tool the Flutter +
# Rust + Inno build pipeline depends on. Used by Mac orchestrator (via SSH)
# to verify the lab is ready before kicking off a build.
#
# Exit code: 0 if all REQUIRED tools present, 1 otherwise.

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$results = [System.Collections.Generic.List[object]]::new()

function Probe {
    param(
        [string]$Name,
        [string]$Cmd,
        [string]$VersionPattern = '.+',
        [switch]$Required
    )
    $out = & cmd /c "$Cmd 2>&1"
    $rc = $LASTEXITCODE
    if ($rc -le 1 -and $out) {
        $line = ($out | Where-Object { $_ -match $VersionPattern } | Select-Object -First 1)
        if (-not $line) { $line = ($out | Select-Object -First 1) }
        $status = 'OK'
    }
    else {
        $line = ''
        $status = if ($Required) { 'MISSING-REQUIRED' } else { 'MISSING' }
    }
    $results.Add([pscustomobject]@{
        Tool     = $Name
        Status   = $status
        Required = [bool]$Required
        Version  = "$line".Trim()
    })
}

# Required for the canonical build pipeline.
Probe -Name 'git'        -Cmd 'git --version'        -Required
Probe -Name 'gh'         -Cmd 'gh --version'
Probe -Name 'pwsh7'      -Cmd 'pwsh -v'
Probe -Name 'powershell' -Cmd 'powershell -Command $PSVersionTable.PSVersion.ToString()' -Required
Probe -Name 'cmake'      -Cmd 'cmake --version'      -Required
Probe -Name 'ninja'      -Cmd 'ninja --version'      -Required
Probe -Name '7z'         -Cmd '7z i'
Probe -Name 'iscc'       -Cmd 'iscc /?'              -Required
Probe -Name 'rustc'      -Cmd 'rustc --version'      -Required
Probe -Name 'cargo'      -Cmd 'cargo --version'      -Required
Probe -Name 'rustup'     -Cmd 'rustup --version'     -Required
Probe -Name 'fvm'        -Cmd 'fvm --version'        -Required
Probe -Name 'flutter'    -Cmd 'fvm flutter --version' -Required
Probe -Name 'dart'       -Cmd 'fvm dart --version'   -Required

# MSVC cl.exe + signtool: detected via filesystem since they're not on PATH by default.
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$clFound = $false
if (Test-Path $vsWhere) {
    $vsInstall = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsInstall) {
        $cl = Get-ChildItem -Path (Join-Path $vsInstall 'VC\Tools\MSVC') -Filter 'cl.exe' -Recurse -ErrorAction SilentlyContinue |
              Where-Object FullName -match 'x64\\cl\.exe$' | Select-Object -First 1
        if ($cl) {
            $results.Add([pscustomobject]@{ Tool = 'cl.exe (MSVC)'; Status = 'OK'; Required = $true; Version = $cl.FullName })
            $clFound = $true
        }
    }
}
if (-not $clFound) {
    $results.Add([pscustomobject]@{ Tool = 'cl.exe (MSVC)'; Status = 'MISSING-REQUIRED'; Required = $true; Version = '' })
}

$signtool = Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object FullName -match 'x64\\signtool\.exe$' | Sort-Object FullName -Descending | Select-Object -First 1
if ($signtool) {
    $results.Add([pscustomobject]@{ Tool = 'signtool'; Status = 'OK'; Required = $false; Version = $signtool.FullName })
}
else {
    $results.Add([pscustomobject]@{ Tool = 'signtool'; Status = 'MISSING'; Required = $false; Version = '' })
}

# Print table
$results | Format-Table -AutoSize

$missingReq = ($results | Where-Object { $_.Required -and $_.Status -ne 'OK' }).Count
$missingOpt = ($results | Where-Object { -not $_.Required -and $_.Status -ne 'OK' }).Count
Write-Host ""
Write-Host ("Required missing: {0}    Optional missing: {1}" -f $missingReq, $missingOpt)

if ($missingReq -eq 0) {
    Write-Host "TOOLCHAIN READY" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "TOOLCHAIN NOT READY ($missingReq required tool(s) missing)" -ForegroundColor Red
    exit 1
}
