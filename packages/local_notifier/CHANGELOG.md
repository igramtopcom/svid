## 0.1.6+ssvid.1

SSvid/VidCombo vendored fork (path dependency, not published to pub.dev).
See `FORK_NOTES.md` for upstream baseline + merge-back strategy.

* `[windows]` `LocalNotifier.setup()` accepts new optional `appUserModelId`
  parameter. The native plugin now threads this into
  `WinToast::setAppUserModelId()` separately from `setAppName()`, fixing
  upstream's hardcoded `_aumi = appName` that caused branded toast icons
  to render as the host-app placeholder when Dart had already set a
  brand-scoped AUMID via Win32 `SetCurrentProcessExplicitAppUserModelID`.
* `[windows]` `WinToast::initialize` now calls
  `SetCurrentProcessExplicitAppUserModelID(_aumi.c_str())` (was
  `_appName.c_str()` upstream — same hardcoding bug at a second site).
* `[windows]` `validateShellLinkHelper` (in `wintoastlib.cpp`) re-stamps
  the Start-Menu LNK on every launch when AUMID drifts: rewrites
  `PKEY_AppUserModel_ID`, and under `SHORTCUT_POLICY_REQUIRE_CREATE`
  unconditionally refreshes `SetPath(exePath)` / `SetArguments(L"")` /
  `SetWorkingDirectory(workDir)` / `SetIconLocation(exePath, 0)`. This
  closes the stale-shortcut path that left toast icons showing the
  pre-update icon after a brand swap or app move.
* `[linux]` `[macos]` Unchanged from upstream 0.1.6.

## 0.1.6

* Updates minimum supported SDK version to Flutter 3.3/Dart 3.0.
* Fixed deprecations and dependencies version #27

## 0.1.4

* [linux] Fixed build failed with error. #8

## 0.1.3

* [windows] Fix auto-create shortcut #5
* [windows] Add closeReason in onLocalNotificationClose event #6

## 0.1.2

* Implemented `close` method.
* Implemented `destroy` method.
* `LocalNotification` Add `onShow` event.
* `LocalNotification` Add `onClose` event.
* `LocalNotification` Add `onClick` event.
* `LocalNotification` Add `onClickAction` event.

## 0.1.1

* [macos] Support macOS < 10.15 #4

## 0.1.0

* First release.
