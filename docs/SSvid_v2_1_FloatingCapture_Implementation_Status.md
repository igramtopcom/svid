# SSvid v2.1 Floating Capture — Implementation Status

> Single-source-of-truth for the floating capture feature on branch
> `claude/sharp-diffie-f83a32`. Update this when shipping new slices.

**Status**: Architecturally complete. End-to-end functional on macOS + Windows.
Pending native polish + i18n.

**Last verified**: CI run [25385777302](https://github.com/kynndev/ssvid_app/actions/runs/25385777302) — covers all Codex-audit fixes through P1 #2 (queue UX). 287 tests passing, all P0 + P1 closed.

---

## 1. Phase log

Each slice = one self-contained commit (or a feat + audit pair). Click the
hash to inspect the diff.

### Phase 1A — core feature

| Slice | Commit | Lines | Tests added |
|---|---|---|---|
| 1A.1 — URL classifier + oEmbed preview service | [`6bb40de3`](https://github.com/kynndev/ssvid_app/commit/6bb40de3) + audit [`8b7aee77`](https://github.com/kynndev/ssvid_app/commit/8b7aee77) | ~600 | ~80 |
| 1A.2 — Native clipboard (macOS Swift + Windows C++) | [`d8114264`](https://github.com/kynndev/ssvid_app/commit/d8114264) → [`0ae54c50`](https://github.com/kynndev/ssvid_app/commit/0ae54c50) + audits | ~750 | ~30 |
| 1A.3 — FloatingWindow architecture | spike [`ac4f1685`](https://github.com/kynndev/ssvid_app/commit/ac4f1685) → 3a/3b/3c [`956dde37`](https://github.com/kynndev/ssvid_app/commit/956dde37)/[`33b103d2`](https://github.com/kynndev/ssvid_app/commit/33b103d2)/[`ad755277`](https://github.com/kynndev/ssvid_app/commit/ad755277) + audit [`0309c143`](https://github.com/kynndev/ssvid_app/commit/0309c143) | ~1500 | ~50 |
| 1A.4 — Popup UI design (Wine Red, 300×420) | [`41778634`](https://github.com/kynndev/ssvid_app/commit/41778634) + audit [`f570831b`](https://github.com/kynndev/ssvid_app/commit/f570831b) | ~700 | (UI only) |
| 1A.5 — CaptureService coordinator | [`226269b9`](https://github.com/kynndev/ssvid_app/commit/226269b9) + audit [`4c80e476`](https://github.com/kynndev/ssvid_app/commit/4c80e476) | ~900 | +39 |
| 1A.6a — Provider wiring + side-effect router | [`8dbb696d`](https://github.com/kynndev/ssvid_app/commit/8dbb696d) | ~390 | +9 |
| 1A.6b — Auto-start in main.dart | [`c67b37e9`](https://github.com/kynndev/ssvid_app/commit/c67b37e9) | ~330 | +10 |
| 1A.7 — Settings UI + boot gate | [`5bfbd047`](https://github.com/kynndev/ssvid_app/commit/5bfbd047) + audit [`bb77a816`](https://github.com/kynndev/ssvid_app/commit/bb77a816) | ~410 | +13 |
| 1A.8 — pause/resume lifecycle | [`97be4844`](https://github.com/kynndev/ssvid_app/commit/97be4844) | ~110 | +5 |

### Phase 1B — cross-feature integration

| Slice | Commit | What |
|---|---|---|
| 1B.1 — onDownload | [`cc7f0008`](https://github.com/kynndev/ssvid_app/commit/cc7f0008) + audit [`d67c1ae1`](https://github.com/kynndev/ssvid_app/commit/d67c1ae1) | popup Download click → HomeScreen.startDownload via pendingProvider |
| 1B.2 — onOpenInApp | [`f6d2a9df`](https://github.com/kynndev/ssvid_app/commit/f6d2a9df) | popup Open-in-SSvid → HomeScreen URL field + focus (no auto-start) |
| 1B.3 — onOpenSettings | [`6c913a03`](https://github.com/kynndev/ssvid_app/commit/6c913a03) | popup menu Settings → navigationProvider tab change |

### Phase 1C — native polish

| Slice | Commit | What |
|---|---|---|
| 1C.1 — Floating-panel attributes | [`dcc1ff4b`](https://github.com/kynndev/ssvid_app/commit/dcc1ff4b) | macOS `level=.statusBar` + cross-Spaces; Windows HWND_TOPMOST + WS_EX_NOACTIVATE |
| 1C.2 — Drag-saved popup position | [`ddab63ec`](https://github.com/kynndev/ssvid_app/commit/ddab63ec) + audit M1 [`cdecb20a`](https://github.com/kynndev/ssvid_app/commit/cdecb20a) | popup respects user's drag; popup-side show() removes first-spawn flicker |

### Phase 1D — i18n

| Slice | Commit | What |
|---|---|---|
| 1D — Localization (5 langs) | [`ee63dadf`](https://github.com/kynndev/ssvid_app/commit/ee63dadf) | en + vi proper translations; es/pt/ja English placeholder. Settings card uses easy_localization; popup engine has inline string table to keep boot fast. |

### Phase 1E — Codex external audit fixes

External Codex audit run on the full feature surface caught 8 real
findings the self-review missed. Each commit is one batch.

| Slice | Commit | Findings |
|---|---|---|
| Batch 1 — critical path | [`f413c15a`](https://github.com/kynndev/ssvid_app/commit/f413c15a) | P0 dismiss desync, P1 #1 terminal auto-close, P1 #5 Windows panel show-before-noactivate, P1 #6 search URL filter |
| Lifecycle wins | [`a6677e1c`](https://github.com/kynndev/ssvid_app/commit/a6677e1c) | P1 #3 cancellation token, P2 macOS onCancel timer, P2 subscribe-before-start (+ dispose ordering bug found while testing) |
| P1 #4 — ready-ack handshake | [`d5891a63`](https://github.com/kynndev/ssvid_app/commit/d5891a63) | Popup signals `popupReady` after registering its handler so main side's first invokeMethod doesn't race the popup's setMethodCallHandler. 3-second timeout fallback. |
| P1 #7 — snooze "1 day" | [`25a4886f`](https://github.com/kynndev/ssvid_app/commit/25a4886f) | `untilEndOfDay` (midnight today, 10 min at 23:50) → `oneDay` (literal 24h). Legacy wireKey accepted for migration. |
| P1 #2 — queue UX | [`eb010d5f`](https://github.com/kynndev/ssvid_app/commit/eb010d5f) + mockups [`ac34fd17`](https://github.com/kynndev/ssvid_app/commit/ac34fd17) | Bounded queue (max 5 + drop-oldest) with selectedIndex, _QueueThumbnailStrip widget (variant 3 from Codex-generated mockups), per-item action targeting via _currentPreview getter. |

### Infrastructure

| What | Commit |
|---|---|
| Add CI workflow (analyze + macOS + Windows debug builds) | [`9fb74b1b`](https://github.com/kynndev/ssvid_app/commit/9fb74b1b) |
| Fix Windows linker — link `flutter_wrapper_plugin` for inline plugins | [`2f1da886`](https://github.com/kynndev/ssvid_app/commit/2f1da886) |

---

## 2. Architecture overview

### Runtime data flow

```
┌──────────────────────────┐            ┌──────────────────────────┐
│  Main Flutter engine     │            │  Popup Flutter engine    │
│  (host app)              │            │  (separate engine        │
│                          │            │   spawned by             │
│  ClipboardMonitorService │  spawn()   │   desktop_multi_window)  │
│       │                  ├───────────►│                          │
│       │ String URL       │            │  floating_window_main    │
│       ▼                  │            │  + window_manager chrome │
│  CaptureService          │            │  + FloatingCapturePanel  │
│       │                  │            │    Plugin (level/topmost)│
│       │ fetch preview    │            │                          │
│       ▼                  │            │  Wine Red popup UI       │
│  LightweightPreviewSvc   │            │  (300×420 portrait)      │
│  (oEmbed → VideoPreview) │            │                          │
│       │                  │            │  ┌────────────────────┐  │
│       ▼                  │            │  │ thumbnail / title  │  │
│  FloatingWindow          │  WindowMethodChannel               │
│  (DesktopMultiWindow…)   │  ssvid.floating_capture           │  │
│       │                  ├──showPreview / pushQueue / setQuota│  │
│       │                  │  ◄──onDownload / onSnoozeSelected /│  │
│       │                  │     onMenuOpenApp / OpenSettings…  │  │
│       │                  │            │  └────────────────────┘  │
│       ▼                  │            │  [Download] [Snooze]     │
│  CaptureSideEffect      │            └──────────────────────────┘
│  (sealed: StartDownload, │
│   OpenExternal,          │
│   OpenInApp,             │
│   OpenMainApp,           │
│   OpenCaptureSettings)   │
│       │                  │
│       ▼                  │
│  CaptureSideEffectRouter │
│  (host overrides:        │
│   onDownload  → HomeScreen.startDownload via pendingProvider
│   onOpenInApp → HomeScreen URL field via pendingProvider
│   onOpenSettings → navigationProvider tab change
│   onOpenExternal → url_launcher (in-feature default)
│   onOpenMainApp  → WindowService.show (in-feature default))
│
└──────────────────────────┘
```

### Provider chain (main engine, Riverpod)

```
sharedPreferencesProvider          (existing global)
    │
    ├── snoozeStoreProvider                     ──┐
    ├── capturePreferencesStoreProvider         ──┤
    │                                              ├── captureServiceProvider
    │                                              │     │
    │   urlPatternServiceProvider               ──┤     ├── snoozeChangesStream
    │                                              │     │
    │   clipboardSourceProvider     ──┐           │     │
    │                                  ├── clipboardMonitorServiceProvider
    │                                  │           │
    │   lightweightPreviewServiceProvider        ──┤
    │   floatingWindowProvider                   ──┤
    │   captureQuotaPolicyProvider               ──┘
    │
    ├── captureSideEffectRouterProvider  (overridden in main.dart)
    │     │
    │     └── captureLifecycleControllerProvider
    │                │
    │                └── starts service, subscribes to sideEffects, dispatches
    │
    ├── capturePreferencesNotifierProvider
    │     │  (StateNotifier, watched by FloatingCaptureSettingsCard)
    │
    ├── captureSnoozeStreamProvider
    │     │  (StreamProvider seeded with currentSnooze, watched by Settings)
    │
    ├── pendingCaptureDownloadProvider     (StateProvider)
    └── pendingCaptureOpenInAppProvider    (StateProvider)
```

### Native plugin map

| Plugin | Where | Channel | Role |
|--------|-------|---------|------|
| ClipboardMonitorPlugin | main engine only | `ssvid.clipboard_monitor/{methods,events}` | macOS NSPasteboard.changeCount poll / Windows AddClipboardFormatListener |
| FloatingCapturePanelPlugin | popup engines only | `ssvid.floating_capture.native` | macOS NSWindow.level / Windows HWND_TOPMOST + WS_EX_NOACTIVATE |
| desktop_multi_window | both | `mixin.one/desktop_multi_window` | Plugin-managed; auto-registered via setOnWindowCreatedCallback |

---

## 3. Test coverage

```
flutter test test/features/floating_capture/
→ 287 tests, 0 failures, 0 skipped
```

By slice:
- snooze_duration_test (12)
- floating_window_event_test (2)
- mock_floating_window_test (21)
- parse_floating_window_event_test (15)
- url_pattern_service_test (~30)
- video_preview_test (~20)
- lightweight_preview_service_test (~25)
- clipboard_monitor_service_test (~15)
- native_clipboard_source_test (15)
- auto_launch_service_test (~12)
- capture_service tests (24 + 4 snooze stream)
- snooze_state_test (15)
- capture_side_effect_router_test (9)
- capture_lifecycle_controller_test (15: 10 base + 5 pause/resume)
- capture_preferences_test (13)
- build_default_router_test (5)
- window_position_test (11)
- + Codex audit fixes added 4 tests across snooze (legacy wireKey, oneDay), capture_service (stop/dispose mid-fetch), url_pattern (search isKnownUrlType)

Project-wide: 2564+ tests pass cross-platform on CI.

---

## 4. Outstanding deferred work

**Not blocking ship; not started.**

| Item | Source | Estimated cost |
|------|--------|----------------|
| Codex P2 — IPC URL allowlist | Main side accepts arbitrary string URLs from popup; should reclassify and allowlist scheme/host before launching | S (one boundary check) |
| Codex P2 — `_previewCache` LRU/TTL | Currently unbounded for long-running sessions | S (Map → bounded LRU) |
| Codex P3 — VideoPreview JSON schemaVersion | No explicit version field; add before more fields ship | S (schema field + parse fallback) |
| Codex P3 — popup widget tests + integration smoke tests | Cross-engine flows currently rely on manual QA | M (widget test harness) |
| macOS click-on-popup focus-steal prevention | Needs NSPanel subclass / styleMask conversion (proper fix). `level=.statusBar` already covers the common "popup pops up while typing" case. | M (Swift refactor) |
| Per-monitor saved position + off-screen recovery | 1C.2 ships single-slot position. Multi-monitor would key on display ID; off-screen recovery needs bounds-check vs current displays. | M (window_manager monitor API + bounds math) |
| Quota=0 upgrade UI variant (spec Q9) | Premium feature integration not yet done | L for capture side, paywall integration is separate |
| Auto-scroll Settings to capture section | Polish only | S (scroll target hint) |
| Proper es / pt / ja translations | 1D shipped English placeholder for these | S per locale (translation work) |
| macOS smoke test (manual QA) | Validates end-to-end flow on real hardware | One sitting on a macOS machine |

---

## 5. Manual smoke test plan

To validate the full flow on macOS:

1. Build + run debug:
   ```bash
   flutter build macos --debug
   open build/macos/Build/Products/Debug/ssvid.app
   ```

2. App launch — check logs for `[CaptureLifecycle] started` (Phase G post-frame)
3. Navigate to Settings → General → "Floating capture" toggle should be ON
4. Open Safari / any browser; copy a YouTube URL: `https://youtube.com/watch?v=dQw4w9WgXcQ`
5. Within ~500ms a 300×420 popup should appear with:
   - Wine Red brand dot + "SSvid" header
   - 16:9 thumbnail (or fallback if oEmbed fails)
   - Video title + uploader
   - "Download" primary button + Snooze + Dismiss
6. Click Download — main app brings itself to front, URL field populated, extraction starts
7. Copy a playlist URL: `https://www.youtube.com/playlist?list=PL...`
   - Popup updates in place
   - Primary button now reads "Open in SSvid"
   - Click it — main app forward, URL field populated, no auto-extract
8. Open popup menu (3-dot) → "Settings" — main app navigates to Settings tab
9. In Settings, snooze for 30 minutes — popup hides
10. Copy another URL — no popup (snoozed)
11. Click "Resume" — snooze cleared, popup behaviour restored

Verify across Spaces: pre-step popup visible, switch Space (Mission Control →) — popup follows.

---

## 6. Notable design decisions

**Separate engine, not shared state**: Popup runs its own Flutter engine.
WindowMethodChannel mediates state. The popup imports nothing from the main
app to keep boot fast (no Rust bridge / Sentry / tray).

**Send initial preview via launch args, not channel**: Avoids the
popup-not-yet-ready race on first paint. Subsequent updates do go through
the channel because the popup is alive.

**Sealed CaptureSideEffect hierarchy**: Adding a new variant becomes a
compile-time error in any consumer's switch statement. Prevents silent
"missing handler" bugs.

**Capture defaults ON (spec Q6)**: Settings toggle starts true; user can
disable. Phase G boot reads the preference before starting the lifecycle.

**StateProvider hand-off pattern (1B.1, 1B.2) vs direct state mutation
(1B.3)**: Hand-off is needed when the payload (URL, request) targets a
specific widget instance. Direct mutation works for global state
(navigation tab index).

**`fireImmediately: true` on home_screen listenManual** (1B.1 audit fix):
Closes the lost-request race when the popup fires before HomeScreen
subscribes.

**Cross-platform behavioural parity by design, not by claim**: Each
platform plugin (clipboard, panel) does the platform-idiomatic thing
(macOS NSPasteboard poll vs Windows AddClipboardFormatListener; macOS
.statusBar level vs Windows HWND_TOPMOST). The Dart side sees a uniform
contract.

---

## 7. Build / CI

- Lightweight CI workflow at `.github/workflows/ci.yml` runs on every
  push (except main) + PR. Three jobs: Analyze + Test (ubuntu),
  Build macOS debug (macos-latest), Build Windows debug (windows-latest).
- **Never** trigger `release.yml workflow_dispatch` for build verification
  — it builds in release mode AND publishes a real GitHub Release at the
  end. ci.yml is the right tool.
- Concurrency control cancels in-progress runs on new push to the same
  ref to save runner minutes.
