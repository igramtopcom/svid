# =============================================================================
# Copy the three Microsoft VC++ 2015-2022 runtime DLLs into the Flutter Windows
# bundle so app-local resolution succeeds on clean Windows machines (LTSC, IoT,
# fresh installs without the VC++ Redistributable). Closes the Carl-class
# pre-launch loader failure (`vcruntime140_1.dll not found`).
#
# Source: the Visual Studio install on the build agent's MSVC redist directory.
#         Microsoft.VC143.CRT subfolder contains the three runtime DLLs already
#         signed by Microsoft with a valid Authenticode chain.
#
# Usage: scripts/windows_bundle_vcruntime.ps1 -BundleDir dist/windows-bundle
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BundleDir)) {
    Write-Error "Bundle directory not found: $BundleDir"
    exit 1
}

$requiredDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

# Locate the Microsoft.VC143.CRT redist directory on the build agent.
# vswhere is the official Microsoft tool to discover Visual Studio installs.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    Write-Error "vswhere.exe not found at $vswhere. Visual Studio Build Tools required on this runner."
    exit 1
}

$vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Redist.14.Latest -property installationPath
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
    Write-Error "No Visual Studio install with VC.Redist.14.Latest component found on this runner."
    exit 1
}

# The redist version directory name is the actual MSVC toolset version
# (eg 14.40.33807). Pick the highest version present.
$redistRoot = Join-Path $vsInstall 'VC\Redist\MSVC'
if (-not (Test-Path -LiteralPath $redistRoot)) {
    Write-Error "VC Redist root not found: $redistRoot"
    exit 1
}

$versionDir = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'x64\Microsoft.VC143.CRT') } |
    Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending |
    Select-Object -First 1

if ($null -eq $versionDir) {
    Write-Error "No x64\Microsoft.VC143.CRT directory found under $redistRoot"
    exit 1
}

$sourceDir = Join-Path $versionDir.FullName 'x64\Microsoft.VC143.CRT'
Write-Host "==> VC++ runtime source: $sourceDir"

foreach ($dll in $requiredDlls) {
    $src = Join-Path $sourceDir $dll
    $dst = Join-Path $BundleDir $dll
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Error "Source DLL missing in redist directory: $src"
        exit 1
    }

    # Verify Microsoft Authenticode signature on source BEFORE copy.
    # Fail hard if the source is somehow tampered/unsigned.
    $sig = Get-AuthenticodeSignature -LiteralPath $src
    if ($sig.Status -ne 'Valid') {
        Write-Error "Source $dll has non-Valid Authenticode status: $($sig.Status)"
        exit 1
    }
    if ($sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        Write-Error "Source $dll signer is not Microsoft: $($sig.SignerCertificate.Subject)"
        exit 1
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    $size = (Get-Item -LiteralPath $dst).Length
    Write-Host ("  + {0,-22} {1,12:N0} bytes  (signer verified Microsoft)" -f $dll, $size)
}

Write-Host "==> VC++ runtime DLLs bundled into $BundleDir"

# -----------------------------------------------------------------------------
# Prune orphan debug-CRT DLLs.
#
# media_kit_libs_windows_video bundles zlib.dll from the ANGLE prebuild, which
# was linked against the DEBUG CRT (imports VCRUNTIME140D.dll + ucrtbased.dll --
# DLLs that only exist on machines with Visual Studio). Verified via dumpbin:
#   * NO shipped PE imports zlib.dll (no entry in any /DEPENDENTS list)
#   * NO binary contains the literal string "zlib.dll" / "zlib1.dll" (nothing
#     can LoadLibrary it by name at runtime)
#   * mpv statically links its own zlib (libmpv-2.dll has zlib symbols but no
#     dependency on this file)
# => zlib.dll is a dead-weight orphan AND the only source of the debug-CRT leak.
# Removing it eliminates the leak entirely instead of allow-listing it, so the
# dependency-closure gate stays strict (any future debug-CRT import FAILs hard).
$orphanDebugCrtDlls = @('zlib.dll')
foreach ($orphan in $orphanDebugCrtDlls) {
    $target = Join-Path $BundleDir $orphan
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Force
        Write-Host ("  - pruned orphan debug-CRT DLL: {0}" -f $orphan)
    }
}
