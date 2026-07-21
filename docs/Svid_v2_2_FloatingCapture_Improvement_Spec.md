# Svid v2.2 — Floating Capture Improvement Spec

**Version:** v1.1 (post ultra self-review — 23 issues fixed)
**Date:** 2026-05-07
**Status:** Approved direction; pending Stitch design review before Phase 2B implementation
**Companion to:**
- [Svid_v2_1_FloatingCapture_Spec.md](Svid_v2_1_FloatingCapture_Spec.md) (v2.1 base)
- [Svid_v2_1_FloatingCapture_Implementation_Status.md](Svid_v2_1_FloatingCapture_Implementation_Status.md) (current state, v2.1 — 287 tests passing on `v2/home-redesign-foundation`)
- [Svid_v2_2_FloatingCapture_Stitch_Brief.md](Svid_v2_2_FloatingCapture_Stitch_Brief.md) (visual brief)

**Author:** CTO Frontend (Desktop)
**Approver:** Chairman (anh My)

**v1.0 → v1.1 changelog (ultra self-review fixes):**
- C1: Phase order rebalanced — 2A is logic-only, 2B includes Stitch UI work, 2C polish (3 releases instead of 2)
- C2: Auth detection moved to yt-dlp extract failure (not oEmbed status) — oEmbed often returns 200 + bogus data for private content
- C3: Real codebase API names — `activePresetProvider`, `_repository.createDownload`, `binaryManagerProvider` — replaces guessed names
- C4: OG scraping uses realistic browser User-Agent; IG/FB explicitly accept Tier D fallback (privacy + likely block)
- C5: `_RecentUrlTracker` marks on **successful action**, not popup show — failed-then-retry within cooldown allowed
- C6: VidCombo brand color = `#0066CC` + `#03BEFE` (verified `brand_config.dart:795`); Svid + VidCombo both `freeDailyDownloads = 15` (memory `flutter-frontend.md` line "VidCombo=10" is OUT OF DATE per `brand_config.dart:633` code comment)
- M1-M9: Idle pause-on-hover, "Tuỳ chọn…" quota gate, Settings nested-target, IPC version handshake, telemetry endpoint verified, full auth matrix, drag-drop edge detection, snoozed-banner separate form factor, Stitch generation batched
- m1-m8: Verified 287 baseline; 4s auto-close instead of 2s; "browser tabs" metaphor instead of film negative; State 4 fallback for missing channel avatar; PII rules; YouTube/TikTok geo risk; cooldown 2-min default with override
- B1-B7 strategic decisions locked (see §10)

---

## 0. Executive Summary

Floating Capture v2.1 đã ship architecturally complete (4,210 LOC + 1,294 popup engine, 287 tests passing). Production verification trên hardware thật phát hiện **4 critical UX defects + 10 secondary gaps**. Spec này định nghĩa v2.2 — **không rebuild kiến trúc**, chỉ:

1. **Sửa root cause** của 4 critical defects (spam popup, indirect download, popup respawn, thumbnail majority broken)
2. **Đóng các security/memory gaps** (IPC allowlist, preview cache LRU)
3. **Reposition popup** từ "shortcut to main app" → "self-contained capture destination"
4. **Brand-aware visual** (VidCombo Arctic Blue popup, không hardcode Wine Red)
5. **Edge cases chưa cover** (offline, private video, multi-monitor, hot reload, quota=0)

Quy mô estimate: **~990 LOC modified/added**, ~52 test additions, **3 phases × 3 releases over 6 tuần**.

---

## 1. Problem Statement

### 1.1 Critical defects (verified from production hardware testing)

| # | Symptom | Root cause (file:line) | Fix phase |
|---|---------|----------------------|----------|
| C1 | Popup spam — copy 1 URL nhiều lần → queue tích tụ | `default_capture_service.dart:308-315` (no dedupe), `floating_window_main.dart:436-444` (queue dedupe absent) | 2A |
| C2 | Click "Download" → mở main app + Dialog, không tải thẳng | `home_screen.dart:135-143` (calls `startDownload()` which opens dialog) | 2B |
| C3 | Popup không tắt sau action — respawn từ queue cũ hoặc clipboard re-fire | Popup `_emitDownload` hide local nhưng KHÔNG remove khỏi queue; clipboard radar trên main side fire lại sau focus | 2A + 2B |
| C4 | Thumbnail chỉ có cho YouTube/Vimeo — IG/FB/Threads/Pinterest/Dailymotion/SoundCloud toàn placeholder | `lightweight_preview_service.dart:76-95` Tier-1/2 binary, Dailymotion + SoundCloud xếp Tier-2 sai, không có OG image fallback | 2A |

### 1.2 Secondary gaps

| # | Issue | Source | Fix phase |
|---|-------|--------|-----------|
| S1 | IPC URL allowlist gap | Codex P2 audit | 2A |
| S2 | `_previewCache` unbounded | Codex P2 audit | 2A |
| S3 | Settings idempotent — popup "Settings" khi đã ở Settings → vẫn focus + navigate (cộng với nested sub-section issue) | Self-audit | 2C |
| S4 | Snooze "Until I resume" không có toast feedback | Self-audit | 2B |
| S5 | Quota=0 paywall UI variant chưa làm | v2.1 deferred | 2C |
| S6 | Brand-aware chỉ ở `appName`, color luôn Wine Red | Self-audit | 2B |
| S7 | Cookies-aware private video (auth detection via yt-dlp extract, not oEmbed) | Self-audit + ultra-review C2 | 2C |
| S8 | Multi-monitor saved position single-slot, off-screen recovery | v2.1 deferred | 2C |
| S9 | Drag-drop URL từ browser → popup không support (with edge detection vs reposition gesture) | Self-audit + ultra-review M7 | 2C optional |
| S10 | Hotkey global force-show khi snoozed | Self-audit | 2C |

---

## 2. Vision — 3 Strategic Shifts

### Shift 1: Popup là DESTINATION, không phải SHORTCUT

**v2.1 (current)**: popup → user click Download → main app forward → Dialog → user phải chọn format → click Download lần 2 → tải.

**v2.2 (target)**: popup tự đủ cho 80% common case.
- 2 actions primary: **`[⚡ Tải ngay]`** + **`[⚙ Tuỳ chọn…]`**
- "Tải ngay" → trigger `StartCaptureDownloadDirectUseCase` (xem §3 Phase 2B): extract qua existing `start_download_usecase.dart` path → áp `activePresetProvider.currentConfig` → tạo download record + start → KHÔNG mở main app
- **Quan trọng (B2 fix)**: sau enqueue → call `notificationService.showDownloadStarted(filename: ...)` để user thấy macOS/Windows system notification kể cả khi không mở app
- "Tuỳ chọn…" → flow v2.1 (main app + dialog)
- Sau khi click "Tải ngay" → popup chuyển sang **Download Started state** (✓ icon + "Đang tải xuống Downloads/" + 4s tự đóng — adjustable)

### Shift 2: Anti-Spam Layered Defense (5 layers + safety valve)

5 lớp bảo vệ:

1. **URL-level dedupe trong ClipboardMonitorService** (Phase 2A): track 10 URLs gần nhất + 2-minute cooldown (default; override 30s/1m/2m/5m). Mark **chỉ khi user thực sự action thành công**, không phải khi popup show. Failed action → URL không vào blocklist → user copy lại retry được.
2. **Queue-level dedupe trong popup** (Phase 2A): `pushQueue` check `_queue.any((p) => p.rawUrl == preview.rawUrl)` → fast-forward `_selectedIndex` thay vì append.
3. **Clipboard noise debounce** (Phase 2A): nếu popup đang visible → clipboard change → đợi 1.5s confirm (clipboard không đổi tiếp) → mới push.
4. **Post-action respawn cooldown** (Phase 2A): sau khi user "Download"/"Open in App"/"Dismiss" → URL vào blocklist 60s.
5. **Idle auto-close** (Phase 2B — phụ thuộc UI state machine): popup không có user interaction 60s → tự ẩn. **Pause khi hover** (M1 fix). Settings adjustable: 30s / 60s / 120s / never.

**Safety valve**: Settings → "Reset all capture cooldowns" button → clear `_RecentUrlTracker` + post-action blocklist + clipboard debounce timer. Verbose debug log mỗi layer skip để diagnose khi user report "popup không xuất hiện".

### Shift 3: Thumbnail 4-tier strategy

Thay binary Tier-1/Tier-2:

```
Tier A — Canonical thumbnail từ ID (synchronous, không HTTP):
  YouTube  → img.youtube.com/vi/{id}/maxresdefault.jpg
  Vimeo    → vumbnail.com/{id}.jpg (3rd party CDN)
  TikTok   → có sau khi resolve short URL (giữ flow hiện tại)

Tier B — oEmbed (existing flow):
  Khi Tier A miss + platform supports public oEmbed
  Tier-1 expanded: +Dailymotion, +SoundCloud (cả 2 có public oEmbed)

Tier C — OG image meta tag scraping (with realistic browser UA):
  KHÔNG dùng cho Instagram, Facebook (block aggressive — accept Tier D)
  Dùng cho: Threads, Pinterest, LinkedIn, Bilibili
  Realistic UA: Mozilla/5.0 ... Chrome/120 (NOT 'Svid/2.1')
  Single GET, 5s timeout, single retry max
  Privacy: opt-in trong Settings (default ON, document trong privacy policy)

Tier D — Platform logo placeholder:
  Instagram, Facebook (always — Tier C confirmed blocked by Cloudflare bot detection)
  Last resort cho mọi platform khác
  Asset: assets/platform_logos/{platform}.svg (15 platforms)
  RÕ RÀNG — user biết "feature limited cho platform này, không phải bug"
```

---

## 3. Phase Plan (3 phases × 3 releases)

### Phase 2A — Logic-Only Critical Fix (no UI change) → ship v1.3.9

**Goal**: Sửa C1 (spam) + C4 (thumbnail) + S1/S2 (security/memory) **không cần Stitch design**, không thay UI cấu trúc → ship sớm 2 tuần.

**Why logic-only first**: tránh regression của Phase 2A standalone (ultra-review C1). User v1.3.9 vẫn thấy popup v2.1 UI nhưng đã hết spam, có thumbnail đẹp cho IG/FB/Threads, IPC secure. Direct download path + visual redesign chờ Phase 2B.

#### 2A.1 — URL dedupe + cooldown (Shift 2 layer 1)

**New file:** `lib/features/floating_capture/domain/services/recent_url_tracker.dart`

```dart
/// Tracks recently-actioned URLs to prevent popup spam when user
/// repeatedly copies the same link. Mark on SUCCESSFUL action only
/// (Download / OpenInApp click), NOT on popup show — that way a
/// failed download retry within cooldown still triggers popup.
class RecentUrlTracker {
  final Duration cooldown;
  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<String, DateTime> _recent = LinkedHashMap();

  RecentUrlTracker({
    this.cooldown = const Duration(minutes: 2), // default — Settings override
    this.maxEntries = 10,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool isRecentlyActioned(String url) {
    _evictExpired();
    final t = _recent[url];
    return t != null && _now().difference(t) < cooldown;
  }

  void markActioned(String url) {
    _evictExpired();
    if (_recent.length >= maxEntries) _recent.remove(_recent.keys.first);
    _recent.remove(url); // re-insert at end (most recent)
    _recent[url] = _now();
  }

  void clear() => _recent.clear();

  void _evictExpired() {
    final now = _now();
    _recent.removeWhere((_, t) => now.difference(t) >= cooldown);
  }
}
```

**Wiring**: inject vào `DefaultCaptureService` (constructor param). Hook trong `_onWindowEvent`:
- `DownloadClicked` → `_recentUrlTracker.markActioned(url)` SAU khi sideEffect emit thành công
- `OpenInAppClicked` → tương tự
- `_handleClipboardEvent` đầu vào → check `isRecentlyActioned` → skip nếu true

**Settings exposure** (Phase 2A.7 below): cooldown duration trong Settings card.

**Tests** (`recent_url_tracker_test.dart`):
- Mark on action → blocked within cooldown
- Failed action (no mark) → not blocked → user can retry
- Eviction: oldest-out when over capacity
- Clock drift: `_now()` returns past → no crash
- Clear bypasses

#### 2A.2 — Queue dedupe trong popup (Shift 2 layer 2)

**File:** `lib/floating_window_main.dart:433-446`

```dart
case 'pushQueue':
  if (call.arguments is Map) {
    final preview = _PreviewState.fromJson(...);
    final existingIdx = _queue.indexWhere((p) => p.rawUrl == preview.rawUrl);
    if (existingIdx >= 0) {
      // v2.2 fix: don't append duplicate — fast-forward to existing entry
      setState(() => _selectedIndex = existingIdx);
      return;
    }
    setState(() {
      _queue.add(preview);
      while (_queue.length > _kMaxQueueSize) {
        _queue.removeAt(0);
        if (_selectedIndex > 0) _selectedIndex--;
      }
    });
  }
```

**Tests** (`mock_floating_window_test.dart` extend): duplicate URL not appended; selectedIndex moves to existing entry; non-duplicate appends normally.

#### 2A.3 — Clipboard noise debounce (Shift 2 layer 3)

**File:** `lib/features/floating_capture/data/datasources/default_capture_service.dart`

Thêm `Timer? _debounceTimer; String? _pendingUrl;`

Khi `clipboardSource` emit URL:
- Cancel `_debounceTimer`
- Set `_pendingUrl = url`
- Start 1500ms timer → on fire: nếu `clipboardSource.current == _pendingUrl` (chưa đổi) → proceed `_handleUrl(_pendingUrl!)`; nếu đổi → skip (debounce won)

**Tests**: 2 fast clipboard changes within 1.5s → only second proceeds; same URL twice within 1.5s → 1 popup show.

#### 2A.4 — Post-action respawn cooldown (Shift 2 layer 4)

**File:** `lib/features/floating_capture/data/datasources/default_capture_service.dart`

Thêm `final Map<String, DateTime> _postActionBlocklist = {};`

Trong `_onWindowEvent` cho mọi event terminal (Download/OpenInApp/PopupDismissed):
```dart
_postActionBlocklist[url] = _now().add(const Duration(seconds: 60));
```

Trong `_handleClipboardEvent` đầu: nếu `_postActionBlocklist[url] != null && _postActionBlocklist[url]!.isAfter(_now())` → skip.

Cleanup expired entries định kỳ hoặc lazy in `_handleClipboardEvent`.

#### 2A.5 — Thumbnail 4-tier strategy (Shift 3)

**File:** `lib/features/floating_capture/data/datasources/lightweight_preview_service.dart`

Replace Tier-1/2 binary với 4-tier method (xem `Shift 3` for tier table). Realistic User-Agent constant:

```dart
static const _browserUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
```

Implementation outline:
```dart
Future<VideoPreview> fetchPreview(String url) async {
  final c = _urlPattern.classify(url);

  if (c.urlType == UrlType.notUrl || c.urlType == UrlType.unknown) {
    return _buildFallbackPreview(c);
  }

  // Tier A — canonical thumb from itemId
  final tierA = _tierAThumbnail(c);

  // Tier B — oEmbed (now includes Dailymotion + SoundCloud)
  if (_supportsOEmbed(c.platform) && c.urlType == UrlType.video) {
    final fetched = await _fetchOEmbed(c);
    if (fetched != null) {
      // Prefer Tier A thumb if available (higher resolution for YT/Vimeo)
      return tierA != null
          ? fetched.copyWith(thumbnailUrl: tierA)
          : fetched;
    }
  }

  // Tier A standalone (no oEmbed support / oEmbed failed but ID known)
  if (tierA != null) {
    return _buildFallbackPreview(c).copyWith(thumbnailUrl: tierA);
  }

  // Tier C — OG image scrape
  if (_supportsOgImageScrape(c.platform) && c.urlType == UrlType.video) {
    final og = await _fetchOgImage(c.rawUrl);
    if (og != null) {
      return _buildFallbackPreview(c).copyWith(thumbnailUrl: og);
    }
  }

  // Tier D — platform logo placeholder
  return _buildFallbackPreview(c).copyWith(
    thumbnailUrl: 'asset:platform_logos/${c.platform.name}.svg',
  );
}

bool _supportsOEmbed(VideoPlatform p) {
  switch (p) {
    case VideoPlatform.youtube:
    case VideoPlatform.vimeo:
    case VideoPlatform.tiktok:
    case VideoPlatform.twitter:
    case VideoPlatform.reddit:
    case VideoPlatform.dailymotion:  // NEW v2.2
    case VideoPlatform.soundcloud:   // NEW v2.2
      return true;
    default:
      return false;
  }
}

bool _supportsOgImageScrape(VideoPlatform p) {
  // Instagram + Facebook block aggressive (Cloudflare bot detection).
  // We accept Tier D for them — see ultra-review C4.
  switch (p) {
    case VideoPlatform.threads:
    case VideoPlatform.pinterest:
    case VideoPlatform.linkedin:
    case VideoPlatform.bilibili:
      return true;
    default:
      return false;
  }
}
```

**oEmbed endpoint registry update**:
- Dailymotion: `https://www.dailymotion.com/services/oembed?url={url}`
- SoundCloud: `https://soundcloud.com/oembed?url={url}&format=json`

**Tests**:
- `lightweight_preview_service_test.dart` extend: 4-tier ordering per platform
- New `og_image_scraper_test.dart`: parse common HTML, malformed, missing meta, redirects, realistic UA header sent

#### 2A.6 — IPC URL allowlist (S1)

**File:** `capture_side_effect_router.dart`

```dart
case OpenExternalUrl(:final url):
  final classification = _urlPattern?.classify(url);
  if (!_isSafeUrl(url, classification)) {
    appLogger.warning('[CaptureRouter] OpenExternalUrl blocked: $url');
    return; // silently drop — never propagate untrusted URL
  }
  await _invoke('OpenExternalUrl', onOpenExternal, (cb) => cb(url));
```

```dart
bool _isSafeUrl(String url, UrlClassification? c) {
  try {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (c?.platform == VideoPlatform.unknown || c == null) return false;
    return true;
  } catch (_) {
    return false;
  }
}
```

Inject `UrlPatternService` into router.

**Tests** (`capture_side_effect_router_test.dart` extend): file:// blocked, javascript: blocked, unknown host blocked, valid YouTube URL passes.

#### 2A.7 — `_previewCache` LRU bounded (S2)

**File:** `default_capture_service.dart`

Replace `Map<String, VideoPreview> _previewCache = {}` với:

```dart
final _LruCache<String, VideoPreview> _previewCache = _LruCache(32);
```

Implementation: `LinkedHashMap`-backed move-to-end on read, evict oldest on write.

**Tests** (`lru_cache_test.dart`): basic put/get, capacity eviction order, get-promotes-to-most-recent.

#### 2A.8 — Settings Card additions

**File:** `floating_capture_settings_card.dart`

Add 2 controls:
- **"Anti-spam cooldown"** — Dropdown 30s / 1 phút / 2 phút (default) / 5 phút. Stored trong `CapturePreferences.recentUrlCooldown`.
- **"Reset all cooldowns"** — Button. Calls `defaultCaptureServiceProvider.notifier.resetCooldowns()` which clears `_RecentUrlTracker` + `_postActionBlocklist`.

i18n keys: `settingsCaptureAntiSpamCooldown`, `settingsCaptureResetCooldowns`.

#### Phase 2A acceptance criteria

- [ ] All 287 v2.1 tests still pass
- [ ] +18 new tests added (RecentUrlTracker 5, queue dedupe 4, debounce 3, allowlist 3, LRU 3)
- [ ] `flutter analyze` clean (output mentions "snakeloader")
- [ ] Manual smoke macOS: copy YouTube URL 3x → only 1 popup; copy IG URL → Tier D logo shown; click Download → flow as before (no UI change)
- [ ] Manual smoke Windows: same
- [ ] VidCombo brand build: same flow OK
- [ ] Ship target: **v1.3.9 (Svid) + v1.6.6 (VidCombo)** — tentative 2026-05-21

### Phase 2B — Visual Redesign + Direct Download Path → ship v1.4.0

**Goal**: Stitch design freeze → implement 10 state variants × 2 brands → wire direct download path → fix C2 + C3 + S4 + S6.

#### 2B.0 — Stitch design (gate before code)

Generate 20 screens (10 states × 2 brands) per Stitch creative brief. **Sequence**:
1. Generate State 2 (default success) for Svid → Chairman approve hero
2. Generate State 2 for VidCombo → Chairman confirm brand parity
3. Parallel generate other 9 states × 2 brands (18 more screens)
4. Stitch export design tokens → CTO consume

**Cost note**: ~10-40 phút Stitch compute. Em pause at this gate per Chairman directive.

#### 2B.1 — Brand-aware popup theme

**File:** `lib/core/config/brand_config.dart`

Extend `BrandConfig` abstract:
```dart
abstract class BrandConfig {
  // ... existing
  Color get popupAccentColor;        // Primary action bg
  Color get popupAccentForeground;   // Primary action text
  Color get popupBrandDot;           // 8pt brand dot in top bar
  String get popupAccentGradientHex; // For gradient overlays (paywall)
}
```

`SvidBrand`:
```dart
@override Color get popupAccentColor => const Color(0xFF8D021F);     // Wine Red
@override Color get popupAccentForeground => Colors.white;
@override Color get popupBrandDot => const Color(0xFF8D021F);
```

`VidComboBrand` (real color from `brand_config.dart:795` gradient):
```dart
@override Color get popupAccentColor => const Color(0xFF0066CC);     // Ocean Blue
@override Color get popupAccentForeground => Colors.white;
@override Color get popupBrandDot => const Color(0xFF03BEFE);        // Cyan dot
```

**File:** `floating_window_main.dart`

Replace hardcoded `AppColors.wineRed` references với `BrandConfig.current.popupAccentColor`. The popup engine boots with brand initialized (already done v2.1).

**Reviewer checklist trong PR** (per §7):
- grep `0x..8D021F\|wineRed\|crimson` trong popup files modified — chỉ được trong `app_colors.dart` (token def) hoặc `svid_brand_config.dart`
- Run `scripts/dev.sh vidcombo` → screenshot popup → verify Ocean Blue (not Wine Red leak)

#### 2B.2 — `StartCaptureDownloadDirectUseCase` (Shift 1 implementation)

**New file:** `lib/features/floating_capture/domain/usecases/start_capture_download_direct_usecase.dart`

```dart
/// Direct path: extract → apply active FormatPreset → create download
/// record → start. Bypasses HomeScreen.startDownload (which opens
/// Download Options Dialog).
///
/// Real codebase API names (verified via grep, not guessed):
/// - extraction: extract_video_info_usecase.ExtractVideoInfoUseCase
/// - preset: activePresetProvider (Riverpod) → state.currentConfig
/// - create+start: download_repository.createDownload + startDownload
/// - binaries: binaryManagerProvider (auto-init lazily — no explicit ready check)
/// - notification: notificationService.showDownloadStarted
class StartCaptureDownloadDirectUseCase {
  final ExtractVideoInfoUseCase _extract;
  final DownloadRepository _repository;
  final ActivePresetState Function() _readActivePreset;
  final NotificationService _notification;
  final AnalyticsService _analytics;

  StartCaptureDownloadDirectUseCase({
    required ExtractVideoInfoUseCase extract,
    required DownloadRepository repository,
    required ActivePresetState Function() readActivePreset,
    required NotificationService notification,
    required AnalyticsService analytics,
  })  : _extract = extract,
        _repository = repository,
        _readActivePreset = readActivePreset,
        _notification = notification,
        _analytics = analytics;

  Future<Result<DownloadEntity>> call(CaptureDownloadRequest req) async {
    _analytics.track('floating_capture.direct_download_attempt', {
      'platform': req.preview.platform.name,
      // PRIVACY: do NOT log raw URL — log platform + state only
    });

    // 1. Extract via existing yt-dlp pipeline
    final infoResult = await _extract.call(req.preview.rawUrl);
    if (infoResult.isFailure) {
      // Auth-required detection (C2 fix): yt-dlp error message includes
      // "Sign in" / "Private video" / "members-only" → distinct result type
      final err = infoResult.failure!;
      if (_isAuthRequiredError(err)) {
        _analytics.track('floating_capture.direct_download_auth_required', {
          'platform': req.preview.platform.name,
        });
        return Failure(AuthRequiredError(originalError: err));
      }
      return infoResult.cast();
    }

    // 2. Resolve active preset
    final presetState = _readActivePreset();
    final presetConfig = presetState.currentConfig;

    // 3. Build CreateDownloadRequest from preset + extracted info
    final createReq = _buildCreateDownloadRequest(
      info: infoResult.value!,
      preset: presetConfig,
      sourceUrl: req.preview.rawUrl,
    );

    // 4. createDownload + startDownload (mirrors start_download_usecase path)
    final created = await _repository.createDownload(createReq);
    if (created.isFailure) return created.cast();

    final started = await _repository.startDownload(created.value!.id);
    if (started.isFailure) {
      _analytics.track('floating_capture.direct_download_start_failed', {
        'platform': req.preview.platform.name,
        'error_code': started.failure!.code,
      });
      return started.cast();
    }

    // 5. System notification (B2 fix — user feedback even when main app hidden)
    await _notification.showDownloadStarted(
      filename: created.value!.filename ?? 'video',
    );

    _analytics.track('floating_capture.direct_download_started', {
      'platform': req.preview.platform.name,
    });

    return Success(created.value!);
  }

  bool _isAuthRequiredError(Failure err) {
    final msg = err.message.toLowerCase();
    return msg.contains('sign in') ||
           msg.contains('private video') ||
           msg.contains('members-only') ||
           msg.contains('login required') ||
           msg.contains('age-restricted');
  }

  CreateDownloadRequest _buildCreateDownloadRequest({
    required VideoInfo info,
    required PresetConfig preset,
    required String sourceUrl,
  }) {
    // Pick format using preset rules (mirrors home_download_mixin logic)
    final selectedFormat = preset.selectFormat(info.qualities);
    return CreateDownloadRequest(
      url: sourceUrl,
      format: selectedFormat,
      preset: preset,
      // Telemetry hint
      capturedFromFloatingPopup: true,
    );
  }
}
```

**Important caveat (m8 fix)**: `FormatPreset` covers format/quality/folder/filename pattern. Does NOT cover trim time range, custom subtitle language, audio-only override per-download. **For 80% case (default download), preset is sufficient**. Power users wanting custom config click "Tuỳ chọn…" → flow v2.1 dialog.

**Wiring** (`lib/main.dart` capture router override):

```dart
captureSideEffectRouterProvider.overrideWith(
  (ref) => buildDefaultCaptureSideEffectRouter(
    onDownload: (request) async {
      if (request.directDownload) {
        // Phase 2B: direct path (B2 fix — notification flow)
        final result = await ref
            .read(startCaptureDownloadDirectUseCaseProvider)
            .call(request);

        // Route result back to popup state machine
        ref.read(captureWindowStateProvider.notifier).updateActionResult(
              result.isSuccess
                  ? PopupActionResult.started(filename: result.value!.filename)
                  : (result.failure is AuthRequiredError
                      ? const PopupActionResult.authRequired()
                      : PopupActionResult.failed(result.failure!.message)),
            );
        return;
      }
      // Legacy v2.1 path: pre-fill HomeScreen + open dialog
      ref.read(pendingCaptureDownloadProvider.notifier).state = request;
    },
    // ... other handlers unchanged
  ),
),
```

**`CaptureDownloadRequest`** entity extension:
```dart
class CaptureDownloadRequest {
  // ... existing
  final bool directDownload;  // NEW: true = bypass dialog, false = legacy path
  // default true for popup primary action
}
```

#### 2B.3 — `PopupActionResult` sealed entity + IPC

**New file:** `lib/features/floating_capture/domain/entities/popup_action_result.dart`

```dart
sealed class PopupActionResult {
  const PopupActionResult();
}

class PopupActionStarted extends PopupActionResult {
  final String filename;
  const PopupActionStarted({required this.filename});
}

class PopupActionCompleted extends PopupActionResult {
  final String filename;
  final String savedPath;
  const PopupActionCompleted({required this.filename, required this.savedPath});
}

class PopupActionFailed extends PopupActionResult {
  final String message;
  const PopupActionFailed(this.message);
}

class PopupActionAuthRequired extends PopupActionResult {
  const PopupActionAuthRequired();
}
```

**IPC method** (M4 fix — version handshake):

`desktop_multi_window_floating_window.dart`:
```dart
Future<void> setActionResult(PopupActionResult result) async {
  _ensureNotDisposed('setActionResult');
  try {
    await _invoke('setActionResult', result.toJson());
  } catch (e) {
    // Old popup engine doesn't have handler — silently ignore.
    // Bundled release ensures popup + main same version, so this is
    // defensive only.
    appLogger.debug('[FloatingCapture] setActionResult ignored: $e');
  }
}
```

**Popup side** (`floating_window_main.dart`): handle `setActionResult` method → switch UI to corresponding state variant (State 6/7/8).

#### 2B.4 — 10 state variants implementation

Per Stitch design tokens. State enum:

```dart
enum FloatingPopupState {
  loading,             // State 1
  videoPreview,        // State 2 (default)
  fallbackPreview,     // State 3
  nonVideoUrl,         // State 4
  quotaPaywall,        // State 5
  downloadStarted,     // State 6 (via PopupActionStarted)
  downloadComplete,    // State 7 (via PopupActionCompleted)
  downloadFailed,      // State 8 (via PopupActionFailed)
  authRequired,        // State 8b (via PopupActionAuthRequired) — variant of failed
  snoozedBanner,       // State 9 (separate compact form factor 300×120)
  offline,             // State 10
}
```

**State 6 auto-close** (m2 fix): 4 seconds (not 2s — too rushed). Cancellable by hover.
**State 9 form factor** (M8 fix): popup sizing logic switches to 300×120 when `state == snoozedBanner`. Use `windowManager.setSize(...)` with brief animation.

#### 2B.5 — Idle auto-close with hover pause (M1 fix)

```dart
class _IdleTimer {
  Timer? _timer;
  final Duration timeout;
  final VoidCallback onTimeout;
  bool _hovering = false;

  _IdleTimer(this.timeout, this.onTimeout);

  void onUserActivity() {
    if (_hovering) return; // pause while hovering
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void onHoverEnter() {
    _hovering = true;
    _timer?.cancel();
  }

  void onHoverExit() {
    _hovering = false;
    onUserActivity(); // restart
  }

  void dispose() => _timer?.cancel();
}
```

Hook in popup root `MouseRegion(onEnter: ..., onExit: ...)` + on every gesture (click, drag).

#### 2B.6 — Snooze "Until I resume" toast (S4)

**File:** `default_capture_service.dart`

After `snoozeFor(SnoozeDuration.untilResumed)`, emit `_safeEmit(ShowSnoozeToast())` (new `CaptureSideEffect` variant).

**Router** (main.dart capture router override):
```dart
onShowSnoozeToast: () async {
  await notificationService.show(
    title: 'Floating capture đã tạm dừng',
    body: 'Click tray icon → "Resume capture" để bật lại.',
  );
},
```

#### Phase 2B acceptance criteria

- [ ] Stitch 20 screens approved by Chairman
- [ ] All 287 + 18 (Phase 2A) tests still pass
- [ ] +20 new tests (direct download usecase 8, popup states widget tests 10, idle timer 2)
- [ ] Brand parity: VidCombo build screenshots show Ocean Blue accent everywhere
- [ ] Manual smoke macOS: copy URL → Tier A thumb → click "Tải ngay" → popup shows "Đang tải xuống Downloads/" → 4s auto-close → system notification "Download started" appears → main app Downloads tab shows running download (verify without focus-stealing)
- [ ] Manual smoke Windows: same
- [ ] VidCombo build smoke
- [ ] Ship target: **v1.4.0 (Svid) + v1.7.0 (VidCombo)** — tentative 2026-06-04

### Phase 2C — Polish + Edge Cases → ship v1.4.1

#### 2C.1 — Quota=0 paywall (S5)

**File:** `floating_window_main.dart` State 5 implementation per Stitch design.

When `_quotaRemaining == 0`:
- Primary button: `[👑 Nâng cấp Premium]` (gold/amber accent overlay)
- Both brands use Stripe checkout (B4 fix — VidCombo `hasStripeCheckout: true` confirmed `brand_config.dart:638`)
- Click → invokeMethod('onUpgradeClicked')
- Main side router: `OpenExternalUrl(BrandConfig.current.upgradeUrl)`
  - Svid → `https://svid.app/premium`
  - VidCombo → `https://vidcombo.net/premium`

**"Tuỳ chọn…" cũng gate** (M2 fix): when quota=0, hide secondary button OR change label to "Mở app (giới hạn còn lại 0)" — disable enqueue, allow user to see Downloads tab.

#### 2C.2 — Cookies-aware private video (S7, C2 fix)

Already partially done in §2B.2 (auth detection in `StartCaptureDownloadDirectUseCase` via yt-dlp error message). Phase 2C adds:

- **State 8b (auth required)**: distinct UI variant — "Video private — mở trong app để dùng cookies đã đăng nhập"
- Primary button: **`Mở trong app`** (forwards to legacy path with `directDownload: false` + dialog)

**Auth matrix** (M6 fix — full coverage):

| Video state | Has cookies in app | Direct path | Dialog path |
|------------|-------------------|-------------|-------------|
| Public | N/A | ✅ Works | ✅ Works |
| Age-restricted | Maybe (cookies bypass age gate sometimes) | ⚠️ Try direct, on fail → State 8b | ✅ Works (dialog passes cookies) |
| Members-only / private | Required | ❌ State 8b — direct never works without cookies | ✅ Works |
| DRM-protected (Hulu/Netflix) | N/A | ❌ State 8 — yt-dlp can't bypass DRM | ❌ Same |

#### 2C.3 — Settings idempotent + nested target (S3, M3 fix)

**File:** `lib/main.dart` `onOpenSettings` handler:

```dart
onOpenSettings: () async {
  // Always navigate to Settings tab + scroll to capture section
  // (M3: even if user already on Settings/General, must scroll to Capture sub-section)
  if (!await windowManager.isVisible()) {
    await WindowService.show();
  }
  container.read(navigationProvider.notifier).navigateToTab(NavigationConstants.settingsIndex);
  // Scroll target — set hint provider, settings screen reads + scrolls
  container.read(settingsScrollTargetProvider.notifier).state =
      SettingsSection.floatingCapture;
},
```

**New provider** (`lib/features/settings/presentation/providers/settings_scroll_target_provider.dart`): one-shot `StateProvider<SettingsSection?>`. Settings screen `WidgetsBinding.instance.addPostFrameCallback` reads + scrolls to section + clears.

#### 2C.4 — Multi-monitor saved position (S8)

**File:** `lib/features/floating_capture/domain/entities/window_position.dart`

```dart
class WindowPosition {
  final double dx;
  final double dy;
  final String? displayId;  // NEW v2.2 — null = legacy data
  // ...
}
```

**Load logic** (in `shared_preferences_window_position_store.dart`):
- Read displays via `screen_retriever` package or platform channel (need to verify availability)
- If `saved.displayId` matches a current display → use saved position
- Else if no displayId (legacy) → bounds-check against any current display → use if in-bounds
- Else → fallback `Alignment.topRight + 24px margin` of primary display

**Tests** (`window_position_test.dart` extend): 3 cases above.

#### 2C.5 — Hotkey global force-show (S10) + Onboarding (B5 fix)

**File:** `keyboard_service.dart`

Add system-scope hotkey (default disabled — opt-in per B5):
- macOS default suggestion: `Cmd+Shift+F` (D conflicts with Mission Control on some setups)
- Windows: `Ctrl+Shift+F`

**On trigger**:
1. Read clipboard → if URL via `UrlPatternService.classify()` → bypass snooze + cooldown → `_handleUrl(url, force: true)`
2. If no URL → spawn empty popup with "Copy a video URL to capture"

**First-launch onboarding** (Phase 2C.5b): Settings → "Floating Capture" section → toggle "Enable global hotkey":
- Off (default) → no system permission prompt
- On → request macOS Accessibility permission → if denied → toast "Permission required" + fallback to off

**File:** `lib/features/floating_capture/presentation/widgets/global_hotkey_onboarding_dialog.dart` — modal explaining why permission needed.

**Hotkey conflict handling**: if `hotkey_manager.register()` throws `HotKeyConflictException` → toast "Hotkey đã được dùng bởi app khác — chọn hotkey khác trong Settings".

#### 2C.6 — Drag-drop URL into popup (S9, M7 fix)

**File:** `floating_window_main.dart`

Wrap popup root với `DropTarget` (package `desktop_drop`).

**Edge detection** (M7 fix vs reposition gesture):
- Drag from EXTERNAL source (browser address bar URL drag) → DropTarget callback fires `onDragEntered` with text/uri-list MIME
- Drag from popup itself (reposition) → uses `windowManager.startDragging()` → no DropTarget callback
- These are mutually exclusive on macOS by design — no conflict in practice

**Visual affordance**: when external drag detected → show overlay "Drop URL here to capture" → on drop → invokeMethod('onUrlDropped', {'url': ...}) → main side `_handleUrl(url, force: true)`.

**Defer to Phase 3 if Windows test fails** (M7 risk).

#### Phase 2C acceptance criteria

- [ ] All previous tests pass (287 + 38 = 325)
- [ ] +14 new tests (paywall 4, auth matrix 4, multi-monitor 3, hotkey 3)
- [ ] Manual smoke: paywall flow both brands, auth-required flow, multi-monitor disconnect, hotkey opt-in flow, drag-drop (macOS first, Windows if stable)
- [ ] Ship target: **v1.4.1 (Svid) + v1.7.1 (VidCombo)** — tentative 2026-06-18

---

## 4. Architecture Diff (v2.1 → v2.2 final)

### Component changes

```
                       v2.1                            v2.2 (after all phases)
ClipboardMonitorService                                + RecentUrlTracker dependency
                                                       + 1.5s clipboard noise debounce
DefaultCaptureService    _previewCache: Map            _LruCache(32)
                         no respawn cooldown           + _postActionBlocklist with 60s window
                                                       + emits ShowSnoozeToast effect
                                                       + emits PopupActionResult IPC
LightweightPreviewService Tier-1/Tier-2 binary         + Tier A canonical thumb (YT/Vimeo)
                                                       + Tier C OG scrape (Threads/Pinterest/LI/Bili)
                                                       + Realistic browser User-Agent
                                                       Tier-1 expanded: +Dailymotion, +SoundCloud
CaptureSideEffectRouter  passes URL through            + scheme/host allowlist on OpenExternalUrl
                                                       + onUpgradeClicked, onShowSnoozeToast
FloatingWindow IPC       showPreview, pushQueue,       + setActionResult (with version handshake)
                         setQuotaState                 + onUpgradeClicked, onUrlDropped
                                                       + onDownloadClicked.directDownload flag
StartCaptureDownloadDirectUseCase  N/A                 NEW — direct path (extract → preset → enqueue)
                                                       Real codebase deps (verified, not guessed)
PopupActionResult        N/A                           NEW sealed entity (Started/Completed/Failed/AuthRequired)
floating_window_main     1 primary button              2 primary buttons (Tải ngay + Tuỳ chọn)
                         no idle timer                 + idle 60s auto-close with hover pause
                         queue dedupe absent           + queue dedupe by rawUrl
                         brand: appName only           + brand-aware accent (BrandConfig.popupAccentColor)
                         1 form factor 300×420         + 300×120 Snoozed banner variant
BrandConfig              popupAccentColor missing      + popupAccentColor / Foreground / BrandDot
                                                       VidCombo uses 0xFF0066CC (Ocean Blue)
                                                       Both brands have Stripe checkout
KeyboardService          inapp scope only              + 1 system-scope hotkey (opt-in, default OFF)
SharedPrefsWindowPosStore single-slot                  + displayId-keyed + bounds check on load
NotificationService                                    + showDownloadStarted called from popup direct path
SettingsCard                                           + cooldown duration dropdown
                                                       + "Reset cooldowns" button
                                                       + global hotkey toggle (with onboarding)
SettingsScrollTargetProvider                          NEW — for nested-section navigation from popup
```

### New files (after all phases)

```
lib/features/floating_capture/
├── domain/
│   ├── usecases/
│   │   └── start_capture_download_direct_usecase.dart       (~140 lines)
│   ├── services/
│   │   └── recent_url_tracker.dart                          (~60 lines)
│   └── entities/
│       └── popup_action_result.dart                         (~50 lines, sealed)
├── data/
│   └── datasources/
│       └── og_image_scraper.dart                            (~90 lines)
└── presentation/
    └── widgets/
        └── global_hotkey_onboarding_dialog.dart             (~120 lines)

lib/features/settings/presentation/providers/
└── settings_scroll_target_provider.dart                     (~40 lines)

assets/platform_logos/                                       (15 SVGs)
```

### Modified files (estimate, all phases)

```
default_capture_service.dart                +200 / -30
lightweight_preview_service.dart            +130 / -25
floating_window_main.dart                   +280 / -50
clipboard_monitor_service.dart              +50
desktop_multi_window_floating_window.dart   +80 / -10
capture_side_effect_router.dart             +50
brand_config.dart                           +30
home_screen.dart (router wiring)            +35 / -10
main.dart (capture router override)         +60 / -15
keyboard_service.dart                       +80
shared_preferences_window_position_store.dart  +60 / -20
notification_service.dart (no change — reuse showDownloadStarted)  0
analytics_service.dart (no change — reuse track API)  0
settings card                               +60 / -5
window_position.dart entity                 +15
```

**Total**: ~1,260 LOC added, ~165 LOC removed, 6 new files.

---

## 5. Test Plan

v2.1 baseline confirmed: **287 tests passing on `v2/home-redesign-foundation`** (verified `flutter test test/features/floating_capture/` → "All tests passed!" — 2026-05-07).

| Phase | Suite | New tests |
|-------|-------|-----------|
| 2A | recent_url_tracker_test.dart | 5 |
| 2A | default_capture_service_test.dart (extend) | +5 (debounce, post-action blocklist) |
| 2A | mock_floating_window_test.dart (extend) | +4 (queue dedupe) |
| 2A | lightweight_preview_service_test.dart (extend) | +6 (Tier A/B/C/D ordering) |
| 2A | og_image_scraper_test.dart | 5 |
| 2A | capture_side_effect_router_test.dart (extend) | +3 (allowlist) |
| 2A | lru_cache_test.dart | 4 |
| 2A | brand_config_test.dart (extend) | +2 (popupAccentColor) |
| 2A | **Phase 2A subtotal** | **34** |
| 2B | start_capture_download_direct_usecase_test.dart | 8 |
| 2B | popup_state_variants_widget_test.dart (golden) | 10 (1 per state) × 2 brands = 20 golden tests |
| 2B | popup_idle_timer_test.dart | 4 |
| 2B | popup_actions_test.dart (button emits flag) | 3 |
| 2B | **Phase 2B subtotal** | **35** |
| 2C | popup_paywall_test.dart | 4 |
| 2C | auth_matrix_test.dart | 4 |
| 2C | window_position_test.dart (extend) | +3 (multi-monitor) |
| 2C | global_hotkey_onboarding_test.dart | 3 |
| 2C | **Phase 2C subtotal** | **14** |
| | **Grand total new** | **83** |

**Final test count**: 287 + 83 = **370 tests** for floating_capture suite.

### Manual smoke matrix

3 platforms × 2 brands × 17 scenarios = ~100 manual checks across 3 phases. Per-phase smoke checklist generated; track in `docs/floating_capture_v2.2_smoke_log.md`.

---

## 6. Asset & Translation Requirements

### Platform logo SVGs (Phase 2A)

15 platforms × 1 logo each, 24×24 viewBox, monochrome (color-tinted at render).

| Platform | Source | License |
|----------|--------|---------|
| youtube, tiktok, instagram, facebook, twitter, reddit, vimeo, dailymotion, soundcloud, threads, pinterest, linkedin, bilibili | simple-icons.org | CC0 |
| douyin | custom (not in simple-icons) | TBD — em sourcing or commission |
| unknown (generic link icon) | simple-icons.org | CC0 |

### Translation keys (Phase 2A + 2B)

5 langs (en + vi proper, es/pt/ja English placeholder per v2.1 pattern).

```jsonc
"floatingCapture": {
  "popup": {
    "actionDownloadNow": "Tải ngay",                    // NEW (was actionDownload)
    "actionMoreOptions": "Tuỳ chọn…",                   // NEW
    "actionUpgrade": "Nâng cấp Premium",                // NEW (Phase 2C)
    "stateLoading": "Đang tải metadata…",               // NEW (Phase 2B)
    "stateDownloadStarted": "Đang tải xuống Downloads/", // NEW (Phase 2B)
    "stateDownloadComplete": "Tải xong!",               // NEW (Phase 2B)
    "stateDownloadFailed": "Lỗi: {error}",              // NEW (Phase 2B)
    "stateAuthRequired": "Video private — mở trong app để dùng cookies", // NEW (Phase 2C)
    "stateOffline": "Không có Internet",                 // NEW (Phase 2B)
    "snoozeToast": "Floating capture đã tạm dừng. Click tray để bật lại.", // NEW (Phase 2B)
    "openInFolder": "Mở thư mục",                        // NEW (Phase 2B)
    "openInApp": "Mở trong app",                         // NEW (Phase 2C)
  },
  "settings": {
    "captureAntiSpamCooldown": "Anti-spam cooldown",     // NEW (Phase 2A)
    "captureAntiSpamCooldownHint": "Chặn URL đã tải gần đây trong khoảng thời gian này", // NEW
    "captureResetCooldowns": "Reset all cooldowns",      // NEW (Phase 2A)
    "captureGlobalHotkey": "Phím tắt toàn cục",          // NEW (Phase 2C)
  }
}
```

15 new keys × 5 locales = 75 translation entries.

### Asset bundle (`pubspec.yaml`)

```yaml
flutter:
  assets:
    - assets/platform_logos/
```

---

## 7. Brand Parity Rules (MUST OBEY)

VidCombo = priority equal to Svid (50,580+ devices vs Svid Go DB nhỏ hơn). Every UI surface MUST:

1. Render với `BrandConfig.current.popupAccentColor` — không hardcode `AppColors.wineRed`/`crimson`
2. Hiển thị `BrandConfig.current.appName` thay "Svid" trong mọi string
3. Upgrade URL = `BrandConfig.current.upgradeUrl` (svid.app/premium hoặc vidcombo.net/premium) — both Stripe (B4 fix verified `hasStripeCheckout: true`)
4. Free tier limit: **BOTH brands 15 captures/day** (memory `flutter-frontend.md` line "VidCombo=10" is OUT OF DATE per `brand_config.dart:633` code comment — em update memory file separately)
5. Smoke test cả 2 brand build trước khi sign-off mỗi phase

**PR reviewer checklist:**
- [ ] grep `wineRed\|0x..8D021F\|crimson` trong file modified — chỉ trong `app_colors.dart` token def hoặc `svid_brand_config.dart`
- [ ] grep `"Svid"` trong popup UI files — chỉ trong fallback string table
- [ ] Run `scripts/dev.sh vidcombo` → smoke popup → screenshot in PR
- [ ] Verify `BrandConfig.current.popupAccentColor == 0xFF0066CC` for VidCombo build

---

## 8. Migration & Rollout

### Branch strategy

- Base: `v2/home-redesign-foundation` (current branch)
- Feature branch: `feature/floating-capture-v2.2`
- Sub-branches per phase: `phase-2a`, `phase-2b`, `phase-2c` (rebase, không merge — keep history clean)

### Release strategy (3 releases instead of 2 — ultra-review C1 fix)

| Release | Includes | Target | Why split |
|---------|----------|--------|-----------|
| **v1.3.9 / v1.6.6** | Phase 2A only (logic-only) | tentative 2026-05-21 | No UI regression (popup looks same v2.1, just no spam + better thumbnails) |
| **v1.4.0 / v1.7.0** | Phase 2B (Stitch UI + direct download path) | tentative 2026-06-04 | Major visual + UX shift; needs Chairman Stitch approval |
| **v1.4.1 / v1.7.1** | Phase 2C (paywall + auth + hotkey + multi-monitor) | tentative 2026-06-18 | Polish — non-blocking |

**Rationale**: Phase 2A logic-only ship sớm fix critical bugs without visual change → safer for production. Phase 2B is biggest scope (visual + IPC contract update + new use case) — needs full QA + Stitch design. Phase 2C is opt-in polish.

### Backward compat (M4 fix)

- Phase 2A: zero IPC contract change → fully compat with old popup engine if somehow shipped split
- Phase 2B: NEW IPC method `setActionResult` — wrapped in try-catch (defensive). Production reality: popup engine + main bundled same release, no split deploy → caught silently.
- Phase 2C: incremental fields, all defensive

### Telemetry (M5 fix — verified)

`AnalyticsService.track(eventName, properties)` API confirmed. Backend endpoint via `BackendService.trackEvents(batch)` — works for Svid Go. **VidCombo PHP backend** — em verify in Phase 2A: if `trackEvents` 404 silently → log warning + continue (no crash). Don't block ship on telemetry.

Events (Phase 2A first wave):
- `floating_capture.dedupe_skipped`
- `floating_capture.post_action_cooldown_skipped`
- `floating_capture.idle_auto_close` (Phase 2B)
- `floating_capture.direct_download_attempt` (Phase 2B)
- `floating_capture.direct_download_started` (Phase 2B)
- `floating_capture.direct_download_completed` (Phase 2B)
- `floating_capture.direct_download_auth_required` (Phase 2B)
- `floating_capture.thumbnail_tier` (A/B/C/D distribution per platform — Phase 2A)
- `floating_capture.upgrade_clicked` (Phase 2C)
- `floating_capture.hotkey_force_show` (Phase 2C)

**PII rules** (m5 fix):
- DO log: platform name (`youtube`/`tiktok`/...), URL type (`video`/`channel`/`playlist`), state, error_code (yt-dlp class)
- DO NOT log: raw URL, video title, channel name, user-identifying metadata, session IDs

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| OG scrape blocked by IG/FB Cloudflare | High | Low | Already routed Tier D for IG/FB by design (C4 fix). Keep Tier C for Threads/Pinterest/LI/Bili which are looser. |
| Direct download skips user-preferred subtitle/audio config (preset doesn't cover) | Medium | Low | "Tuỳ chọn…" path covers; default = active preset. Telemetry track `direct_download_attempt` vs `more_options_clicked` ratio to validate 80/20 hypothesis. |
| YouTube nerfs oEmbed access (precedent: 2019, 2022) | Medium | Medium | Tier A canonical URL works without oEmbed for YT; oEmbed only for title/uploader. Graceful degrade to URL-only metadata. |
| TikTok geo-block on user's VPN | High | Low | Existing v2.1 timeout 5s → fallback. No regression. |
| Brand-aware refactor breaks Svid existing tests | Low | Medium | Add brand override fixtures; run full Svid + VidCombo CI per PR. |
| 60s idle auto-close annoys power user | Medium | Low | Settings adjustable 30/60/120/never (Phase 2B). |
| Hotkey accessibility prompt scares user | Medium | Medium | Default OFF (B5 fix). Onboarding dialog explains purpose. Skip option visible. |
| Multi-monitor displayId not stable across Spaces switch on macOS | Medium | Low | Bounds-check fallback at load (works regardless of displayId stability). |
| OG scrape adds 500-2000ms latency before Tier D | High | Low | Tier C only when no Tier A/B; show Tier D placeholder during scrape; async update if scrape succeeds. |
| `desktop_drop` Windows quirks | Medium | Low | Phase 2C drag-drop optional — defer to Phase 3 if test fails (M7 risk). |
| Apple updates Smart App Control on Windows side affects unrelated areas | Low | Medium | Outside spec scope — tracked in `project_windows_sac_ecdsa_block.md`. |
| FormatPreset doesn't capture all download options 80% need (worst case 60%) | Medium | Medium | Phase 2A telemetry doesn't measure (no direct path yet); Phase 2B telemetry validates. If <70% direct, redesign primary action label or expose preset selector inline. |
| Stitch generation cost overrun (Chairman billing) | Low | Low | Em report at gate before invoking; Chairman approves cost before Stitch run. |

---

## 10. Strategic Decisions Locked (CTO autonomy per Chairman GO)

| # | Question | Resolution | Rationale |
|---|----------|-----------|-----------|
| Q1 / B1 | "Tải ngay" → FormatPreset hay "Best"? Single button vs 2-button? | **2-button + active FormatPreset** | Discoverability > minimalism. Long-press / split-button less obvious for new users. Active preset = consistency với main app. |
| Q2 | Auto-close timer? | **60s default**, Settings 30/60/120/never. Pause on hover. | Power user reading queue items needs hover pause (M1). 60s = same as Slack notification dwell time. |
| Q3 | Cooldown URL same? | **2 phút default**, Settings 30s/1m/2m/5m | 5m too aggressive (em wrong v1.0); 2m balances spam prevention + retry comfort. |
| Q4 | Branch + release? | **`feature/floating-capture-v2.2`** từ `v2/home-redesign-foundation`; **3 releases** v1.3.9 / v1.4.0 / v1.4.1 (re-ordered ultra-review C1) | Phase 2A standalone alone is regression — can't ship without 2B notification UI. Split into logic-fix + visual + polish 3 waves. |
| Q5 | Stitch first? | **Yes, gate before Phase 2B code** | Vision → implement, per Chairman feedback. |
| Q6 | VidCombo priority? | **Equal to Svid** | Both ship same release, both QA. |
| B2 | Notification on direct download? | **Yes — `notificationService.showDownloadStarted(filename)` after enqueue** | User mất context if popup closes silently. System notification = native pattern. |
| B3 | Anti-spam strict safety valve? | **Settings "Reset cooldowns" button + verbose debug log per layer** | Allows user-level diagnose when popup appears not to work. |
| B4 | VidCombo paywall flow? | **Stripe checkout — same as Svid** | Verified `hasStripeCheckout: true` `brand_config.dart:638`. Em wrong in v1.0 brainstorm assuming manual key only. |
| B5 | Global hotkey default? | **OFF — opt-in via Settings with onboarding dialog** | macOS Accessibility prompt is friction. User must understand value first. |
| B6 | Phase order? | **Logic-first Phase 2A → Visual+UX Phase 2B → Polish Phase 2C** | Re-ordered ultra-review C1 — original "ship 2A standalone" was regression. |
| B7 | Release dates? | Tentative 2026-05-21 / 2026-06-04 / 2026-06-18 | Subject to RSA cert migration unblock + Stitch generation timing. |

---

## 11. Sign-off Checklist

### Pre-implementation (current state)
- [x] Spec v1.1 written (this doc, post-ultra-review)
- [x] Codebase API names verified via grep (C3 fix grounded)
- [x] VidCombo brand color verified (`brand_config.dart:795`) — 0xFF0066CC
- [x] v2.1 baseline test count verified (287 passing)
- [x] FormatPreset coverage assessed (m8)
- [ ] Chairman review spec v1.1 — direction approved
- [ ] Chairman review Stitch creative brief v1.1
- [ ] Memory `flutter-frontend.md` corrected ("VidCombo=10" → 15)

### Phase 2A (target v1.3.9 / v1.6.6)
- [ ] All 8 sub-tasks 2A.1 - 2A.8 implemented
- [ ] +34 new tests pass
- [ ] All 287 v2.1 tests still pass
- [ ] `flutter analyze` clean (output mentions "snakeloader")
- [ ] Manual smoke macOS + Windows + both brands
- [ ] Telemetry endpoints verified for both backends (PHP fallback OK)
- [ ] PR reviewer checklist passed
- [ ] v1.3.9 / v1.6.6 ship — workflow_dispatch per brand serial

### Phase 2B (target v1.4.0 / v1.7.0)
- [ ] **GATE: Stitch design generated + Chairman approved 20 screens**
- [ ] Design tokens exported from Stitch
- [ ] All 6 sub-tasks 2B.0 - 2B.6 implemented
- [ ] +35 new tests pass (including 20 golden file tests)
- [ ] Brand parity verified (Ocean Blue VidCombo, Wine Red Svid)
- [ ] Manual smoke covers direct download path + system notification flow
- [ ] v1.4.0 / v1.7.0 ship

### Phase 2C (target v1.4.1 / v1.7.1)
- [ ] All 6 sub-tasks 2C.1 - 2C.6 implemented (drag-drop optional Phase 3)
- [ ] +14 new tests pass
- [ ] Auth matrix manual verified (4 video states × 2 paths)
- [ ] v1.4.1 / v1.7.1 ship

---

## 12. References

- v2.1 Spec: [Svid_v2_1_FloatingCapture_Spec.md](Svid_v2_1_FloatingCapture_Spec.md)
- v2.1 Status: [Svid_v2_1_FloatingCapture_Implementation_Status.md](Svid_v2_1_FloatingCapture_Implementation_Status.md)
- Stitch brief v1.1: [Svid_v2_2_FloatingCapture_Stitch_Brief.md](Svid_v2_2_FloatingCapture_Stitch_Brief.md)
- Codex audit findings: commits `f413c15a`, `a6677e1c`, `eb010d5f`
- Competitor reference: Downie 4 (paid $30, single-feature popup app)
- Design system: [DESIGN.md](../DESIGN.md), [STITCH.md](../STITCH.md)
- Brand config (verified): [brand_config.dart](../lib/core/config/brand_config.dart) lines 558 (Svid gradient), 795 (VidCombo gradient), 633 (VidCombo freeDailyDownloads=15)
- Real codebase API (verified):
  - Active preset: `lib/features/home/presentation/screens/home_download_mixin.dart:623` (`activePresetProvider.currentConfig`)
  - Download create+start: `lib/features/downloads/data/repositories/download_repository_impl.dart:91` + `:319`
  - Binary manager: `lib/core/binaries/binary_manager.dart:734` (`_ensureInitialized` lazy)
  - Notification: `lib/core/services/notification_service.dart:225` (`showDownloadStarted`)
  - Analytics: `lib/core/services/analytics_service.dart:30` (`track(eventName, properties)`)
