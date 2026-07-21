# Svid — Rebrand + Private-Video Capture Plan

> Handoff note. This repo (`igramtopcom/svid`, private) is a fresh, origin-detached
> copy of `mydinh-studio/ssvid-desktop`. Old `website/` + vendored AppImage removed.
> Two workstreams below. **Run all build/verify steps on a machine with `fvm flutter`,
> Rust (`cargo`), and Go installed** — they are required to validate each stage.

---

## Workstream A — Full-identity rebrand `ssvid` → `svid`

**Decision (owner):** FULL identity change, and rename the Dart package too.
So `Svid` becomes a new app identity (not just a display name).

**Consequences accepted:** existing SSvid installs will not auto-update to Svid;
old `ssvid.db` history is under a new DB name; `SSVID-` license keys must be
accepted for backward-compat (keep a legacy branch in `isValidLicenseKey`);
`api.svid.app` backend must exist before shipping.

### Architecture facts (why this is contained, not 2678 blind edits)
- Multi-brand via `--dart-define=BRAND=ssvid|vidcombo`. Identity is centralized:
  - `lib/core/config/brand_config.dart` — `enum Brand`, `SSvidBrand` class, all identity strings.
  - `macos/Runner/Configs/brands/ssvid.xcconfig` — macOS bundle identity.
  - `windows/runner/brand_config.h` (generated) + `scripts/set_brand.sh`.
  - `assets/brands/ssvid/` — logos/icons/tray.
- CLAUDE.md: "Adding a new brand… **zero Dart code changes** — all filenames, Sentry
  tags, exports derive from `BrandConfig.current`." So most user-facing strings follow
  automatically once `brand_config.dart` changes.

### Staged plan (commit + verify each stage)

**Stage 1 — Dart package rename** (`ssvid` → `svid`)
- `pubspec.yaml`: `name: ssvid` → `name: svid`; description.
- Rewrite 298 files: `package:ssvid/` → `package:svid/` (imports/exports).
- Verify: `fvm flutter pub get` → `fvm flutter analyze` (0 new errors).

**Stage 2 — Brand identity** (`lib/core/config/brand_config.dart` + `lib/` refs)
- `enum Brand { ssvid, vidcombo }` → add/rename `svid`; update `fromString` default,
  `_resolve` switch, and every `Brand.ssvid` reference in `lib/` (218 hits/65 files).
- `SSvidBrand` → `SvidBrand`; `appName 'SSvid'→'Svid'`; `databaseName 'ssvid'→'svid'`
  (⚠️ never add `.db` — see c8bbba91 regression assertion); `urlScheme 'ssvid'→'svid'`;
  `bundleId 'com.ssvid.app'→'com.svid.app'`; `windowsAppUserModelId`; `methodChannelPrefix`;
  backend URLs `api.ssvid.app`→`api.svid.app`; `websiteUrl`→`https://svid.app`;
  `versionCheckUrl`→`https://svid.app/version.json`; `backendAppName 'appSSvid'→'appSvid'`.
- License: `SSVID-` pattern → `SVID-`; hint/example strings. **Keep backward-compat**:
  in `isValidLicenseKey`, also accept legacy `SSVID-...` keys (mirror VidCombo's pattern).
- Default `BRAND` dart-define fallbacks `'ssvid'` → `'svid'`.
- Verify: `fvm flutter analyze`; run brand-config unit tests.

**Stage 3 — Platform configs**
- macOS: rename `macos/Runner/Configs/brands/ssvid.xcconfig` → `svid.xcconfig`; update
  `PRODUCT_BUNDLE_IDENTIFIER`, product/app name `ssvid.app`→`svid.app`, `com.example.ssvid`
  test hosts, url scheme in `Info.plist`, entitlements, `build_rust.sh`, scheme.
- Windows: regenerate `windows/runner/brand_config.h` (via set_brand.sh), update
  `CMakeLists.txt`, `main.cpp`, `installer_windows.iss`, capture/clipboard plugin identity.
- Linux: `linux/CMakeLists.txt`.
- Assets: `git mv assets/brands/ssvid assets/brands/svid` (+ any icon filenames).
- `scripts/set_brand.sh`: add/rename the `svid` case; update every build/package script
  (`package_*`, `release.sh`, `preflight_release.sh`) that hardcodes `ssvid`.
- Verify: `scripts/set_brand.sh svid` then `fvm flutter build macos/windows --dart-define=BRAND=svid`.

**Stage 4 — Native (Rust)** (`native/`, 4 hits) — grep + fix any `ssvid` string/path; `cargo check`.

**Stage 5 — Go backend** (`backend/`, 338 hits/87 files) — SEPARATE service:
- go module path if it embeds `ssvid`; `api.ssvid.app`→`api.svid.app`; device app name
  `appSSvid`→`appSvid`; license `SSVID-` validation (keep legacy accept); Stripe testdata
  fixtures are fine to leave. Verify: `go build ./...` + `go test ./...`.

**Stage 6 — Docs + tests** (docs 616, test 1086) — lower priority; update `SSVID-` license
  fixtures if Stage 2 dropped legacy acceptance (if kept, tests still pass). `fvm flutter test`.

**Final gate:** `scripts/verify_release_gates.sh` must pass green (per CLAUDE.md).

---

## Workstream B — IDM-style "capture the video that's playing" (private/authed video)

**Goal:** user plays their OWN private video (e.g. Facebook "only me") in the app's
browser and can download it, even though pasting the page URL fails (no session).

### Big finding: ~80% already exists and is wired up
- **In-app browser** (`lib/features/browser/`, 36 files): WebView2 (Windows, via
  `flutter_inappwebview` + persistent per-brand user-data dir from
  `webview_environment_service.dart`) / WKWebView (macOS, `webview_flutter`).
- **6-layer JS media interceptor** (`media_interceptor_service.dart`): PerformanceObserver,
  `fetch`/XHR monkey-patch, `<video>/<audio>` MutationObserver, MSE `addSourceBuffer`,
  SPA pushState. Wired in `browser_navigation_mixin.dart:71,337`; surfaced in
  `media_sniff_panel.dart` (premium-gated via `mediaSniffingEnabledProvider`).
- **HttpOnly cookie extraction from the WebView** (`lib/core/auth/data/native/native_cookie_extractor.dart`)
  — reads cookies JS can't see (WebView2 CookieManager / WKHTTPCookieStore). This is the key
  to private video.
- **Auto cookie capture on login** (`browser_cookie_auto_capture_service.dart`): on
  `onPageFinished`, detects FB `c_user`+`xs`, IG `sessionid`, YT `LOGIN_INFO`, etc., mirrors
  cookies into the `PlatformCookie` DB → later downloads pick them up.
- **Rust engine accepts cookies + Referer/Origin**: `native/src/api.rs:597`
  `download_start_with_headers`; direct/HLS engines (`engine.rs:99`, `hls_engine.rs:41`).
  The sniff panel's direct download already re-attaches WebView cookies
  (`media_sniff_panel.dart:891-921`).
- **yt-dlp fully cookie-aware**: `--cookies-from-browser` (`download_providers.dart:244`)
  + `--cookies <file>` from app DB via `cookie_exporter.dart`.
- **Clipboard floating capture popup** (`lib/features/floating_capture/`): separate, mature,
  triggers on URL copy (not on playing media).

### Gaps to close (the actual work)
1. **MSE/DASH + HttpOnly-signed segments** — FB private often uses MSE with short-lived
   signed CDN URLs; JS layer sees URL but not HttpOnly cookies, and blob playback may have
   no URL. `.mpd` (DASH) has no native engine (`hls_engine` = m3u8 only). Fix: route DASH/MSE
   items to **yt-dlp with the page URL + WebView cookies** (yt-dlp handles DASH natively),
   feeding cookies via `CookieExporter.exportPlatformCookies` (accepts raw Netscape).
2. **No native request interception** — everything is JS monkey-patch (can't read response
   headers / real cookies; some players evade it). Add native hooks:
   - Windows: `shouldInterceptAjaxRequest` / `onLoadResource` in
     `app_webview.dart:472` (`_WindowsWebViewController._buildRawInAppWebView`).
   - macOS: `WKURLSchemeHandler` / `decidePolicyForNavigationResponse`.
   - Surface via existing `interceptedMediaProvider.processMessage` +
     the unused `InterceptionSource.nativeHook` enum (`intercepted_media.dart:131`).
3. **FB "only me" first-class flow** — today it falls back to enabling media-sniff after a
   login failure (`browser_download_mixin.dart:90-101`). Make "log in → play → Download this
   video" a guided flow.
4. **Unify the two IDM subsystems** — bridge in-browser `MediaSniffPanel` detections into the
   floating-capture popup UX so "playing in browser" gets the same one-click popup as clipboard.

### Recommended feature sequencing
1. **Quick win:** ensure sniffed items reliably reuse WebView HttpOnly cookies on the yt-dlp
   path (not just Rust direct) — closes most FB/IG private cases with little code.
2. **DASH/MSE route** to yt-dlp + cookies.
3. **Native request interception** (headers + real cookies) — the robustness upgrade.
4. **UX unification** + first-class "capture playing video" flow.

### Key anchor files
- Interceptor JS: `lib/features/browser/domain/services/media_interceptor_service.dart`
- Wiring + auto cookie capture: `lib/features/browser/presentation/screens/browser_navigation_mixin.dart:71,258,337`
- Sniff-panel download entry: `lib/features/browser/presentation/widgets/media_sniff_panel.dart:760,891`
- HttpOnly cookies: `lib/core/auth/data/native/native_cookie_extractor.dart`
- yt-dlp cookie args: `lib/features/downloads/data/datasources/ytdlp_datasource.dart:1874,3710`
- Rust IDM engine: `native/src/api.rs:597`, `native/src/download/engine.rs:99`, `hls_engine.rs:41`
- WebView native-hook insertion point: `lib/features/browser/data/webview/app_webview.dart:472`

### Non-negotiables
- DRM (Widevine) content is not downloadable — do not attempt / advertise.
- Frame the feature as downloading content **the user has legitimate access to**
  (their own videos), consistent with the "no tracking, no catch" positioning.
