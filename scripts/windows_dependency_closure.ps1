# =============================================================================
# Windows dependency closure audit.
#
# For each shipped PE file (the brand exe and every *.dll in the bundle),
# enumerate its direct imported DLLs via `dumpbin /DEPENDENTS`. Every dependency
# must EITHER be on a Windows system allowlist OR be present in the bundle
# itself. Anything else means "this build only works on machines that happen to
# already have <X>.dll installed", which is the exact class of bug that hid the
# VC++ runtime gap for months.
#
# Pragmatic v1: direct deps only (no transitive walk). Catches the high-value
# cases (vcruntime*, msvcp*, third-party runtimes) without combinatorial blowup.
#
# Usage:
#   scripts/windows_dependency_closure.ps1 -BundleDir dist/windows-bundle -Brand vidcombo
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDir,

    [Parameter(Mandatory = $true)]
    [ValidateSet('svid', 'vidcombo')]
    [string]$Brand
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BundleDir)) {
    Write-Error "Bundle dir not found: $BundleDir"
    exit 1
}
# Resolve to absolute path -- $pe.FullName below is absolute, so the
# Substring(BundleDir.Length) display path requires BundleDir to be absolute too.
$BundleDir = (Resolve-Path -LiteralPath $BundleDir).Path

# Locate dumpbin.exe (ships with Visual Studio Build Tools).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    Write-Error "vswhere.exe not found at $vswhere"
    exit 1
}
$vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
    Write-Error "No Visual Studio install with VC.Tools.x86.x64 component found"
    exit 1
}
$msvcRoot = Join-Path $vsInstall 'VC\Tools\MSVC'
$msvcVer = Get-ChildItem -LiteralPath $msvcRoot -Directory |
    Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending |
    Select-Object -First 1
$dumpbin = Join-Path $msvcVer.FullName 'bin\Hostx64\x64\dumpbin.exe'
if (-not (Test-Path -LiteralPath $dumpbin)) {
    Write-Error "dumpbin.exe not found at $dumpbin"
    exit 1
}

# Windows system DLL allowlist. These ship with every supported Windows version
# (Windows 10 1507+) and are safe to depend on without bundling.
# Sources: api-ms-win-* and ext-ms-win-* are the Universal CRT umbrella;
# kernel32/user32/etc. are core Win32; bcrypt/crypt32 are SSPI/CNG.
$systemAllowlist = @(
    # Kernel + ntdll layer
    'ntdll.dll', 'kernel32.dll', 'kernelbase.dll', 'user32.dll', 'gdi32.dll',
    'gdi32full.dll', 'win32u.dll', 'msvcrt.dll',
    # Core Win32
    'advapi32.dll', 'comctl32.dll', 'comdlg32.dll', 'shell32.dll', 'shlwapi.dll',
    'shcore.dll', 'ole32.dll', 'oleaut32.dll', 'rpcrt4.dll', 'oleacc.dll',
    'wininet.dll', 'urlmon.dll', 'winhttp.dll', 'iertutil.dll', 'mpr.dll',
    'wldap32.dll', 'ws2_32.dll', 'mswsock.dll', 'iphlpapi.dll', 'dnsapi.dll',
    'netapi32.dll', 'cfgmgr32.dll', 'powrprof.dll', 'psapi.dll', 'userenv.dll',
    'version.dll', 'winmm.dll', 'imm32.dll', 'msimg32.dll', 'setupapi.dll',
    'msi.dll', 'dwmapi.dll', 'uxtheme.dll', 'gdiplus.dll', 'wevtapi.dll',
    'wtsapi32.dll', 'profapi.dll', 'normaliz.dll', 'usp10.dll', 'imagehlp.dll',
    'dbghelp.dll', 'winspool.drv', 'wsock32.dll',
    # Crypto / SSPI / CNG
    'crypt32.dll', 'cryptbase.dll', 'cryptsp.dll', 'bcrypt.dll',
    'bcryptprimitives.dll', 'ncrypt.dll', 'msasn1.dll', 'wintrust.dll',
    'secur32.dll', 'sspicli.dll',
    # Graphics / media (ships with Windows 10+)
    'd3d11.dll', 'd3d12.dll', 'd3d9.dll', 'd2d1.dll', 'dxgi.dll', 'dxva2.dll',
    'dwrite.dll', 'windowscodecs.dll', 'avrt.dll', 'mfplat.dll', 'mf.dll',
    'mfreadwrite.dll', 'mfsensorgroup.dll', 'evr.dll', 'audioses.dll',
    'mmdevapi.dll', 'msacm32.dll', 'opengl32.dll', 'glu32.dll', 'avicap32.dll',
    # UI Automation / accessibility (oleacc already listed above)
    'uiautomationcore.dll',
    # COM / WinRT
    'combase.dll', 'propsys.dll', 'twinapi.appcore.dll', 'twinapi.dll',
    'coremessaging.dll', 'coreuicomponents.dll',
    # Universal CRT (ships with Windows 10+)
    'ucrtbase.dll'
)

# Anything starting with these prefixes is treated as system (api-ms-* / ext-ms-*).
$systemPrefixes = @('api-ms-win-', 'ext-ms-win-')

# DEBUG runtime DLLs -- these only exist on machines with Visual Studio
# installed. ANY reference from a shipped PE means the third-party artifact
# was built against the debug CRT instead of the release CRT. This is the
# exact Carl-class loader failure the P4 gate is designed to catch.
$debugRuntimeDlls = @(
    'vcruntime140d.dll', 'vcruntime140_1d.dll', 'msvcp140d.dll',
    'ucrtbased.dll', 'msvcrtd.dll', 'concrt140d.dll'
)

function Is-SystemDll {
    param([string]$Name)
    $lower = $Name.ToLowerInvariant()
    if ($systemAllowlist -contains $lower) { return $true }
    foreach ($prefix in $systemPrefixes) {
        if ($lower.StartsWith($prefix)) { return $true }
    }
    return $false
}

function Is-DebugRuntime {
    param([string]$Name)
    return $debugRuntimeDlls -contains $Name.ToLowerInvariant()
}

# Known upstream-tracked debug-runtime leaks. Each entry pairs a shipped PE
# with the exact debug DLL its third-party prebuild references. The gate
# logs these as WARNING and lets the build pass, but they MUST NOT grow
# without a tracked upstream issue.
#
# Intentionally EMPTY. The former sole entry -- zlib.dll (media_kit's ANGLE
# prebuild, linked against the debug CRT) -- was proven a dead-weight orphan
# (no PE imports it; no binary references "zlib.dll" by name) and is now
# pruned at bundle-staging time in windows_bundle_vcruntime.ps1. With it gone
# the gate stays strict: ANY debug-CRT import from ANY shipped PE FAILs hard.
# Do NOT add an entry here without a real, LoadLibrary-proven invocation and a
# tracked upstream issue -- allow-listing a debug-CRT leak ships a clean-machine
# crash.
$knownDebugRuntimeLeaks = @{
}

function Is-KnownLeak {
    param([string]$PeBaseName, [string]$Dep)
    $peKey = $PeBaseName.ToLowerInvariant()
    if (-not $knownDebugRuntimeLeaks.ContainsKey($peKey)) { return $false }
    return $knownDebugRuntimeLeaks[$peKey] -contains $Dep.ToLowerInvariant()
}

# Enumerate bundle contents (files directly shipped) -- case-insensitive name match.
$bundleFiles = Get-ChildItem -LiteralPath $BundleDir -Recurse -File |
    ForEach-Object { $_.Name.ToLowerInvariant() } |
    Sort-Object -Unique

function Is-InBundle {
    param([string]$Name)
    return $bundleFiles -contains $Name.ToLowerInvariant()
}

# PE files to audit: brand exe + every shipped DLL.
$peFiles = Get-ChildItem -LiteralPath $BundleDir -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.dll') }

$violations = @()
$auditCount = 0

foreach ($pe in $peFiles) {
    $auditCount++
    $rel = $pe.FullName.Substring($BundleDir.Length).TrimStart('\', '/')
    $dumpbinOutput = & $dumpbin /NOLOGO /DEPENDENTS $pe.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "dumpbin failed for ${rel}: $dumpbinOutput"
        continue
    }
    # dumpbin /DEPENDENTS output: blank line, then "Image has the following dependencies:" then DLL names.
    $inDepsSection = $false
    $deps = @()
    foreach ($line in $dumpbinOutput) {
        $trimmed = $line.Trim()
        if ($trimmed -match 'has the following.*dependencies') {
            $inDepsSection = $true
            continue
        }
        if (-not $inDepsSection) { continue }
        if ($trimmed -match '^Summary' -or $trimmed -match '^Image has' -or $trimmed -eq '') {
            if ($trimmed -match '^Summary') { break }
            continue
        }
        if ($trimmed -match '^\S+\.dll$') {
            $deps += $trimmed
        }
    }

    $peBase = $pe.Name
    foreach ($dep in $deps) {
        $kind = if (Is-DebugRuntime $dep) {
            if (Is-KnownLeak $peBase $dep) { 'KnownLeak' } else { 'DebugRuntime' }
        } elseif (Is-SystemDll $dep) {
            'System'
        } elseif (Is-InBundle $dep) {
            'Bundled'
        } else {
            'Missing'
        }
        if ($kind -eq 'System' -or $kind -eq 'Bundled') { continue }
        $violations += [pscustomobject]@{
            PE = $rel
            MissingDep = $dep
            Kind = $kind
        }
    }
}

Write-Host ""
Write-Host "==> Dependency closure audit (brand=$Brand, bundle=$BundleDir)"
Write-Host "    PE files audited: $auditCount"
Write-Host "    System allowlist entries: $($systemAllowlist.Count) + prefixes"
Write-Host "    Bundle files: $($bundleFiles.Count)"

$debugLeaks = $violations | Where-Object { $_.Kind -eq 'DebugRuntime' }
$missingDeps = $violations | Where-Object { $_.Kind -eq 'Missing' }
$knownLeaks = $violations | Where-Object { $_.Kind -eq 'KnownLeak' }

if ($knownLeaks.Count -gt 0) {
    Write-Host ""
    Write-Host "  [KNOWN UPSTREAM LEAK -- tracked, gate passes but DO NOT extend without rationale]"
    foreach ($v in $knownLeaks) {
        Write-Host ("    ~ {0} -> {1}" -f $v.PE, $v.MissingDep)
    }
}

if ($debugLeaks.Count -eq 0 -and $missingDeps.Count -eq 0) {
    Write-Host "==> PASS: every non-system dependency is bundled (known leaks tracked separately)."
    exit 0
}

Write-Host ""
Write-Host "==> FAIL: $(($debugLeaks.Count + $missingDeps.Count)) blocking unresolved dependency reference(s):"

if ($debugLeaks.Count -gt 0) {
    Write-Host ""
    Write-Host "  [DEBUG-RUNTIME LEAK -- Carl-class crash on clean Windows]"
    foreach ($v in $debugLeaks) {
        Write-Host ("    - {0} -> {1}" -f $v.PE, $v.MissingDep)
    }
    Write-Host "    Root cause: shipped artifact was built against the DEBUG CRT."
    Write-Host "    Fix: replace the third-party DLL with a Release-CRT build, OR"
    Write-Host "    add to `$knownDebugRuntimeLeaks with documented upstream tracking."
}

if ($missingDeps.Count -gt 0) {
    Write-Host ""
    Write-Host "  [MISSING -- bundle the DLL or extend system allowlist if it is a Windows component]"
    foreach ($v in $missingDeps) {
        Write-Host ("    - {0} -> {1}" -f $v.PE, $v.MissingDep)
    }
}

exit 1
