# =============================================================================
# Multi-Brand Windows Packaging Script — Creates portable .zip from a Windows
# runner bundle (default: Flutter Release output).
# =============================================================================

param(
  [string]$Brand = "svid",
  [string]$BundleDir = ""
)

$ErrorActionPreference = "Stop"

Write-Warning "Legacy unsigned packaging helper. Do not use this script for production Windows releases; use the Release Pipeline dry-run path instead."

# Brand configuration
switch ($Brand) {
  "svid"    { $AppName = "Svid";    $ExeName = "svid.exe" }
  "vidcombo" { $AppName = "VidCombo"; $ExeName = "vidcombo.exe" }
  default    { Write-Error "Unknown brand: $Brand. Use 'svid' or 'vidcombo'."; exit 1 }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir/.."
$DistDir = "$ProjectRoot/dist"

# Parse version from pubspec.yaml
$pubspec = Get-Content "$ProjectRoot/pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s*(\S+)')
$fullVersion = $versionMatch.Groups[1].Value
$version = $fullVersion -replace '\+.*', ''

$ResolvedBundleDir = if ($BundleDir -ne "") { $BundleDir } else { "$ProjectRoot/build/windows/x64/runner/Release" }
$ZipName = "$AppName-$version-windows-x64.zip"
$ZipPath = "$DistDir/$ZipName"
$StagingDir = "$DistDir/windows-staging"

Write-Host "Packaging Windows ZIP: $ZipName (brand: $Brand)"

# Verify bundle exists
if (-not (Test-Path $ResolvedBundleDir)) {
    Write-Error "ERROR: $ResolvedBundleDir not found. Run 'flutter build windows --release' first or pass -BundleDir."
    exit 1
}

# Create dist directory
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# Clean previous
if (Test-Path $StagingDir) { Remove-Item -Recurse -Force $StagingDir }
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

# Create staging directory
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

# Copy build output
Copy-Item -Recurse "$ResolvedBundleDir/*" "$StagingDir/"

# Copy Rust native DLL if it exists in the windows folder
$NativeDll = "$ProjectRoot/windows/native.dll"
if (-not (Test-Path "$StagingDir/native.dll") -and (Test-Path $NativeDll)) {
    Copy-Item $NativeDll "$StagingDir/native.dll"
    Write-Host "  Copied native.dll fallback"
}

# Create ZIP
Write-Host "  Creating ZIP archive..."
Compress-Archive -Path "$StagingDir/*" -DestinationPath $ZipPath -Force

# Clean up
Remove-Item -Recurse -Force $StagingDir

$size = (Get-Item $ZipPath).Length / 1MB
Write-Host "  ZIP created: $ZipPath"
Write-Host ("  Size: {0:N1} MB" -f $size)
