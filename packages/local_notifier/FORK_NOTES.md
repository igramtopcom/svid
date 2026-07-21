# Fork notes — SSvid/VidCombo vendored copy of `local_notifier`

This directory is a **vendored fork** of [`leanflutter/local_notifier`](https://github.com/leanflutter/local_notifier).
It is consumed as a `path:` dependency from the root `pubspec.yaml` and is
NOT published to pub.dev. Do not send upstream PRs against this directory —
they will be lost on the next upstream sync.

## Upstream baseline

| Field | Value |
|-------|-------|
| Upstream repo | https://github.com/leanflutter/local_notifier |
| Fork point | `0.1.6` (pub.dev release) |
| License | MIT (LiJianying, 2022-present) — preserved in `LICENSE` |
| Fork version | `0.1.6+ssvid.1` |

## Why we forked

Two Windows-only bugs in upstream `0.1.6` blocked our multi-brand toast
notification + identity story. Both root-caused by the same anti-pattern:
upstream conflates the Win32 `AppUserModelID` (AUMID) with the Flutter
`appName`, silently overriding any externally-set AUMID with the
`appName` string passed to `LocalNotifier.setup()`.

The host app (SSvid/VidCombo) sets a brand-specific AUMID at process
start via `SetCurrentProcessExplicitAppUserModelID(L"com.tinasoft.vidcombo.desktop")`
or `L"com.ssvid.app"` (see `lib/core/services/notification_service.dart`
+ `windows/runner/flutter_window.cpp`). Upstream blew this away inside
`WinToast::initialize`, which caused two visible production defects:

1. **Branded toast icons rendered as the host-app placeholder** — Windows
   resolves the toast icon by looking up the AUMID's LNK shortcut in the
   Start Menu. If AUMID drifts from the installer-created shortcut,
   Windows falls back to a generic placeholder.
2. **Stale Start-Menu LNK after brand swap / app move** — upstream
   created the LNK once on first run and never re-validated it, so an
   exe path change (uninstall/reinstall, dev brand switching) left the
   LNK pointing at a stale target/icon.

## Fork diffs

All runtime behavior changes are Windows-specific. The Dart API has one
backward-compatible optional argument so the host app can pass that Windows
identity through. `linux/` and `macos/` are **byte-identical** to upstream
0.1.6.

### 1. Dart API — new optional `appUserModelId` parameter

**File**: `lib/src/local_notifier.dart`

`setup({required String appName, String? appUserModelId, ...})` — backward
compatible. Existing upstream callers that pass only `appName` continue
to work. New callers (us) thread the brand AUMID through.

### 2. Native plugin — read AUMID arg + prefer process AUMID

**File**: `windows/local_notifier_plugin.cpp` (Setup handler)

- Reads `appUserModelId` arg from the method call.
- Defaults to `appName` if arg absent (upstream behaviour, backward compat).
- Overrides with `GetCurrentProcessExplicitAppUserModelID()` if the host
  has already set one. This wins over the method-call arg because
  process AUMID is the authoritative Win32 identity.
- Calls `WinToast::setAppUserModelId(...)` separately from `setAppName(...)`.

### 3. WinToast core — AUMID-not-appName everywhere

**File**: `windows/wintoastlib.cpp`

- `WinToast::initialize`: `SetCurrentProcessExplicitAppUserModelID(_aumi.c_str())`
  (upstream: `_appName.c_str()`). Single-line fix at the second
  hardcoding site.
- `validateShellLinkHelper`: when on-disk LNK AUMID differs from
  `_aumi`, rewrites `PKEY_AppUserModel_ID`. Under
  `SHORTCUT_POLICY_REQUIRE_CREATE` (SSvid/VidCombo default),
  unconditionally re-stamps `SetPath(exePath)` / `SetArguments(L"")` /
  `SetWorkingDirectory(workDir)` / `SetIconLocation(exePath, 0)` on
  every launch when dirty. Saves only when dirty.

### 4. Windows build system — required COM/Shell libraries

**File**: `windows/CMakeLists.txt`

Links `shell32.lib`, `ole32.lib`, and `propsys.lib` because the fork uses
Win32 shell-link, COM, and property-store APIs directly from the plugin
translation units.

### LNK re-stamping caveat (by design)

The repair is destructive to user customization on the Start-Menu LNK
under `REQUIRE_CREATE` policy:

- Clears `Arguments` to empty string on every launch.
- Overwrites `IconLocation` back to `exePath, 0`.
- Overwrites `WorkingDirectory` to repo bin dir.

Mitigation: `Util::defaultShellLinkPath` only touches
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\<appName>.lnk` — NOT
the user's taskbar pin (which lives elsewhere and is created via a
copy-and-pin operation that breaks the link). Power-user damage to the
Start-Menu shortcut is acknowledged and intentional: toast routing
requires AUMID + exe path consistency post-update/reinstall, and the
Start-Menu LNK is owned by the installer, not the user.

## Merge-back strategy

When upstream ships a release > 0.1.6:

1. Diff our `lib/src/local_notifier.dart` and `windows/` against upstream's
   new tree. Conflicts expected in `local_notifier.dart` (setup args),
   `local_notifier_plugin.cpp` (Setup), `wintoastlib.cpp` (initialize +
   validateShellLinkHelper), and possibly `windows/CMakeLists.txt`.
2. Replay the four fork diffs above on top of upstream's new code.
3. Update `version:` in `pubspec.yaml` to `<upstream>+ssvid.<N>`.
4. Append a new `## <upstream>+ssvid.<N>` block to `CHANGELOG.md`.
5. Update this `FORK_NOTES.md` with the new upstream baseline.
6. Filing the AUMID-not-appName fix upstream is encouraged but not
   blocking — the LNK repair is opinionated enough that upstream may
   reject it, in which case the fork stays.

## Upstream PR status

No upstream PR filed yet for either fix. If filed, link here.
