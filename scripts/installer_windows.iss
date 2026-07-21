; =============================================================================
; Multi-Brand Windows Installer — Inno Setup Script
; Builds professional installer EXE from Flutter release build
;
; Requirements: Inno Setup 6+ (https://jrsoftware.org/isinfo.php)
; Usage (SSvid — default):
;   iscc /DMyAppVersion=1.0.0 scripts/installer_windows.iss
; Usage (VidCombo):
;   iscc /DMyAppVersion=1.5.0 /DMyAppName=VidCombo /DMyAppExeName=vidcombo.exe /DMyAppPublisher=VidCombo /DMyAppURL=https://vidcombo.net /DMyAppId={{C6BC5050-3D98-47F7-8F1E-3DC53963381A} /DMyUrlScheme=vidcombo /DMyAppUserModelId=com.tinasoft.vidcombo.desktop scripts/installer_windows.iss
; =============================================================================

; Brand identity — all overridable via /D flags
#ifndef MyAppName
  #define MyAppName "SSvid"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "ssvid.exe"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "SSvid"
#endif
#ifndef MyAppCompany
  #define MyAppCompany "Bui Xuan Mai"
#endif
#ifndef MyAppProductName
  #define MyAppProductName "SSvid Desktop"
#endif
#ifndef MyAppFileDescription
  #define MyAppFileDescription "SSvid Desktop Installer"
#endif
#ifndef MyAppCopyright
  #define MyAppCopyright "Copyright (C) 2026 Bui Xuan Mai. All rights reserved."
#endif
#ifndef MyAppURL
  #define MyAppURL "https://ssvid.app"
#endif
#ifndef MyAppId
  #define MyAppId "{{A3D7F1E2-8B4C-4E5A-9F6D-2C1B3A4E5F6D}"
#endif
; Custom URL scheme for deep-link license activation (e.g. "ssvid://key=...")
; Must match lib/core/config/brand_config.dart `urlScheme` for the brand.
#ifndef MyUrlScheme
  #define MyUrlScheme "ssvid"
#endif
#ifndef MyAppUserModelId
  #if MyAppName == "VidCombo"
    #define MyAppUserModelId "com.tinasoft.vidcombo.desktop"
  #else
    #define MyAppUserModelId "com.ssvid.app"
  #endif
#endif

; Version is injected by CI via /D flag, fallback to 1.0.0
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

; Runtime bundle root to package into the installer. CI overrides this when
; building the installer from a pre-signed bundle artifact.
#ifndef MyBuildSource
  #define MyBuildSource "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppCopyright={#MyAppCopyright}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
VersionInfoCompany={#MyAppCompany}
VersionInfoCopyright={#MyAppCopyright}
VersionInfoDescription={#MyAppFileDescription}
VersionInfoOriginalFileName={#MyAppName}-{#MyAppVersion}-windows-x64-setup.exe
VersionInfoProductName={#MyAppProductName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoTextVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no
UsePreviousTasks=yes
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "launchonstartup"; Description: "Launch {#MyAppName} on Windows startup"; GroupDescription: "Other:"; Flags: unchecked

[Files]
; Flutter build output (includes all DLLs, data folder, etc.)
Source: "{#MyBuildSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; IconIndex: 0; AppUserModelID: "{#MyAppUserModelId}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; IconIndex: 0; Tasks: desktopicon; AppUserModelID: "{#MyAppUserModelId}"

[Registry]
; Launch on startup (optional)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: launchonstartup

; Custom URL protocol handler — register at INSTALL time so deep-link
; activation (e.g. ssvid://key=... or vidcombo://key=... from an email)
; works BEFORE the user ever launches the app. Without this, the runtime
; registration in StartupService only fires on first launch, leaving a
; gap where freshly-installed users hit "no handler for scheme". Values
; below mirror the runtime handler exactly so switching between paths is
; a no-op.
Root: HKCU; Subkey: "Software\Classes\{#MyUrlScheme}"; ValueType: string; ValueName: ""; ValueData: "URL:{#MyAppName} Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#MyUrlScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\{#MyUrlScheme}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"",0"
Root: HKCU; Subkey: "Software\Classes\{#MyUrlScheme}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
; Interactive install: show "Launch {App}" checkbox on the Finished page.
; The `postinstall` flag makes this an optional post-install item; Inno
; Setup silently skips ALL postinstall items when the wizard ran silent,
; so this entry never fires during `/VERYSILENT` runs (the auto-update
; code path). The explicit `skipifsilent` flag documents that behavior.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Silent install (auto-update flow — `/VERYSILENT`): the Finished page is
; skipped, so the entry above never fires. Without THIS entry an in-app
; update closes the running app via Restart Manager and then never
; reopens it — the user sees the app silently disappear after clicking
; "Update now". `skipifnotsilent` confines this relaunch to silent runs
; so interactive installs never double-launch.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent

[UninstallDelete]
; Clean up non-binary app data on uninstall.
; IMPORTANT: Do NOT delete {userappdata}\{#MyAppName}\{#MyAppName}
; (= getApplicationSupportDirectory) — it contains bin/ with yt-dlp,
; ffmpeg, gallery-dl (~120MB total). Wiping bin/ forces a full
; re-download on reinstall. Stale prefs/flags are handled by the
; installer marker mechanism (vidcombo_installer_ran.txt in %TEMP%).
Type: filesandordirs; Name: "{localappdata}\{#MyAppName}"
#if MyAppName == "VidCombo"
; Old VidCombo (Tinasoft/BLUEBYTE) app data — only in VidCombo builds.
Type: filesandordirs; Name: "{userappdata}\com.tinasoft.vidcombo"
#endif

[Code]
// ==========================================================================
// VidCombo Migration — Extract legacy license key + uninstall old app
//
// CRITICAL ORDERING: The old VidCombo uninstaller deletes its app data
// (%APPDATA%\com.tinasoft.vidcombo\) which contains the license key in
// settings1.gs. We MUST extract and save the key BEFORE uninstalling.
//
// Flow:
//   1. ExtractLegacyLicenseKey() → reads settings1.gs → saves to temp file
//   2. ScanUninstallPath() → finds and removes old VidCombo
//   3. New app launches → _importLegacyLicenseKey() reads temp file first
// ==========================================================================

// Read a JSON file and extract the "lisenceKey" value (typo is original).
// Inno Setup Pascal doesn't have a JSON parser, so we use simple string
// extraction — the key is always a 32-char hex string.
function ExtractKeyFromFile(const FilePath: String): String;
var
  Content: AnsiString;
  Marker: String;
  P, Q: Integer;
  Key: String;
begin
  Result := '';
  if not FileExists(FilePath) then Exit;
  if not LoadStringFromFile(FilePath, Content) then Exit;

  // Locate "lisenceKey" marker
  Marker := '"lisenceKey"';
  P := Pos(Marker, Content);
  if P = 0 then Exit;

  // Advance past the marker + colon to find the value
  // Format: "lisenceKey":"A3B9EE..." or "lisenceKey" : "A3B9EE..."
  P := P + Length(Marker);

  // Skip whitespace and colon
  while (P <= Length(Content)) and ((Content[P] = ' ') or (Content[P] = ':') or (Content[P] = #9)) do
    P := P + 1;

  // Expect opening quote
  if (P > Length(Content)) or (Content[P] <> '"') then Exit;
  P := P + 1;

  // Find closing quote
  Q := P;
  while (Q <= Length(Content)) and (Content[Q] <> '"') do
    Q := Q + 1;

  Key := Copy(Content, P, Q - P);

  // Validate: must be exactly 32 hex characters
  if Length(Key) <> 32 then Exit;

  Result := Key;
end;

// Scan known old VidCombo data directories for license key.
// Saves the key to %TEMP%\vidcombo_migrated_key.txt for the new app.
procedure ExtractLegacyLicenseKey();
var
  Key: String;
  Dirs: array of String;
  Files: array of String;
  I, J: Integer;
begin
  // Scan ALL known data directories from every BLUEBYTE VidCombo version.
  // The old app's VERSIONINFO varied across builds, so path_provider returned
  // different paths depending on CompanyName/ProductName:
  //   - CompanyName="com.VidCombo", ProductName="VidCombo" → %APPDATA%\com.VidCombo\VidCombo\
  //   - CompanyName=ProductName="VidCombo Youtube Downloader" → %APPDATA%\VidCombo Youtube Downloader\...
  //   - Bundle ID convention (macOS-style) → com.tinasoft.vidcombo
  // Cost: each non-existent path is a single FileExists() returning immediately.
  SetArrayLength(Dirs, 11);
  Dirs[0] := ExpandConstant('{userappdata}') + '\com.VidCombo\VidCombo';
  Dirs[1] := ExpandConstant('{userappdata}') + '\VidCombo Youtube Downloader\VidCombo Youtube Downloader';
  Dirs[2] := ExpandConstant('{userappdata}') + '\VidCombo Youtube Downloader';
  Dirs[3] := ExpandConstant('{userappdata}') + '\com.tinasoft.vidcombo';
  Dirs[4] := ExpandConstant('{userappdata}') + '\VidCombo\VidCombo';
  Dirs[5] := ExpandConstant('{userappdata}') + '\VidCombo';
  Dirs[6] := ExpandConstant('{userappdata}') + '\Vidcombo\Vidcombo';
  Dirs[7] := ExpandConstant('{userappdata}') + '\Vidcombo';
  Dirs[8] := ExpandConstant('{localappdata}') + '\com.VidCombo\VidCombo';
  Dirs[9] := ExpandConstant('{localappdata}') + '\com.tinasoft.vidcombo';
  Dirs[10] := ExpandConstant('{localappdata}') + '\Programs\VidCombo';

  SetArrayLength(Files, 5);
  Files[0] := 'settings1.gs';
  Files[1] := 'settings1.bak';
  Files[2] := 'settings.gs';
  Files[3] := 'settings.bak';
  Files[4] := 'settings.json';

  for I := 0 to GetArrayLength(Dirs) - 1 do
  begin
    for J := 0 to GetArrayLength(Files) - 1 do
    begin
      Key := ExtractKeyFromFile(Dirs[I] + '\' + Files[J]);
      if Key <> '' then
      begin
        // Save to %TEMP% — persists across installer phases and survives
        // the old app's uninstall. The new app reads this on first launch.
        SaveStringToFile(GetTempDir() + 'vidcombo_migrated_key.txt', Key, False);
        Log('Extracted legacy license key from ' + Dirs[I] + '\' + Files[J]);
        Exit;
      end;
    end;
  end;
end;

// Detect and silently uninstall old VidCombo (Tinasoft) before installing new version.
// Old VidCombo could have any AppId and any installer type (Inno Setup, NSIS, etc.).
// We search the Uninstall registry for entries whose DisplayName contains "VidCombo"
// but whose AppId differs from ours (i.e., not a previous version of THIS installer).

procedure UninstallOldEntry(const RootKey: Integer; const SubKey, DisplayName: String; const NeedElevation: Boolean);
var
  UninstString, ExePath: String;
  ResultCode: Integer;
begin
  if not RegQueryStringValue(RootKey, SubKey, 'UninstallString', UninstString) then Exit;
  ExePath := RemoveQuotes(UninstString);
  if ExePath = '' then Exit;

  Log('Removing old VidCombo: ' + DisplayName + ' (' + ExePath + '), elevated=' + IntToStr(Ord(NeedElevation)));

  if NeedElevation then
  begin
    // Old VidCombo was installed "for all users" (HKLM) — needs admin.
    // ShellExec with 'runas' triggers a single UAC prompt.
    if not ShellExec('runas', ExePath, '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      ShellExec('runas', ExePath, '/S', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end
  else
  begin
    // Per-user install — no elevation needed.
    if not Exec(ExePath, '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      Exec(ExePath, '/S', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure ScanUninstallPath(const RootKey: Integer; const BasePath: String; const SkipOurAppId, NeedElevation: Boolean);
var
  SubKeys: TArrayOfString;
  I: Integer;
  UninstPath, DisplayName, LowerName: String;
  OurAppId: String;
begin
  OurAppId := '{#MyAppId}';
  if not RegGetSubkeyNames(RootKey, BasePath, SubKeys) then Exit;

  for I := 0 to GetArrayLength(SubKeys) - 1 do
  begin
    UninstPath := BasePath + '\' + SubKeys[I];
    if RegQueryStringValue(RootKey, UninstPath, 'DisplayName', DisplayName) then
    begin
      // Case-insensitive match: old BLUEBYTE app uses "Vidcombo" (lowercase c),
      // not "VidCombo". Pos() is case-sensitive, so normalize to lowercase.
      LowerName := Lowercase(DisplayName);
      if (Pos('vidcombo', LowerName) > 0) then
      begin
        if SkipOurAppId and (Pos(OurAppId, SubKeys[I]) > 0) then
          Continue;
        UninstallOldEntry(RootKey, UninstPath, DisplayName, NeedElevation);
      end;
    end;
  end;
end;

function InitializeSetup(): Boolean;
begin
  if '{#MyAppName}' = 'VidCombo' then
  begin
    // STEP 0: Always write installer-ran marker to %TEMP%.
    // The new app uses this to reset stale migration state (one-shot import
    // flags, cached credentials) even if no license key was found. This
    // covers the "dirty machine" scenario where old VidCombo was already
    // uninstalled in previous test/upgrade cycles.
    SaveStringToFile(GetTempDir() + 'vidcombo_installer_ran.txt', '1', False);

    // STEP 1: Extract license key BEFORE uninstalling old VidCombo.
    // The old uninstaller deletes %APPDATA%\com.tinasoft.vidcombo\ which
    // contains settings1.gs with the license key. We must save it first.
    ExtractLegacyLicenseKey();

    // STEP 2: Uninstall old VidCombo from all registry hives.
    // HKCU native: skip our AppId (Inno Setup handles same-hive upgrade)
    ScanUninstallPath(HKEY_CURRENT_USER,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      True, False);

    // HKLM native (64-bit view): needs elevation to uninstall
    ScanUninstallPath(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      False, True);

    // HKLM WOW6432Node (32-bit view): old BLUEBYTE VidCombo was 32-bit,
    // registered under WOW6432Node — invisible to the 64-bit native scan.
    ScanUninstallPath(HKEY_LOCAL_MACHINE,
      'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
      False, True);
  end;
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  IconCacheLegacy, IconCacheModern: String;
  TaskbarPins: String;
begin
  if CurStep = ssPostInstall then
  begin
    // Aggressively refresh Windows icon cache. The old BLUEBYTE VidCombo
    // may have had a broken/placeholder icon that Windows cached. Without
    // clearing the cache, the new VidCombo inherits the stale placeholder
    // in the taskbar, Start Menu, and File Explorer — even though the new
    // .exe has the correct icon embedded in its resources.

    // Phase 1: Delete legacy icon cache (pre-Windows 10)
    IconCacheLegacy := ExpandConstant('{localappdata}') + '\IconCache.db';
    if FileExists(IconCacheLegacy) then
      DeleteFile(IconCacheLegacy);

    // Phase 2: Delete modern icon cache (Windows 10/11)
    // Files are often locked by Explorer — cmd /c with wildcard and error
    // suppression handles the lock gracefully. Explorer rebuilds them on
    // next login/restart.
    IconCacheModern := ExpandConstant('{localappdata}') + '\Microsoft\Windows\Explorer';
    Exec('cmd.exe', '/c del /f /a "' + IconCacheModern + '\iconcache_*.db" >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('cmd.exe', '/c del /f /a "' + IconCacheModern + '\thumbcache_*.db" >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // VidCombo has a long-lived legacy Windows footprint. If a user has a
    // stale VidCombo taskbar pin, Windows may group the new process under that
    // old pin and keep showing its cached icon even when the new exe resource
    // is correct. Remove only VidCombo-named taskbar pins; the installer
    // recreates Start Menu/Desktop shortcuts with the new AppUserModelID.
    if '{#MyAppName}' = 'VidCombo' then
    begin
      TaskbarPins := ExpandConstant('{userappdata}') + '\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar';
      Exec('cmd.exe', '/c del /f /q "' + TaskbarPins + '\*VidCombo*.lnk" >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;

    // Phase 3: Trigger shell icon refresh without killing Explorer. `-show`
    // covers modern Windows; `-ClearIconCache` covers older shells. Avoid
    // direct DLL imports here: Inno resolves external imports before showing
    // the wizard, so a shell32 import mismatch can make the installer fail at
    // startup before users can install.
    Exec('ie4uinit.exe', '-ClearIconCache', '', SW_HIDE, ewNoWait, ResultCode);
    Exec('ie4uinit.exe', '-show', '', SW_HIDE, ewNoWait, ResultCode);
  end;
end;
