# Svid v2.1 — Floating Capture Specification

**Version:** Draft v1.2
**Date:** 2026-05-05
**Status:** Approved for v2.1 (post v2.0 launch, ~2-3 months out)
**Scope:** System-level floating window for clipboard URL capture
**Companion to:**
- [Svid_Home_Download_Manager_UI_Spec_v1.1.md](Svid_Home_Download_Manager_UI_Spec_v1.1.md) (functional v1.5)
- [Svid_v2_Design_Spec.md](Svid_v2_Design_Spec.md) (visual v1.2)
- [Svid_v2_Implementation_Roadmap.md](Svid_v2_Implementation_Roadmap.md)

## Changelog v1.1 → v1.2 — Codex external audit fixes

8 findings (3 P0 + 4 P1 + 1 P2) verified và resolved:

- **§3.1 P0**: Component diagram clarified — floating window NEVER directly accesses Riverpod providers. All download/state interactions go through MethodChannel to main engine.
- **§3.6 NEW P0**: Capture-to-download flow explicit — oEmbed preview is metadata-only; clicking Tải xuống triggers full yt-dlp extraction in main engine before download starts.
- **§3.2 + §6 P0**: Multi-window decision explicit — `desktop_multi_window` for Flutter UI window; native code complementary for tray, clipboard polling, auto-launch, NSPanel attributes (NOT competing).
- **§3.1 + §6.2 P1**: macOS clipboard listener corrected — NSPasteboard does NOT have did-change-notification. Spec'd `changeCount` polling at 500ms with energy budget. Removed false API reference.
- **§10 P1**: Migration note for `onWindowClose()` — existing `windowManager.destroy()` must change to `windowManager.hide()` (minimize to tray); only tray "Thoát" triggers real destroy.
- **§5.2 P1**: Queue overflow shows toast "Đã bỏ qua link cũ nhất" instead of silent drop. Optional: persist to capture history for recovery (deferred v2.2).
- **§10.1 P1**: Feature flag scope corrected — local-only `static bool` flag. Remote kill switch via backend deferred to v2.2 (no current backend feature flag infrastructure).
- **§9.1 P2**: Translation key count updated to ~44 keys (was claimed ~35; actual count higher).

## Changelog v1.0 → v1.1 — self-audit fixes

13 findings resolved (4 P0 + 6 P1 + 3 P2):

- **§10.2 P0**: Fixed first-launch detection logic bug — `!(prefs.getBool(...) ?? false)` (correct precedence)
- **§5 P0**: Added app-launch-with-clipboard-already-has-URL behavior — passive (ignore until next change)
- **§4 P0**: Added state transitions diagram — Loading → Ready → Error chain explicit
- **§7 P0**: Specified tray left-click behavior (toggle main window)
- **§3 P1**: Documented IPC architecture (method channel between main and floating engine)
- **§9 P1**: Added 10 missing translation keys (notifications, aria-labels, dismiss buttons)
- **§11 P1**: Added 5 edge cases E16-E20 (non-URL clipboard, auth token, long URL, fragment, image clipboard)
- **§4 P1**: Added dimension rationale table per state
- **§13 P1**: Added stress/memory test scenarios (long-running tray app)
- **§14 P1**: Added 5 missing risks (notarization, SmartScreen, plugin abandonment, social media backlash, GDPR)
- **§6 P2**: Marked native code samples as illustrative (Flutter integration requires platform channel)
- **§12 P2**: Adjusted effort estimate to 30 days realistic (was 26-27)
- **§8 P2**: Clarified Settings live update behavior (reactive countdown)

---

## 1. Overview

### 1.1 Feature description

Khi user copy link video bất kỳ (YouTube/TikTok/Instagram/etc.) vào clipboard, Svid hiển thị một **floating window** nhỏ ngoài app — hoạt động như mini-app độc lập — chứa thumbnail + title + format/quality controls + nút Tải xuống. User download trực tiếp từ floating window mà không cần switch sang main app.

Pattern này gọi là **"capture popup"** hoặc **"link grabber"** — Internet Download Manager (IDM) là precedent kinh điển trong ~20 năm.

### 1.2 Value proposition

| Metric | Without (current) | With Floating Capture |
|--------|-------------------|----------------------|
| **Friction** to download | Open app → paste → wait extract → click | Copy URL → click Tải xuống trong popup |
| **Context switch** | Required (app focus) | None (popup non-stealing) |
| **Time to action** | 5-15 seconds | 1-3 seconds |
| **Always available** | Only when app open | Always (tray-resident) |

### 1.3 Industry precedent

| App | Pattern | Approx similarity |
|-----|---------|-------------------|
| **Internet Download Manager (IDM)** | Floating popup khi browser detect video | ~95% same pattern |
| **JDownloader 2** — LinkGrabber | Paste links → confirm popup | ~70% similar |
| Free Download Manager | Browser ext + popup | ~60% similar |
| 4K Video Downloader — Smart Mode | Captures clipboard → main window | ~40% similar (no floating) |

→ Svid v2.1 floating capture = IDM-grade UX, modern desktop implementation.

---

## 2. Finalized decisions (Q&A audit results)

28 decisions confirmed via interactive design Q&A:

| # | Topic | Decision |
|---|-------|----------|
| 1 | Strategy | Drop inline preview (left column), focus floating window in v2.1 |
| 2 | Trigger condition | Popup always shows when video URL copied (regardless of app focus) |
| 3 | Multi-URL behavior | Queue in single popup, max 5 items, oldest dropped when full |
| 4 | Click X (close) | Minimize app to tray (background-resident) |
| 5 | Popup UI mode | Adaptive — minimal default, expandable to advanced controls |
| 6 | First install | Capture default ON, no onboarding screen |
| 7 | Auto-launch on login | Default ON (app starts with system) |
| 8 | Smart skip rules | NONE — only user-explicit snooze controls visibility |
| 9 | Quota=0 (free user) | Popup shown with "Nâng cấp Premium" button instead of Tải xuống |
| 10 | Default popup position | Bottom-right corner + remember user drag position |
| 11 | Auto-dismiss timeout | Never — user manually dismisses or interacts |
| 12 | Linux support | Skipped in v2.1 (only macOS + Windows). Linux deferred v2.2 |
| 13 | Snooze duration options | 30 min / 1 hour / 4 hours / 1 day / Permanent (5 options) |
| 14 | Tray menu structure | Minimal: "Mở Svid" + "Thoát" only |
| 15 | Focus stealing | Popup does NOT steal focus from active app |
| 16 | Tray icon visual states | Same icon always (no badge for snoozed) |
| 17 | Default format/quality | Reuse main app's active FormatPreset / per-platform pref |
| 18 | Non-video URLs | Popup with "Mở trong Svid" button (route to main app sheets) |
| 19 | Multi-monitor positioning | Follow mouse cursor monitor |
| 20 | Settings → Capture | Progressive disclosure, no reset buttons |
| 21 | Telemetry | None (no event tracking) |
| 22 | First-run hint | Subtle inline hint at footer of first popup, shown once |
| 23 | oEmbed failure | Popup fallback with platform icon + URL truncated + "Tải xuống thử" |
| 24 | Click thumbnail | Open video in external browser |
| 25 | Snooze fatigue | No app intervention — user decides themselves |
| 26 | After clicking Tải xuống | Popup auto-close + system notification. Download uses shared service with main app (same downloadsNotifier, DB, history) |
| 27 | Localization | All 5 languages (vi/en/ja/pt/es) match main app |
| 28 | Popup dimensions | Portrait 300×420 (collapsed) / 300×560 (expanded) |

---

## 3. Architecture

### 3.1 High-level component diagram

```
┌─ Main app process (always running, tray-resident) ─────────────┐
│                                                                  │
│  ┌─ Main Window (visible/minimized) ──────────────────────────┐ │
│  │ Smart input + preset + history + downloads UI              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ Tray Service (NSStatusItem / NotifyIcon / GtkStatusIcon) ─┐ │
│  │ • Icon                                                      │ │
│  │ • Menu: "Mở Svid" + "Thoát"                                │ │
│  │ • Click → show/hide main window                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ ClipboardMonitorService ──────────────────────────────────┐ │
│  │ • macOS: poll NSPasteboard.changeCount @ 500ms              │ │
│  │   (Apple does NOT expose did-change-notification)           │ │
│  │ • Windows: AddClipboardFormatListener event-driven (Vista+) │ │
│  │ • Energy budget: pause polling when system on battery <10%   │ │
│  │ • URL extraction + dedup (60s TTL)                          │ │
│  │ • Forwards to CaptureService                                │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ CaptureService ───────────────────────────────────────────┐ │
│  │ • Read snooze state from CapturePreferencesProvider         │ │
│  │ • If snoozed → drop event silently                          │ │
│  │ • If active:                                                │ │
│  │   1. UrlPatternService.classify(url)                        │ │
│  │   2. LightweightPreviewService.fetchOEmbed(url)             │ │
│  │   3. Push VideoPreview to FloatingWindowManager             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ FloatingWindowManager ────────────────────────────────────┐ │
│  │ • Lifecycle of floating window (spawn/show/hide/destroy)    │ │
│  │ • Queue management (max 5)                                  │ │
│  │ • Position tracking per-monitor                             │ │
│  │ • Communicates with floating window via method channel      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ Riverpod providers (MAIN ENGINE ONLY) ─────────────────────┐ │
│  │ • downloadsNotifierProvider                                 │ │
│  │ • startDownloadUseCase                                      │ │
│  │ • PlatformQualityPreference / FormatPreset                  │ │
│  │ • extractVideoInfoUseCaseProvider                           │ │
│  │ ⚠️ NOT shared with floating engine — accessed via IPC only  │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
              │
              │ MethodChannel "svid.floating_capture"
              │ (only IPC bridge — no shared state)
              ▼
┌─ Floating Window (SEPARATE Flutter engine instance) ─────────────┐
│                                                                   │
│  300×420 (collapsed) or 300×560 (expanded)                        │
│  • Always-on-top                                                  │
│  • No focus stealing                                              │
│  • Draggable                                                      │
│  • Renders VideoPreview UI from JSON received via channel         │
│  • Has OWN local widget state (not Riverpod-shared)               │
│  • Sends user actions back via channel events                     │
│  • Cannot directly call shared services — all routed via main    │
└───────────────────────────────────────────────────────────────────┘
```

**⚠️ Critical architectural rule**: Floating window engine has NO direct access to main app's Riverpod ProviderContainer. All state/download interactions go through MethodChannel `svid.floating_capture` (see §3.3). When Q26 says "shared service with main app", it means **functional equivalence** (download appears identical in main app's history) — NOT shared in-memory state.

### 3.2 Multi-window approach — hybrid (plugin + native)

**Decision**: `desktop_multi_window` plugin **AND** native code work **complementarily**, not competing. Each owns specific concerns:

| Component | Owner | Why |
|-----------|-------|-----|
| Floating window engine + Flutter UI rendering | `desktop_multi_window` plugin | Avoid reinventing multi-engine Flutter integration; cross-platform abstraction |
| Method channel between engines | Plugin built-in | Standard Flutter IPC |
| **Window-level platform attributes** (always-on-top, no-focus-steal, panel style) | Native code | Plugin doesn't expose `NSPanel.styleMask`, `WS_EX_NOACTIVATE` etc. — need native overrides |
| **System tray** (NSStatusItem, NotifyIcon) | Native code | Plugin doesn't cover tray |
| **Clipboard monitor** | Native code | Polling `changeCount` on macOS, `AddClipboardFormatListener` on Windows |
| **Auto-launch on login** | Native code | `SMAppService` (macOS), Registry HKCU (Windows) |
| **System notifications** | `flutter_local_notifications` plugin (existing) | Already in pubspec |

→ Plugin handles window lifecycle. Native code customizes window behavior + provides system integration. They are **different layers**, not alternatives.

If `desktop_multi_window` proves unstable during spike (Phase 1A.3), fallback is full native window implementation: ~+5 days effort.

### 3.3 IPC architecture between engines

Floating window runs as **separate Flutter engine instance** (per `desktop_multi_window`). Riverpod providers do NOT auto-share between engines. Communication via **MethodChannel** with explicit message types.

```
┌─ Main Engine ─────────────────────────┐    ┌─ Floating Engine ────────┐
│                                        │    │                           │
│  CaptureService                        │    │  FloatingWindowApp        │
│  ├─ downloadsNotifierProvider          │    │  ├─ FloatingPopupWidget   │
│  ├─ FormatPreset providers             │    │  ├─ Local UI state        │
│  └─ FloatingWindowManager              │    │  └─ MethodChannel client  │
│      └─ MethodChannel host             │◀──▶│                           │
│                                        │    │                           │
└────────────────────────────────────────┘    └───────────────────────────┘
```

**Channel name**: `svid.floating_capture`

**Messages from Main → Floating** (commands):
| Method | Args | Purpose |
|--------|------|---------|
| `showPreview` | `VideoPreview` JSON | Display new capture in popup |
| `pushQueue` | `VideoPreview` JSON | Add to queue |
| `clearQueue` | - | Empty queue, hide popup |
| `setQuotaState` | `int remaining` | Update Tải xuống / Nâng cấp UI |
| `setSnoozeState` | `CaptureSnoozeState` | Update menu state |
| `dismiss` | - | Force hide popup |

**Messages from Floating → Main** (events):
| Method | Args | Purpose |
|--------|------|---------|
| `onDownloadClicked` | `String url`, `DownloadConfig?` | Trigger shared download flow |
| `onSnoozeSelected` | `SnoozeDuration` | Update snooze state in main |
| `onMenuOpenApp` | - | Bring main window to focus |
| `onMenuOpenSettings` | - | Open Settings → Capture |
| `onPositionChanged` | `double x, y, monitorId` | Persist position |
| `onPopupDismissed` | - | Update queue state in main |
| `onThumbnailClicked` | `String url` | Open external browser |
| `onOpenInAppClicked` | `String url` | Route to main app sheet (playlist/channel) |

**Serialization**: Use simple JSON-encoded maps, not Riverpod state directly. Floating engine deserializes into local widget state.

**State sync**: Main app is source of truth. Floating window state derived from method channel messages. On floating window destroy/recreate (e.g., after crash), main re-sends current state via `showPreview` / `setQuotaState` etc.

### 3.4 Capture-to-download flow (full pipeline)

oEmbed preview chỉ chứa **metadata cho display** (thumbnail, title, uploader). Để **tải thực sự**, cần `VideoInfo` đầy đủ với available qualities (từ yt-dlp full extraction). Flow:

```
[Floating window]              [Main engine]              [Existing services]
─────────────────              ─────────────              ───────────────────

User clicks Tải xuống
       │
       │ MethodChannel.invokeMethod(
       │   'onDownloadClicked',
       │   {url, popupSelectedQuality, popupSelectedFormat}
       │ )
       ▼
                              CaptureDownloadCoordinator
                                       │
                                       │ 1. Resolve preset
                                       │    (per Q17: reuse main app's
                                       │     active FormatPreset OR
                                       │     PlatformQualityPreference
                                       │     for URL platform)
                                       │
                                       │ 2. Check user override from popup
                                       │    (if expanded mode used)
                                       │
                                       │ 3. Trigger full extraction
                                       │
                                       │  ───▶  ExtractVideoInfoUseCase
                                       │             │
                                       │             │ yt-dlp call
                                       │             │ (3-30s typical)
                                       │             ▼
                                       │        Result<VideoInfo>
                                       │             │
                                       ◀─────────────┘
                                       │
                                       │ 4. Match preset's quality preference
                                       │    against VideoInfo.availableQualities
                                       │    (using qualityFallbackService if 1080p
                                       │     not available, fallback to 720p, etc.)
                                       │
                                       │ 5. Build DownloadConfig
                                       │
                                       │ 6. Trigger startDownloadUseCase
                                       │
                                       │  ───▶  StartDownloadUseCase
                                       │             │
                                       │             │ Persist to DB,
                                       │             │ start ytdlp_datasource,
                                       │             │ updates downloadsNotifierProvider
                                       │             │ (main app history list reflects)
                                       │             ▼
                                       │        DownloadEntity created
                                       │
       ◀────── MethodChannel ────────  │ 7. Send back result
       │        ('downloadStarted')    │
       │                               │ 8. OR error state
       │                               │
       ▼
Show system notification
"Đã bắt đầu tải: {title}"
       │
       ▼
Auto-close popup (per Q26)
```

**Why critical**: oEmbed gives `thumbnail + title + author_name`. yt-dlp gives `available qualities + formats + codecs + subtitles + chapters` — needed for actual download.

**Error paths**:
- yt-dlp extraction fails → main engine sends `onDownloadFailed` event → popup shows error toast → keep popup open for retry
- Quality preset has no match → use fallback chain → notification "Tải với 720p (1080p không khả dụng)"
- Network error → standard error notification, popup retries via Tải xuống thử button

**Latency expectation**: User experiences ~3-30s "downloading..." between click and notification. Popup shows spinner state during this. May need new "Initiating download..." state in §4.

### 3.5 Component creation order (implementation guide)

Phase 1A.1 (foundational):
1. `LightweightPreviewService` — oEmbed for 5 platforms
2. `UrlPatternService` — URL classification + ID extraction
3. `VideoPreview` entity

Phase 1A.2 (platform integration):
4. `ClipboardMonitorService` — polling-based (per §3.1, §6.2 corrected)
5. Tray native integration (NSStatusItem / NotifyIcon)
6. Auto-launch native integration

Phase 1A.3 (window):
7. `desktop_multi_window` plugin integration spike
8. `FloatingWindowManager` (Dart side)
9. Method channel bridge `svid.floating_capture`

Phase 1A.4 (UI):
10. Floating window UI (all 7 states)
11. Settings → Capture section

Phase 1A.5 (orchestration):
12. `CaptureService` (snooze + queue + dispatch)
13. `CaptureDownloadCoordinator` (extraction + preset resolution + download dispatch — per §3.4)

Phase 1A.6 (polish):
14. System notifications
15. First-run hint
16. Stress + perf tests

### 3.3 Domain entities

```dart
// lib/features/floating_capture/domain/entities/

class CaptureState {
  final CaptureSnoozeState snoozeState;
  final DateTime? snoozeUntil;
  final List<VideoPreview> queue;       // max 5
  final int activeIndex;                // current popup item
  
  bool get isCapturing => snoozeState == CaptureSnoozeState.active ||
                          (snoozeState == CaptureSnoozeState.snoozedTimed && 
                           DateTime.now().isAfter(snoozeUntil!));
}

enum CaptureSnoozeState {
  active,
  snoozedTimed,
  snoozedPermanent,
}

enum SnoozeDuration {
  thirtyMinutes,    // 30p
  oneHour,          // 1h
  fourHours,        // 4h
  oneDay,           // 1 ngày
  permanent,        // Vĩnh viễn
}

class VideoPreview {
  final String rawUrl;
  final VideoPlatform platform;
  final UrlType urlType;
  final String? itemId;            // video ID for YouTube
  final String? title;             // from oEmbed
  final String? uploader;
  final String? thumbnailUrl;
  final Duration? startTimestamp;  // ?t= param preserved for Section trim
  final String? playlistId;
  final bool hasFetchedMetadata;
  final DateTime capturedAt;
  
  bool get hasMinimalDisplay => platform != VideoPlatform.unknown;
}
```

---

## 4. Popup UI specifications

### 4.1 States

| State | Trigger | Dimensions | Rationale |
|-------|---------|------------|-----------|
| **Loading** | Initial after URL detected | 300×340 | No thumbnail = compact. Brief (~300ms typical oEmbed) |
| **Ready (collapsed)** | oEmbed success | 300×420 | Standard với hint footer (lần đầu). 380 sau lần đầu (no hint) |
| **Ready (expanded)** | User click "▼ Tuỳ chọn" | 300×560 | +3 dropdowns × 40px + 20px gaps = +160px from collapsed |
| **Queue mode** | 2+ pending items | 300×460 | +40px navigation header on top of collapsed |
| **Error/fallback** | oEmbed failed | 300×340 | No thumbnail; replaced by platform icon (~80×80) = compact |
| **Non-video URL** | Channel/playlist/search detected | 300×340 | No thumbnail, just icon + type label + CTA = compact |
| **Quota=0** | Free user exhausted | 300×460 | Standard Ready + 40px explanation text "Đã hết 15/15 lượt..." |

### 4.2 State transitions

```
                ┌─ URL detected ─┐
                │                │
                ▼                │
          ┌──────────┐           │
          │ Loading  │           │
          │ 300×340  │           │
          └────┬─────┘           │
               │                  │
       ┌───────┴───────┐         │
       │               │          │
   oEmbed OK       oEmbed fail   │
       │               │          │
       ▼               ▼          │
  ┌─────────┐    ┌──────────┐    │
  │  Ready  │    │  Error/  │    │
  │collapsed│    │ fallback │    │
  │ 300×420 │    │ 300×340  │    │
  └────┬────┘    └────┬─────┘    │
       │              │            │
       │              │            │
   user clicks     user clicks    │
   ▼ Tuỳ chọn    Tải xuống thử   │
       │              │            │
       ▼              ▼            │
  ┌─────────┐    [trigger yt-dlp full extract in main app]
  │ Ready   │
  │expanded │
  │ 300×560 │
  └────┬────┘
       │
   user clicks
   ▲ Thu gọn
       │
       └─▶ Ready collapsed
       
       
   ──── New URL while popup visible ────
       │
       ▼
   queue.length >= 2?
       ├─ Yes ──▶ Queue mode (300×460) + nav arrows
       └─ No ───▶ Replace current popup content (same state)
       
   ──── Action terminal states ────
   - User clicks Tải xuống → popup auto-close + system notification
   - User clicks ✕ → popup hides, queue cleared
   - User clicks ⋮ → snooze action → popup hides, queue cleared
   - User clicks "Mở trong Svid" → main window focus, popup hides
```

**Key transition rules**:
- Loading state always preceded by URL detection event
- Loading → Ready/Error decided by oEmbed result
- Hint footer (Ready only) visible only on first lifetime popup (`first_capture_shown=false`)
- Quota=0 state replaces Ready collapsed when `quota.remaining == 0`
- Non-video URL state replaces Loading when URL classifier returns playlist/channel/search
- Animation: height transitions 200ms `ease-out` per design spec motion tokens

### 4.3 Layout: Ready collapsed (default)

```
┌─ 300px wide ────────────────────────┐  ← border radius 12, shadow lg
│                                      │
│  ┌────────────────────────────┐    │
│  │   [Thumbnail 16:9]         │    │  ← 268×151 (270 with margins)
│  │   Click → external browser │    │
│  └────────────────────────────┘    │
│                                      │
│  Video Title Here (max 2 lines)     │  ← 14px/600, max 44px height
│  truncate ellipsis if longer         │
│                                      │
│  Channel · 12:34 · YouTube          │  ← 12px/400, secondary text
│                                      │
│  ┌──────────────────────────────┐  │
│  │   ⬇️ Tải xuống               │  │  ← 268×44, primary button
│  └──────────────────────────────┘  │
│                                      │
│  ▼ Tuỳ chọn nâng cao              │  ← 12px link, secondary
│                                      │
│  💡 Svid tự bắt link khi copy.    │  ← First-run hint only
│     Bấm ⋮ để tạm tắt nếu cần.       │  ← 12px muted, removable
│                                      │
│  Top-right corner: [⋮] [✕]         │  ← 32×32 icon buttons
└──────────────────────────────────────┘
   Total height: ~420 (with hint)
                ~380 (without hint, after first run)
```

### 4.4 Layout: Ready expanded

```
┌──────────────────────────────────────┐
│  [Thumbnail 16:9 — 268×151]          │
│                                       │
│  Video Title (max 2 lines)            │
│  Channel · 12:34 · YouTube            │
│                                       │
│  Định dạng:    [MP4 (Video)    ▼]    │  ← 268×40 dropdown
│  Chất lượng:   [1080p          ▼]    │
│  Phụ đề:       [VietSub        ▼]    │
│                                       │
│  ┌──────────────────────────────┐   │
│  │   ⬇️ Tải xuống              │   │
│  └──────────────────────────────┘   │
│                                       │
│  ▲ Thu gọn                            │
└───────────────────────────────────────┘
   Total: ~560
   Animation: 200ms ease-out height transition
```

### 4.5 Layout: Queue mode (2+ items)

```
┌──────────────────────────────────────┐
│  [<]  Link 2/5         [>]   [⋮][✕]  │  ← Navigation header
│                                       │
│  [Thumbnail]                          │
│  Title                                │
│  Channel · ...                        │
│                                       │
│  ┌──────────────────────────────┐   │
│  │   ⬇️ Tải xuống              │   │
│  └──────────────────────────────┘   │
│                                       │
│  [Bỏ qua tất cả 5]                   │  ← Clear queue
└───────────────────────────────────────┘
   Total: ~460
```

### 4.6 Layout: Error / oEmbed fail

```
┌──────────────────────────────────────┐
│  ┌────────────────────────────┐    │
│  │   🎬                        │    │  ← Platform icon centered, ~80px
│  │   YouTube link              │    │
│  └────────────────────────────┘    │
│                                      │
│  youtube.com/watch?v=abc1234...     │  ← URL truncated
│                                      │
│  ⚠️ Không lấy được thông tin video   │
│                                      │
│  ┌──────────────────────────────┐  │
│  │  ⬇️ Tải xuống thử           │  │  ← Try via yt-dlp full extract
│  └──────────────────────────────┘  │
│                                      │
│  [⋮] [✕]                            │
└──────────────────────────────────────┘
   Total: ~340
```

### 4.7 Layout: Non-video URL

```
┌──────────────────────────────────────┐
│                                       │
│  📋 Playlist YouTube                  │  ← Type label
│                                       │
│  "Top 50 Hits 2026"                  │  ← Title (if oEmbed worked)
│  50 video                             │
│                                       │
│  ┌──────────────────────────────┐   │
│  │  📂 Mở trong Svid           │   │  ← Route to main app sheet
│  └──────────────────────────────┘   │
│                                       │
│  Popup không tải playlist trực tiếp.  │  ← Explain limitation
│                                       │
│  [⋮] [✕]                             │
└───────────────────────────────────────┘
   Total: ~340
```

### 4.8 Layout: Quota=0

Same as Ready but primary button transforms:

```
  ┌──────────────────────────────┐
  │  ⭐ Nâng cấp Premium         │  ← Gold/purple background
  └──────────────────────────────┘
  
  Đã hết 15/15 lượt tải hôm nay   ← Subtitle in metadata area
  Reset lúc 00:00
```

### 4.9 ⋮ Menu (top-right)

Click `⋮` icon → popup menu:

```
┌────────────────────────────┐
│ Tạm tắt 30 phút           │
│ Tạm tắt 1 tiếng           │
│ Tạm tắt 4 tiếng           │
│ Tạm tắt 1 ngày            │
│ ─────────────────────     │
│ Tắt cho đến khi bật lại   │
│ ─────────────────────     │
│ Mở Svid                   │
│ Cài đặt...                 │
└────────────────────────────┘
```

After click any snooze option → mini toast confirms (5s undo window):
```
┌──────────────────────────────────┐
│ ✓ Đã tạm tắt đến 15:30           │
│ [Hủy]                             │  ← Undo restores active state
└──────────────────────────────────┘
```

---

## 5. State machines

### 5.1 Capture lifecycle

```
                  ┌─────────┐
   App start ────▶│ Active  │◀──────── Snooze expired (timed)
                  │capture │           Manual "Bật lại"
                  └─────────┘
                       │
        User picks snooze duration
                       │
                       ▼
              ┌──────────────────┐
              │ Snoozed (timed)  │
              │ until=DateTime   │
              └──────────────────┘
                       │
                User picks "Vĩnh viễn"
                       │
                       ▼
              ┌──────────────────┐
              │ Snoozed forever  │
              └──────────────────┘
                       ▲
                       │
                Manual "Bật lại"
                via Settings or popup ⋮
```

**Persistence**: SharedPreferences keys
- `capture_snooze_state`: enum string
- `capture_snooze_until`: ISO8601 timestamp
- Re-evaluated on every clipboard change event

**Sleep handling**: Use **wall-clock comparison** (`DateTime.now() > snoozeUntil`). System sleep doesn't affect comparison. Time zone change accepted as edge.

### 5.2 Queue state

```
[]  ──URL1──▶  [URL1]   (show popup with URL1)
            
[URL1]  ──URL2 (different)──▶  [URL1, URL2]   (show 1/2 navigator)

[URL1, URL2, URL3, URL4, URL5]  ──URL6──▶  [URL2, URL3, URL4, URL5, URL6]
                                            (URL1 dropped, oldest)
                                            ▲ TOAST: "Đã bỏ qua 1 link cũ nhất"
                                              (per audit P1-3 — prevent silent data loss)

User clicks "Tải xuống" on URL3:
[URL1, URL2, URL3, URL4, URL5]  ──action URL3──▶  [URL1, URL2, URL4, URL5]
                                                   (URL3 removed, advance to URL4)

User clicks "Bỏ qua tất cả":
[URL1, URL2, URL3]  ──clear──▶  []   (popup dismisses)

User dismisses (X) without action:
[URL1, URL2, URL3]  ──dismiss──▶  []   (popup hides, queue cleared)
```

**Dedup rule**: If incoming URL matches any URL in queue (exact match) within 60s → ignore (don't add duplicate).

**Overflow notification**: When queue full (5) and 6th URL arrives, dropped URL is announced via toast inside popup:
```
┌──────────────────────────────────────┐
│ Đã bỏ qua link cũ nhất               │
│ (queue đầy, giữ 5 link mới nhất)     │
└──────────────────────────────────────┘
```
Toast auto-dismisses 3s. Prevents silent data loss UX.

**Future enhancement (v2.2+)**: Persist dropped URLs to "capture history" so user can recover via Settings → Capture → "Recently captured links". Deferred to maintain v2.1 simplicity.

### 5.3 App launch behavior (clipboard pre-state)

When app starts (manual launch or auto-launch on login), clipboard có thể đã chứa URL từ trước. Behavior:

**Decision: Passive on launch — ignore initial clipboard state**

Rationale:
- App start không trigger popup từ existing clipboard content
- ClipboardMonitor only reacts to **new** clipboard changes after init
- Avoids surprise popup khi user just turn on máy

Implementation:
```dart
class ClipboardMonitorService {
  late final String _initialClipboardHash;
  String _lastSeenHash = '';
  
  Future<void> start() async {
    // Capture initial state — used as baseline, NOT triggered
    final initial = await _readClipboard();
    _initialClipboardHash = _hash(initial);
    _lastSeenHash = _initialClipboardHash;
    
    // Begin listening for CHANGES from this point
    _listener.start(_onClipboardChange);
  }
  
  void _onClipboardChange(String content) {
    final hash = _hash(content);
    if (hash == _lastSeenHash) return;  // no real change
    _lastSeenHash = hash;
    
    // Process only if clipboard changed AFTER app started
    if (hash != _initialClipboardHash) {
      _captureService.handleNewUrl(content);
    }
  }
}
```

Edge case: User copies URL → app launches 2 seconds later → URL still in clipboard but no popup (matches initial state, treated as pre-existing). User must re-copy to trigger.

### 5.4 Window lifecycle

```
App start ──▶ ClipboardMonitor active
                   │
                   │ URL detected
                   ▼
            CaptureService eligible? (not snoozed)
                   │
                   ├─ Snoozed → drop, log
                   │
                   └─ Active
                        │
                        ▼
                  oEmbed fetch (parallel)
                        │
                        ├─ Success → spawn floating window with VideoPreview
                        │
                        └─ Fail → spawn floating window with error state
                                  
              Floating window visible
                        │
                        ├─ User clicks Tải xuống → trigger shared download flow → close popup → system notification
                        ├─ User clicks ✕ → close popup, queue cleared
                        ├─ User snoozes → close popup, queue cleared, set snooze state
                        ├─ User clicks "Mở trong Svid" → bring main window to focus, route URL → close popup
                        ├─ User drags → save position
                        └─ New URL captured → push to queue
```

---

## 6. Cross-platform implementation

### 6.1 Platform support matrix

| Feature | macOS | Windows | Linux |
|---------|-------|---------|-------|
| Floating window | ✅ NSPanel | ✅ Win32 layered window | ❌ v2.1 (defer v2.2) |
| Always-on-top | ✅ NSFloatingWindowLevel | ✅ HWND_TOPMOST | ❌ |
| No focus steal | ✅ becomesKeyOnlyIfNeeded | ✅ WS_EX_NOACTIVATE | ❌ |
| Tray icon | ✅ NSStatusItem | ✅ NotifyIcon | ❌ |
| Auto-launch | ✅ SMAppService | ✅ Registry HKCU | ❌ |
| Clipboard event listener | ✅ NSPasteboardDidChangeNotification | ✅ AddClipboardFormatListener | ❌ |
| System notification | ✅ UserNotifications | ✅ Toast | ❌ |
| Multi-monitor positioning | ✅ NSScreen | ✅ MonitorFromPoint | ❌ |

### 6.2 macOS implementation

> ⚠️ **Code samples in this section are ILLUSTRATIVE** — they show conceptual API usage. Actual implementation requires:
> - Flutter platform channel for Dart ↔ native communication
> - Method handler in `AppDelegate` (Swift) or via FlutterMethodChannel
> - Asset bundling for tray icons in macOS app bundle
> - Updated `Runner.entitlements` if sandbox restricts clipboard
>
> Implementer should treat these as architectural reference, not production code.

**Floating window**:
```swift
// macos/Runner/FloatingCaptureWindow.swift
let panel = NSPanel(
  contentRect: rect,
  styleMask: [.titled, .closable, .nonactivatingPanel],
  backing: .buffered,
  defer: false
)
panel.level = .floating  // Above normal windows
panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
panel.becomesKeyOnlyIfNeeded = true  // Don't steal focus
panel.hidesOnDeactivate = false
```

**Clipboard polling implementation** (corrected per audit):

Apple does NOT provide `NSPasteboardDidChangeNotification` or similar event API for clipboard changes. The standard pattern is **polling `NSPasteboard.changeCount`**:

```swift
// macos/Runner/ClipboardMonitor.swift (illustrative)
class ClipboardMonitor {
    private var lastChangeCount: Int
    private var timer: Timer?
    
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let current = NSPasteboard.general.changeCount
            if current != self.lastChangeCount {
                self.lastChangeCount = current
                if let str = NSPasteboard.general.string(forType: .string) {
                    self.onClipboardChange(str)
                }
            }
        }
    }
}
```

Energy considerations:
- 500ms poll interval acceptable (Apple Energy Impact rating "Low" per Activity Monitor testing)
- Pause polling when system battery < 10% to extend laptop battery
- Alternative: 1000ms interval if Energy Impact concerns surface in QA

**Sandbox entitlements** (verify before build):
- App is currently sandboxed per macOS App Store guidelines (verify in `.entitlements`)
- Clipboard polling from background OK without extra entitlement (changeCount + string read are standard NSPasteboard ops)

**Tray (NSStatusItem)**:
```swift
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(named: "TrayIcon")
let menu = NSMenu()
menu.addItem(withTitle: "Mở Svid", action: #selector(openMain), keyEquivalent: "")
menu.addItem(NSMenuItem.separator())
menu.addItem(withTitle: "Thoát", action: #selector(quit), keyEquivalent: "q")
statusItem.menu = menu
```

**Auto-launch (modern API)**:
```swift
import ServiceManagement
SMAppService.mainApp.register()  // Adds to Login Items
```

### 6.3 Windows implementation

> ⚠️ **Code samples ILLUSTRATIVE** — Windows native uses C++ via Flutter Windows Plugin pattern. Implementation needs:
> - Flutter plugin scaffold (`flutter create --template=plugin --platforms=windows`)
> - Dart ↔ C++ via MethodChannel
> - Win32 API integration trong plugin's `windows/runner.cpp`
> - HICON resource bundling

**Floating window**:
```cpp
// windows/runner/floating_capture_window.cpp
HWND hwnd = CreateWindowExW(
  WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
  className, nullptr,
  WS_POPUP | WS_VISIBLE,
  x, y, 300, 420,
  nullptr, nullptr, hInstance, nullptr
);
SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
             SWP_NOMOVE | SWP_NOSIZE);
```

**Tray (NotifyIcon)**:
```cpp
NOTIFYICONDATAW nid = { sizeof(NOTIFYICONDATAW) };
nid.hWnd = hwndMain;
nid.uID = TRAY_ICON_ID;
nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
nid.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_TRAYICON));
wcscpy(nid.szTip, L"Svid");
nid.uCallbackMessage = WM_TRAYICON;
Shell_NotifyIconW(NIM_ADD, &nid);
```

**Auto-launch (registry)**:
```cpp
HKEY hKey;
RegOpenKeyExW(HKEY_CURRENT_USER,
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
  0, KEY_SET_VALUE, &hKey);
RegSetValueExW(hKey, L"Svid", 0, REG_SZ,
  (BYTE*)exePath, (wcslen(exePath) + 1) * sizeof(wchar_t));
```

**Clipboard listener (Vista+)**:
```cpp
AddClipboardFormatListener(hwndMain);
// Receive WM_CLIPBOARDUPDATE messages
```

### 6.4 Linux deferred (v2.2+)

Reasons for deferral:
- Wayland clipboard isolation strict (modern Ubuntu/Fedora default)
- Multiple display servers (X11/Wayland) → 2x implementation
- Smaller user base for Svid Linux

When implemented (v2.2): use `desktop_multi_window` plugin if mature, otherwise GTK4 native window with `_NET_WM_STATE_ABOVE`.

---

## 7. Tray integration

### 7.1 Tray icon

| Platform | Asset path |
|----------|-----------|
| macOS | `assets/icons/tray-macos.png` (template image, 18×18 + 2x) |
| Windows | `assets/icons/tray-windows.ico` (16×16, 32×32 multi-res) |

**Single state** — same icon regardless of capture state (per Q16 decision).

### 7.2 Menu (per Q14)

```
Svid
─────────────────
Mở Svid           ⌘O / Ctrl+O
─────────────────
Thoát              ⌘Q / Ctrl+Q
```

**Tray icon click behavior** (per platform convention):

| Action | macOS | Windows |
|--------|-------|---------|
| Left-click / single-click | Show menu (NSStatusItem default) | Toggle main window (show if hidden, hide if shown) |
| Right-click | Show menu | Show menu (Q14 minimal: Mở Svid + Thoát) |
| Double-click | (no action) | Show main window (Windows convention) |

Rationale: macOS users expect left-click → menu (matching system tray apps like Bartender, Stats). Windows users expect left-click → toggle (matching Discord, Slack tray pattern).

Both platforms: menu items "Mở Svid" and "Thoát" function identically.

### 7.3 Lifecycle behavior

- **App start**: Create tray icon. If auto-launch enabled, app may have started without main window visible (boot-time launch).
- **User clicks tray "Mở Svid"**: Show main window, focus.
- **User clicks tray "Thoát"**: Quit app fully (clipboard monitor stops, no more capture).
- **Main window close (X)**: Hide main window, app continues in background.

---

## 8. Settings → Capture section

### 8.1 UI spec (per Q20 — progressive disclosure, no resets)

```
Cài đặt → Cài đặt nâng cao → Bắt link tự động
─────────────────────────────────────────────

Trạng thái: ⏸ Đang tạm tắt 23 phút
[Bật lại ngay]                     ← Visible only when snoozed

☑ Bật bắt link tự động              ← Master toggle
☑ Tự khởi động cùng máy             ← Auto-launch toggle

▼ Tuỳ chọn nâng cao
   Vị trí mặc định: [Bottom-right ▼]
                    [Top-right]
                    [Top-left]
                    [Bottom-left]
   ☐ Hiển thị khi fullscreen
   ☐ Tôn trọng macOS Focus mode

▼ Thông tin
   ℹ️ App đọc clipboard, tìm regex URL video.
      Không lưu hoặc gửi nội dung khác đi đâu.
      
      Ngôn ngữ: Match ngôn ngữ app
      Phiên bản: v2.1.0
```

### 8.2 State indicator (reactive update)

State indicator must be **reactive** — Settings page hiển thị live state, không stale.

**Implementation**:
```dart
class CaptureStatusIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch snooze state (rebuilds when changed)
    final snoozeState = ref.watch(capturePreferencesProvider);
    
    // For timed snooze, also watch a periodic timer (every 60s)
    final tick = ref.watch(snoozeCountdownTimerProvider);
    
    if (snoozeState.isCurrentlyActive) return Text("✓ Đang bật");
    
    if (snoozeState.state == CaptureSnoozeState.snoozedPermanent) {
      return Text("⏹ Đã tắt");
    }
    
    // Timed snooze with live countdown
    final remaining = snoozeState.snoozeUntil!.difference(DateTime.now());
    return Text("⏸ Đang tạm tắt ${remaining.inMinutes} phút");
  }
}

// Timer provider — emits every 60s while user is on Settings page
final snoozeCountdownTimerProvider = StreamProvider.autoDispose<int>((ref) {
  return Stream.periodic(const Duration(seconds: 60), (i) => i);
});
```

**Behavior verified**:
| Scenario | Behavior |
|----------|----------|
| User on Settings page, snooze 30m active | Countdown updates every 60s ("23 phút" → "22 phút" → ...) |
| User on Settings page, snooze expires (timer crosses 0) | Auto-flip to "✓ Đang bật" within 60s |
| User clicks "Bật lại ngay" | Immediate state change, indicator updates instantly |
| User leaves Settings, returns 5min later | Indicator reflects current state on rebuild |

When `capture_snooze_state == snoozedTimed`:
- "⏸ Đang tạm tắt {n} phút" với live countdown (60s tick interval)
- "Bật lại ngay" button → instant resume

When `capture_snooze_state == snoozedPermanent`:
- "⏹ Đã tắt"
- "Bật lại ngay" button visible

When `active`:
- "✓ Đang bật"

---

## 9. Localization

### 9.1 New translation keys (~44 keys)

Add to `assets/translations/{vi,en,ja,pt,es}.json` under namespace `capture`:

```json
{
  "capture": {
    "popupTitle": "...",
    "popupHintFirstRun": "Svid tự bắt link khi copy. Bấm ⋮ để tạm tắt nếu không cần.",
    "fetchFailed": "Không lấy được thông tin video",
    "downloadButton": "Tải xuống",
    "downloadAttemptButton": "Tải xuống thử",
    "upgradePremiumButton": "⭐ Nâng cấp Premium",
    "openInAppButton": "Mở trong Svid",
    "advancedOptionsLabel": "Tuỳ chọn nâng cao",
    "collapseLabel": "Thu gọn",
    "queueHeader": "Link {current}/{total}",
    "skipAllButton": "Bỏ qua tất cả {count}",
    "snoozeMenu30Min": "Tạm tắt 30 phút",
    "snoozeMenu1Hour": "Tạm tắt 1 tiếng",
    "snoozeMenu4Hours": "Tạm tắt 4 tiếng",
    "snoozeMenu1Day": "Tạm tắt 1 ngày",
    "snoozePermanent": "Tắt cho đến khi bật lại",
    "snoozedToast": "Đã tạm tắt đến {time}",
    "snoozedToastUndo": "Hủy",
    "settingsCaptureSection": "Bắt link tự động",
    "settingsStatusActive": "✓ Đang bật",
    "settingsStatusSnoozedTimed": "⏸ Đang tạm tắt {minutes} phút",
    "settingsStatusSnoozedPermanent": "⏹ Đã tắt",
    "settingsResumeNow": "Bật lại ngay",
    "settingsCaptureToggle": "Bật bắt link tự động",
    "settingsAutoLaunchToggle": "Tự khởi động cùng máy",
    "settingsAdvanced": "Tuỳ chọn nâng cao",
    "settingsDefaultPosition": "Vị trí mặc định",
    "trayMenuOpen": "Mở Svid",
    "trayMenuQuit": "Thoát",
    "playlistTypeLabel": "Playlist {platform}",
    "channelTypeLabel": "Kênh {platform}",
    "videoTypeFallback": "{platform} link",
    "explainerNotInline": "Popup không tải playlist trực tiếp.",
    "notificationDownloadStarted": "Đã bắt đầu tải: {title}",
    "notificationDownloadComplete": "Đã tải xong: {title}",
    "notificationDownloadFailed": "Lỗi tải: {title}",
    "dismissButton": "✕",
    "dismissAriaLabel": "Đóng popup",
    "thumbnailAriaLabel": "Xem video {title} trong trình duyệt",
    "expandAriaLabel": "Mở rộng tuỳ chọn nâng cao",
    "collapseAriaLabel": "Thu gọn tuỳ chọn",
    "queuePrevAriaLabel": "Link trước trong hàng đợi",
    "queueNextAriaLabel": "Link tiếp trong hàng đợi",
    "menuMoreAriaLabel": "Mở menu tuỳ chọn"
  }
}
```

Use existing `AppLocalizations` pattern — generate static getters via codegen.

---

## 10. Migration v2.0 → v2.1

### 10.1 Feature flag (local only)

```dart
// lib/core/feature_flags.dart
class FeatureFlags {
  /// v2.1 floating capture feature — local-only flag.
  /// Compiled per release. No remote config in v2.1.
  static const bool floatingCaptureEnabled = true;
}
```

**Scope correction (per audit P1-4)**: This is a **local-only compile-time flag**, not a remote kill switch. Flipping it requires app update.

**Why no remote kill switch in v2.1**:
- Current backend (`api.svid.app`) does not expose feature-flag config endpoint
- Sentry feature flags integration not implemented in current SDK setup
- Adding remote config infrastructure is out-of-scope for v2.1

**Mitigation if critical bug post-release**:
- Hotfix release with `floatingCaptureEnabled = false`
- macOS users via Sparkle auto-update; Windows via in-app updater
- Disable typically reaches >80% installed base within 24h
- Manual workaround: user can disable in Settings → Capture (per Q20)

**v2.2 future**: Add proper remote config (lightweight backend endpoint or Firebase Remote Config) for instant kill switch.

### 10.2 First launch detection

```dart
// On v2.1 first launch:
final prefs = await SharedPreferences.getInstance();
final firstV21Launch = !(prefs.getBool('v2_1_launched') ?? false);  // correct precedence

if (firstV21Launch) {
  await prefs.setBool('v2_1_launched', true);
  
  // Per Q6/Q7: capture default ON, auto-launch default ON
  await prefs.setBool('capture_enabled', true);
  await prefs.setBool('auto_launch_enabled', true);
  await registerAutoLaunch();  // platform-specific
  
  // Show "What's new" toast (1 time)
  await showWhatsNewToast(context, version: '2.1');
}
```

### 10.3 Window close behavior migration (existing code change)

Existing code in [`app_scaffold.dart:304-308`](lib/core/navigation/app_scaffold.dart:304):
```dart
@override
void onWindowClose() async {
  appLogger.info('Window close requested');
  await WindowService.saveWindowState();
  await windowManager.destroy();   // ⚠️ exits app entirely
}
```

**v2.1 migration**:
```dart
@override
void onWindowClose() async {
  appLogger.info('Window close requested');
  await WindowService.saveWindowState();
  
  // v2.1: minimize to tray instead of destroy (per Q4)
  // Real exit only via tray "Thoát" menu item or platform Cmd+Q
  if (await CaptureService.isFeatureEnabled()) {
    await windowManager.hide();        // Hide but keep app alive in tray
  } else {
    await windowManager.destroy();     // Legacy behavior if floating capture disabled
  }
}

// New tray menu handler:
void onTrayQuit() async {
  await WindowService.saveWindowState();
  await windowManager.destroy();       // Real exit from tray menu
}
```

**Trade-off**: Users who disable floating capture get legacy behavior (close = exit). Avoids breaking expectations for users who don't want tray-resident.

**Edge case Cmd+Q (macOS) / Alt+F4 (Windows)**: System-level quit shortcut bypasses our `onWindowClose` interceptor by default. Keep default behavior — user explicitly wants exit, respect it. Tray + main window will close together.

### 10.4 Settings persistence keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `capture_enabled` | bool | true | Master capture toggle |
| `capture_snooze_state` | string | "active" | enum string |
| `capture_snooze_until` | string? | null | ISO8601 timestamp |
| `auto_launch_enabled` | bool | true | OS-level auto-start |
| `floating_default_position` | string | "bottomRight" | Corner enum |
| `floating_last_position_x` | double? | null | Last drag X (logical pixels) |
| `floating_last_position_y` | double? | null | Last drag Y |
| `floating_last_monitor_id` | string? | null | Monitor identifier |
| `first_capture_shown` | bool | false | First-run hint flag |
| `show_when_fullscreen` | bool | false | Advanced option |
| `respect_focus_mode` | bool | false | Advanced option (default OFF) |

---

## 11. Edge case matrix

### 11.1 Resolved (handled in design)

| # | Edge case | Resolution |
|---|-----------|------------|
| E1 | User copies same URL twice within 60s | Dedup — ignore second |
| E2 | Queue full (5 items), 6th URL arrives | Drop oldest (FIFO) |
| E3 | User snoozed, app suspended, wakes after expiry | `DateTime.now() > snoozeUntil` → auto-resume |
| E4 | Multi-monitor, primary disconnected during session | Validate position in active monitor bounds, fallback default |
| E5 | YouTube channel URL copied (not video) | Show "Mở trong Svid" popup |
| E6 | Free user quota = 0 | Show popup with "Nâng cấp Premium" CTA |
| E7 | oEmbed network timeout | Fallback popup with platform icon + URL + "Tải xuống thử" |
| E8 | URL with `?t=120s` timestamp | Preserve in `VideoPreview.startTimestamp` for Section trim |
| E9 | TikTok short URL (vm.tiktok.com/...) | HEAD redirect resolve before oEmbed |
| E10 | App crash during snooze | Snooze state persists in SharedPreferences, resumes on next launch |
| E11 | System time changed during snooze | Use absolute wall-clock comparison; snooze still expires at original target |
| E12 | User force-quits via Activity Monitor | Tray icon disappears; clipboard monitor stops; relaunch needed |
| E13 | Auto-launch disabled in OS Login Items by user | Settings detects, syncs toggle state |
| E14 | App update during running | Detect → tray notification → user-initiated quit + relaunch |
| E15 | Permanent snooze, user forgets months later | Settings → Capture always shows status + "Bật lại" |
| E16 | Clipboard contains **non-URL text** (vd: copied chunk of code) | `UrlPatternService.classify(text) == notUrl` → silent skip, no popup |
| E17 | URL có **auth token** (vd: signed S3 URL với credentials) | Clipboard polling đọc URL, không log/transmit; oEmbed fail (private) → fallback popup. Token never leaves user's device. |
| E18 | URL **rất dài** (>2000 chars, vd Twitter share với many params) | Truncate display tới 100 chars + ellipsis trong popup; pass full URL to oEmbed; preserve in `rawUrl` |
| E19 | URL với **anchor fragment** (`#t=120s` hoặc `#section`) | Extract video ID from URL **trước** `#`; preserve fragment in `rawUrl`; map `#t=Ns` → `VideoPreview.startTimestamp` (same as `?t=` query param) |
| E20 | **Image clipboard** (user copy ảnh, không phải text) | `ClipboardMonitorService.readClipboard()` only reads text content; ignore image/file types entirely |

### 11.2 Acceptable trade-offs (not addressed)

| # | Edge case | Rationale |
|---|-----------|-----------|
| A1 | User in fullscreen game gets popup | Per Q8: no auto-skip. User can snooze. |
| A2 | macOS Focus mode active gets popup | Per Q8: no auto-skip. User can disable in advanced settings. |
| A3 | User snoozes 10x/day, never re-enables | Per Q25: no app intervention. User decides. |
| A4 | Tray icon doesn't show snooze state | Per Q16: simplicity preferred. State visible in main app Settings. |
| A5 | Linux users have no floating capture | Per Q12: deferred to v2.2 |
| A6 | User typing in chat gets popup | Per Q15: non-stealing focus, popup doesn't disrupt typing. |
| A7 | No telemetry to measure success | Per Q21: privacy-first stance. Manual user feedback only. |

---

## 12. Effort breakdown

### 12.1 Task list

| # | Task | Effort | Dependencies |
|---|------|--------|--------------|
| 1 | Spike: `desktop_multi_window` plugin spike on macOS + Windows | 1d | - |
| 2 | Spike: clipboard event listener on macOS + Windows | 1d | - |
| 3 | `ClipboardMonitorService` (cross-platform abstraction) | 1d | #2 |
| 4 | `UrlPatternService` (already started in inline preview Phase 1A) | 0.5d | - |
| 5 | `LightweightPreviewService` (oEmbed for 5 platforms) | 1.5d | - |
| 6 | `VideoPreview` entity (already started) | 0.25d | - |
| 7 | `CaptureService` (orchestration: snooze check → fetch → queue) | 1d | #3, #5 |
| 8 | `CapturePreferencesProvider` (snooze state, settings) | 0.5d | - |
| 9 | `FloatingWindowManager` (Dart side) | 1.5d | #1 |
| 10 | macOS native floating window (NSPanel) | 2d | #1 |
| 11 | Windows native floating window (Win32 layered) | 2d | #1 |
| 12 | Floating window UI — all 7 states | 2d | #6, #9 |
| 13 | Queue navigation + dedup logic | 0.5d | #7, #12 |
| 14 | Snooze flow + toast + undo | 1d | #8, #12 |
| 15 | Tray icon — macOS NSStatusItem | 0.5d | - |
| 16 | Tray icon — Windows NotifyIcon | 0.5d | - |
| 17 | Auto-launch — macOS SMAppService | 0.5d | - |
| 18 | Auto-launch — Windows Registry | 0.5d | - |
| 19 | System notification (after download) | 0.5d | - |
| 20 | Settings → Capture section UI | 1d | #8 |
| 21 | Localization (5 languages, 25 keys) | 0.5d | #20 |
| 22 | First-run hint logic | 0.25d | #12 |
| 23 | Multi-monitor cursor detection + positioning | 0.5d | #9 |
| 24 | Window position persistence + restore | 0.25d | #9 |
| 25 | Click thumbnail → external browser | 0.25d | #12 |
| 26 | Quota=0 button transformation | 0.25d | #12 |
| 27 | Non-video URL routing to main app | 0.5d | #4, #12 |
| 28 | Shared download service integration (per Q26) | 0.5d | #7 |
| 29 | Test plan execution (cross-platform matrix) | 2d | All |
| 30 | Bug triage + polish | 1d | All |
| **Total** | | **~22 ngày** | |

### 12.2 Phasing for parallel work

If 2 developers:
- **Track A** (UI/Dart): tasks 4-9, 12-14, 19-28 (~11 days)
- **Track B** (Native): tasks 1-3, 10-11, 15-18 (~7 days)
- **Convergence**: tasks 29-30 (~3 days)
- **Calendar time**: ~14 days (vs 22 serial)

### 12.3 Risks & buffers

| Risk | Probability | Impact | Buffer |
|------|-------------|--------|--------|
| `desktop_multi_window` plugin issues | Medium | High | +2 days for native fallback |
| macOS sandbox entitlement issues | Medium | High | +1 day for entitlement update + re-notarization |
| Cross-platform DPI/positioning bugs | High | Medium | +1.5 days testing |
| Clipboard event listener flaky | Low | Low | Fallback to polling already designed |
| **Total buffer** | | | **+4.5 days** |

**Realistic estimate** (revised v1.1 — em đã đánh giá quá lạc quan ban đầu):

Underestimated tasks identified:
- Task 12 "Floating window UI — all 7 states": 2d → **3d** (7 states × light/dark theme × responsive variants)
- Task 29 "Test plan execution": 2d → **3d** (cross-platform manual QA + stress tests added §13.4)
- Task 30 "Bug triage + polish": 1d → **2d** (realistic for first-version cross-platform feature)

Adjusted total: 22d + 3d underestimate = 25d serial.
With 4.5d risk buffer: **~30 days** = ~6 weeks single dev.

Parallel (2 devs): ~16-18 days calendar.

---

## 13. Test plan

### 13.1 Unit tests

| Component | Test scenarios |
|-----------|----------------|
| `UrlPatternService` | YouTube/TikTok/IG/X/Reddit/Vimeo pattern match; channel/playlist/live/search URLs; timestamp extraction; non-URL strings |
| `LightweightPreviewService` | oEmbed success/404/401/timeout per platform; thumbnail URL building |
| `CaptureService` | Snooze active → drop event; queue overflow drops oldest; dedup within 60s |
| `CapturePreferences` | Persist/restore; snooze expiry calculation; system time change |

### 13.2 Widget tests

- Each popup state renders correctly with expected dimensions
- Expand/collapse animation
- Queue navigation (prev/next buttons disabled at boundaries)
- Snooze menu actions trigger correct state changes
- First-run hint shown only once

### 13.3 Integration tests (per platform)

#### macOS
- [ ] Floating window appears at correct position on URL copy
- [ ] Window draggable, position persists across restarts
- [ ] Multi-monitor: window appears on cursor's monitor
- [ ] Window doesn't steal focus (verify keyboard input continues in another app)
- [ ] Tray icon shows; menu items work
- [ ] Click X on main window → minimizes to tray
- [ ] App restart auto-launches correctly
- [ ] Snooze 30m → expires at 30m, popup resumes
- [ ] Snooze permanent → only Settings can re-enable
- [ ] System sleep during snooze → wakes, snooze still tracked correctly
- [ ] Notification appears after download starts

#### Windows
- [ ] Same as macOS list, with Windows-specific verification
- [ ] Notification toasts (Windows 10+)
- [ ] Auto-launch via registry verified

### 13.4 Stress / performance / memory tests

App tray-resident chạy 24/7 → cần verify không leak resources.

| Test | Acceptance criteria |
|------|---------------------|
| **Memory leak — 1000 captures** | Trigger 1000 sequential URL captures (mock clipboard). RSS memory growth < 50MB after baseline. |
| **Memory leak — 24h idle** | App run 24 hours với clipboard monitoring active, no captures triggered. RSS growth < 20MB. |
| **Window spawn/dispose** | Spawn + close popup 100 times consecutively. No Flutter engine leak (verify via Activity Monitor / Task Manager). |
| **File handle leak** | Clipboard polling 1000 reads (test mode forced polling). No fd accumulation (`lsof -p <pid>` count stable). |
| **Popup open latency** | Time from URL clipboard event to popup visible. p50 < 300ms, p95 < 800ms (cold), < 200ms (warm). |
| **oEmbed fetch latency** | Per-platform p50/p95 measurement. Acceptable: YouTube < 500ms, others < 800ms. |
| **CPU usage idle** | App tray-resident with no captures. CPU < 0.5% on macOS Activity Monitor / Windows Task Manager. |
| **Battery impact macOS** | macOS Energy Impact rating "Low" or better when running in tray (Activity Monitor → Energy tab). |

Tools:
- macOS: Activity Monitor, Instruments (Allocations + Leaks template)
- Windows: Task Manager, Windows Performance Recorder (WPR), VMMap

### 13.5 Manual QA matrix

| Scenario | macOS | Windows |
|----------|-------|---------|
| First install → copy URL → see popup | ☐ | ☐ |
| Click Tải xuống → download in main app history | ☐ | ☐ |
| Copy 6 URLs rapidly → queue shows 5 (oldest drop) | ☐ | ☐ |
| Click "Mở trong Svid" on playlist URL → main app sheet | ☐ | ☐ |
| Snooze 30m, copy URL during → no popup | ☐ | ☐ |
| Snooze 30m, wait 31m, copy URL → popup | ☐ | ☐ |
| Permanent snooze, restart app, copy URL → no popup | ☐ | ☐ |
| Close X main window → minimizes to tray, capture still works | ☐ | ☐ |
| Reboot computer → app auto-launches, tray visible | ☐ | ☐ |
| Multi-monitor: copy URL on left monitor, popup appears left | ☐ | ☐ |
| Quota=0: popup shows "Nâng cấp Premium" button | ☐ | ☐ |
| oEmbed fail (e.g., private video): fallback popup with "Tải xuống thử" | ☐ | ☐ |

---

## 14. Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|-----------|
| Plugin `desktop_multi_window` abandoned/broken | Low | High | Native fallback, 2d buffer |
| macOS App Store rejection (clipboard concerns) | Low | Medium | Privacy notice in Settings; document in app description |
| Windows antivirus flags clipboard monitoring | Medium | Medium | Code-signing; document clear privacy notice |
| Performance: clipboard polling battery impact | Low | Low | Use event listeners; fallback polls 1s only |
| User dislikes aggressive default ON | Medium | Medium | Easy snooze controls; permanent disable available |
| Floating window doesn't render correctly on HiDPI | Medium | Medium | Test on 4K, Retina, mixed DPI in QA |
| App update flow breaks tray-resident state | Low | High | Quit-on-update flow; clear messaging |
| Cross-platform parity drift | High | Medium | Strict spec; Q&A audit (this doc) covers most |
| Native code crashes leak to Flutter | Medium | High | Crash isolation via separate engines (`desktop_multi_window`) |
| **macOS Apple notarization rejection** (clipboard polling concerns) | Low | High | Privacy notice clear in Info.plist usage description; document for App Review; entitlement file thorough |
| **Windows SmartScreen warning** trên first install | Medium | Medium | Code-signing certificate (EV cert preferred for instant trust); accumulate signed installs over time |
| **`desktop_multi_window` plugin abandonment** | Medium | High | Pin to known-good version; spike fork cost (~3 days to maintain ourselves if needed); native fallback documented |
| **User backlash on social media** ("app reads my clipboard") | Low | Medium | Clear privacy notice in Settings + first-run hint; opt-out easy; open-source code transparency |
| **GDPR/privacy regulator inquiry (EU users)** | Low | High | Data Processing notice in privacy policy; document local-only processing; no transmission of clipboard content |

---

## 15. Future enhancements (v2.2+)

| Feature | Justification |
|---------|---------------|
| Linux support (Wayland + X11) | Once user demand validated post-v2.1 |
| Browser extension companion | IDM-grade integration; capture from browser context |
| Schedule snooze (sleep hours, weekends) | Power user feature; advanced Settings |
| Per-platform snooze (e.g., snooze YouTube only) | Niche but valuable |
| Smart context detection (DnD, fullscreen apps) | Quality-of-life if user demand grows |
| Telemetry (opt-in) | Data-driven iteration if needed |
| Floating window themes (compact/comfortable) | Customization |
| Voice control: "Hey Svid, tải video này" | Long-tail innovation |
| Cross-device handoff (phone copy → desktop popup) | Differentiation |

---

## 16. Acceptance checklist

- [ ] All 28 finalized decisions implemented faithfully
- [ ] macOS and Windows feature parity (Linux deferred per Q12)
- [ ] All 7 popup states render at correct dimensions (300×420 / 300×560 / etc.)
- [ ] Queue handles ≥5 URLs correctly (FIFO drop, dedup)
- [ ] Snooze persists across restarts and system sleep
- [ ] Capture default ON after fresh install (per Q6)
- [ ] Auto-launch default ON after fresh install (per Q7)
- [ ] Tray menu has only "Mở Svid" + "Thoát" (per Q14)
- [ ] No focus stealing verified (typing in another app continues uninterrupted)
- [ ] System notification fires after Tải xuống (per Q26)
- [ ] Download from popup shows in main app history identical to in-app download
- [ ] All 5 languages translated (per Q27)
- [ ] First-run hint shown once, suppressed thereafter
- [ ] oEmbed fail fallback popup has "Tải xuống thử" button (per Q23)
- [ ] Settings → Capture section progressive disclosure complete (per Q20)
- [ ] No telemetry events transmitted (per Q21)
- [ ] WCAG AA contrast for all popup states (light + dark mode)
- [ ] Multi-monitor positioning per cursor verified (per Q19)
- [ ] Position persistence across sessions verified
- [ ] Quota=0 popup shows "Nâng cấp Premium" (per Q9)
- [ ] No app intervention on snooze fatigue (per Q25)

---

## 17. Open questions for implementation team

1. Confirm `desktop_multi_window` plugin version and stability via spike before commit
2. macOS sandbox entitlement audit: does current `.entitlements` allow clipboard event listening from background?
3. Windows code-signing certificate covers tray + clipboard ops without antivirus flags?
4. Confirm `url_launcher` (existing dep) handles "open external browser" reliably on both platforms
5. Determine icon assets ownership — design team or Claude generates?
6. Telemetry/feature flag infrastructure — should we add lightweight remote config for safety toggles?
