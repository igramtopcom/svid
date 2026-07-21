# Pass 2F — V2 Campaign Hyper-Plan Synthesis

**Aggregated input**: Pass 2A (Design Spec), 2B (UI Spec), 2C (Roadmap), 2D (Mockup), 2E (Multi-brand). 5 findings docs, 1402 dòng tổng.
**Status**: This is the **final research deliverable**. After Chairman approves Q-decisions below, em chuyển sang Pass 3 implementation.
**Scope**: SSvid v2.0.0 ship (VidCombo v2.1.0 deferred per Pass 2E).

---

## 0. Executive summary cho Chairman (single page)

### What we know

- 3 doc CEO Kỳ (Design Spec 1322 + UI Spec 1090 + Roadmap 513 = 2925 dòng) đã đọc full + cross-ref code reality.
- 1 mockup ảnh đã pixel-audit, 1 P0 + 6 P1 + 5 P2 issues cataloged.
- Codebase rất phong phú: BrandConfig 805 dòng multi-brand-aware, AppColors 320 dòng + ~120 tokens, AppTypography 327 dòng + Mission Briefing palette, PlaybackQueueService 263 dòng (F3 80% sẵn sàng).

### Critical findings (high-impact)

1. **Phantom Inter font silent bug** — pubspec fonts section commented; SSvid Windows/Linux render system fallback. Fix ở Phase 0 (1d).
2. **Schema rename v15→v16 → v18→v19** — 6 vị trí spec/roadmap cần sync. CTO autonomous fix.
3. **Mockup Tab 2 = "Hàng đợi tải" violates spec** = "Playlist của tôi". Implementation theo spec.
4. **F3 player queue 80% sẵn sàng** — saving 0.5d on Phase §10.
5. **Multi-brand HYBRID strategy chosen**: SSvid v2.0 first, VidCombo v2.1 +1 cycle.

### Realistic timeline

| Mode | Effort | Calendar |
|---|---:|---|
| Single dev | 36-37d | ~7-7.5 tuần |
| **2-dev parallel (recommended)** | **25-28d** | **~5 tuần** |
| 3-dev parallel | 22-24d | ~4-4.5 tuần |

### Decisions still pending Chairman

8 questions outstanding (xem §11). Em recommend default per câu — Chairman có thể veto từng cái riêng lẻ.

### Ship sequence (target dates assume start 2026-05-12)

| Milestone | Target |
|---|---|
| V2 dev start (after Chairman approve Q-list) | 2026-05-12 |
| SSvid v2.0.0 internal alpha (after Phase 1A+§5) | 2026-05-26 (week 2) |
| SSvid v2.0.0 internal beta (after 1B+1C) | 2026-06-09 (week 4) |
| SSvid v2.0.0 closed beta (after §10) | 2026-06-23 (week 6) |
| **SSvid v2.0.0 public release** | **2026-06-30 (week 7)** |
| VidCombo v2.1.0 port start | 2026-07-07 |
| **VidCombo v2.1.0 public release** | **2026-07-21 (week 9)** |

---

## 1. Final phase plan — 9 phases (Phase 0 + 8 spec phases)

```
Phase 0  → Phase 1A → Phase §5 (overlap 1A) → Phase 1B → Phase 1C → Phase §10 → Polish → Buffer → Ship
```

| # | Phase | Effort | Branch | Ship-able |
|---|---|---:|---|---|
| 0 | Foundation | 1.5d | `feat/v2-foundation` | Internal only (no UI) |
| 1A | Smart input + preset popover + 2-tier customize + batch + Windows fallback | 6.5d | `feat/v2-smart-input` | Internal alpha (after §5 overlap) |
| §5 | FormatPreset 3-layer + EffectiveConfigResolver + 6 built-in seed | 6d | `feat/v2-preset-system` | Internal alpha |
| 1B | Manager rows 9 states + filter popover + sort | 4d | `feat/v2-download-manager-rows` | Internal beta |
| 1C | Selection + bulk (4 actions, drop "Thêm vào playlist") | 4d | `feat/v2-bulk-selection` | Internal beta |
| §10 | Playlist của tôi + F3 player + AddToPlaylistMenu | 9d | `feat/v2-user-playlists` | Closed beta |
| Polish | Dark mode + a11y + i18n 2-lang + perf + telemetry + What's New | 2.75d | `feat/v2-polish` | Pre-release |
| Buffer | QA + bug fix + multi-brand smoke + rollback test | 3d | `feat/v2-buffer` | Public release |
| **TOTAL** | **36.75d** | | | SSvid v2.0.0 |

**Plus**: VidCombo v2.1.0 port = 5.75d ≈ 1.5 weeks after SSvid v2.0 stable.

---

## 2. Phase 0 — Foundation (1.5d)

**Branch**: `feat/v2-foundation`
**Ship-able**: No (internal only, prerequisite)
**Goal**: Wire pubspec fonts, create design_tokens.dart skeleton, fix 4 missing row state tokens, set window min size.

### Files to create

| File | Purpose |
|---|---|
| `lib/core/design/design_tokens.dart` | 8 classes: AppSpacing/Radius/Shadow/Motion/IconSize/ComponentSize/Breakpoint/MinWidth |
| `lib/core/window_size.dart` | Window min size method channel wrapper |

### Files to modify

| File | Change |
|---|---|
| `pubspec.yaml` | (a) Uncomment + populate `fonts:` section bundle Inter; (b) Remove `google_fonts: ^6.3.2` dep |
| `lib/main.dart` | Remove `GoogleFonts.config.allowRuntimeFetching = false` line (no longer needed) |
| `lib/core/theme/app_colors.dart` | Add 4 row state token sets: `postProcessing` container variants (light/dark), `pending` pair, `waitingForNetwork` pair, ensure `downloading` separate from `Active` |
| `macos/Runner/MainFlutterWindow.swift` | Wire NSWindow.setContentMinSize(1024×720) at startup |
| `windows/runner/win32_window.cpp` | Wire WM_GETMINMAXINFO handler 1024×720 |
| `linux/...` | GtkWindow.set_size_request(1024, 720) — file TBD |

### Tasks

1. Pubspec fonts wire:
   ```yaml
   flutter:
     fonts:
       - family: Inter
         fonts:
           - asset: assets/fonts/InterVariable.ttf
   ```
2. Remove `google_fonts: ^6.3.2` from `dependencies:`. Search/remove all imports (`Pass 2A` confirm only `main.dart:10,48`).
3. Smoke test 3 platforms: macOS (verify Inter renders, not system fallback), Windows VM (must work — currently broken silently), Linux VM (must work).
4. Create `design_tokens.dart` 8 class. KHÔNG include `AppColors` / `AppTypography` (deferred to existing source-of-truth files per Pass 2A).
5. Add 4 row state tokens to `app_colors.dart`:
   - `lightStatusPostProcessing` + `lightStatusPostProcessingContainer`
   - `darkStatusPostProcessing` + `darkStatusPostProcessingContainer`
   - `lightStatusPending` + `lightStatusPendingContainer`
   - `darkStatusPending` + `darkStatusPendingContainer`
   - `lightStatusWaitingForNetwork` + `lightStatusWaitingForNetworkContainer`
   - `darkStatusWaitingForNetwork` + `darkStatusWaitingForNetworkContainer`
   - `statusContainer(BuildContext)` context-aware helpers for each
6. Wire window min size OS layer.

### Test plan

- Visual: Inter renders 4 weights (400/500/600/700) on 3 platforms.
- Build smoke: `fvm flutter build macos|windows|linux --dart-define=BRAND=ssvid`.
- Build smoke VidCombo too: `--dart-define=BRAND=vidcombo` — verify no regression.
- Window resize test: cannot drag below 1024×720.

### Acceptance criteria

- [ ] pubspec `fonts:` section uncommented with Inter bundle
- [ ] `google_fonts` dep removed
- [ ] `lib/core/design/design_tokens.dart` exists với 8 class skeleton
- [ ] 4 row state token sets present in `AppColors`
- [ ] Window resize blocked below 1024×720 on all 3 platforms
- [ ] No regression on existing tests (baseline 1667+ tests)

### Risks

- 🟠 macOS users currently using system Inter (14+) may see slight rendering diff after switch to bundle. Mitigation: visual diff before/after on 3 weights × cross-platform.
- 🟠 Drift schema unchanged this phase (no migration risk).

---

## 3. Phase 1A — Smart input + preset popover (6.5d)

**Branch**: `feat/v2-smart-input`
**Depends**: Phase 0 (foundation tokens, Inter bundle)
**Overlap**: Phase §5 (Track B can start parallel)
**Ship-able after merge**: Internal alpha

### Files to create (8 file + 1 hidden)

| File | Purpose |
|---|---|
| `lib/features/home/presentation/widgets/smart_input_bar.dart` | Composite |
| `lib/features/home/presentation/widgets/smart_cta_button.dart` | Adaptive label |
| `lib/features/home/presentation/widgets/customize_icon_button.dart` | ⚙️ Tier 1 |
| `lib/features/home/presentation/widgets/preset_dropdown_button.dart` | Trigger |
| `lib/features/home/presentation/widgets/preset_popover.dart` | Popover (stub for §5 wire) |
| `lib/features/home/presentation/providers/smart_input_provider.dart` | State + 500ms debounce |
| `lib/features/home/presentation/providers/customize_preferences_provider.dart` | Tier 2 toggle |
| `lib/features/home/domain/services/url_classifier_service.dart` | URL → InputType |
| `lib/core/feature_flags.dart` (NEW PER PASS 2E) | `homeV2Enabled` brand-conditional |

### Files to modify

| File | Change |
|---|---|
| `lib/features/home/presentation/screens/home_screen.dart` | Replace top section with `SmartInputBar` (gated by `FeatureFlags.homeV2Enabled`) |
| `lib/features/home/presentation/screens/home_download_mixin.dart` | Refactor `handleDownloadDecision` Rule chain (Rule 4 → 1 → 2 → 3' → 3) — see Pass 2B §2.4 |
| `lib/features/home/presentation/widgets/home_screen_banners.dart` | Refactor free-tier banner to use `BrandConfig.current.freeDailyDownloads` (not hardcoded "15"). **Per Pass 2E §4.2 multi-brand audit** |
| `lib/core/config/brand_config.dart` | Add `int get freeDailyDownloads` getter (SSvid: 15, VidCombo: 10) |
| `assets/translations/{vi,en}.json` | New keys: `home.cta.*`, `home.preset.*` (2 lang only — Q8 default) |

### Hidden tasks (Pass 2A + 2D + 2E findings)

- ⚠️ Verify `assets/fonts/InterVariable.ttf` actually loads (Phase 0 verified)
- ⚠️ Mockup-flagged Customize ⚙️ icon MUST be present (Pass 2D P1)
- ⚠️ Free-tier banner copy: `BrandConfig` getter, no literal (Pass 2E)

### Tasks (17 from roadmap + 3 from finding passes)

[Same as Roadmap §1A tasks 1-17, plus:]
- 18: Add `int get freeDailyDownloads` to `BrandConfig` (SSvid 15, VidCombo 10)
- 19: Refactor home_screen_banners.dart to use the getter
- 20: Verify mockup's missing ⚙️ icon present in `SmartInputBar`

### Test plan

- Unit: `UrlClassifierService` 20+ URLs covering 7 InputType cases
- Unit: `SmartInputProvider` debounce 500ms verified
- Widget: `SmartInputBar` renders all 5 controls (history/batch/⚙️/preset/CTA)
- Widget: `SmartCTAButton` label per state
- Widget: free-tier banner shows 15 (SSvid) / 10 (VidCombo) per BrandConfig
- Manual: paste 5 URL types, verify CTA + dialog routing
- Multi-brand build: `--dart-define=BRAND=vidcombo` build OK no errors

### Acceptance criteria (extends Roadmap §1A criteria)

- [ ] All 7 InputType cases produce correct CTA label
- [ ] Multi-URL parse matches §4.1
- [ ] Debounce 500ms verified
- [ ] Preset popover opens/closes smoothly (UI only, §5 wires data layer)
- [ ] ⚙️ Customize icon visible when input type ∈ {singleVideo, multipleUrls, playlist}
- [ ] Tier 2 toggle persistence + `*` indicator on dropdown label
- [ ] Active preset deleted → fallback to `auto` + clear currentConfig + toast
- [ ] Free-tier banner uses `BrandConfig.freeDailyDownloads` (verify 15 vs 10)
- [ ] FeatureFlag.homeV2Enabled brand-conditional (SSvid default false during dev)

### Risks (consolidated)

- 🟠 home_screen.dart refactor coupling (mitigated by feature flag — keep v1 path alive)
- 🟠 Preset popover stub — §5 must overlap and ship before public release
- 🔴 **Hardcoded copy regression risk** — must lint check no "15" / "10" literals in V2 widgets

---

## 4. Phase §5 — FormatPreset 3-layer (6d)

**Branch**: `feat/v2-preset-system`
**Depends**: None (overlap 1A — Track B)
**Ship-able after merge**: Combine with 1A for alpha

[Same as Roadmap §5 — em không repeat. See Roadmap §5 + Pass 2B §2.1-2.4 for code mapping.]

**Critical addition**: Adopt §17.2 migration template from spec — Pass 2B confirmed ready-to-use.

---

## 5. Phase 1B — Manager rows 9 states (4d)

**Branch**: `feat/v2-download-manager-rows`
**Depends**: Phase 0 (4 row state tokens), Phase 1A (feature flag)
**Ship-able after merge**: Internal beta

[Same as Roadmap §1B. Plus i18n `"Đã hoàn thành" → "Đã tải"` per Pass 2D P1 — vi/en only, NOT 5 lang.]

---

## 6. Phase 1C — Selection + bulk (4d, dropped from 4-5d)

**Branch**: `feat/v2-bulk-selection`
**Depends**: Phase 1B (rows render)
**Ship-able**: Internal beta

**Pass 2C decision**: Drop "Thêm vào playlist" action from v1 ship (cleaner UX vs §10 stub). Final 4 bulk actions: **Phát / Xoá / Khác / Huỷ**.

[Otherwise same as Roadmap §1C.]

---

## 7. Phase §10 — Playlist của tôi + F3 player (9d)

**Branch**: `feat/v2-user-playlists`
**Depends**: 1B + 1C (UI surface for tab + bulk)
**Ship-able**: Closed beta

### CRITICAL: Schema rename v15→v16 → v18→v19

| Reference | Old text | New text |
|---|---|---|
| Migration file | `lib/core/database/migrations/v16_user_playlists.dart` | `lib/core/database/migrations/v19_user_playlists.dart` |
| Roadmap §10.1 | "Drift v16" / "v15→v16" | "Drift v19" / "v18→v19" |
| UI Spec §10.1 caption | "Database schema (Drift v16)" | "Database schema (Drift v19)" |
| UI Spec §17.1 step 1 | "DB migration v15 → v16" | "DB migration v18 → v19" |
| Roadmap risk register row 2 | "v16 conflicts v15 work" | DELETE (obsolete) — replace with "v19 idempotency vs v18 user data" |
| `app_database.dart` | `int get schemaVersion => 18` | `int get schemaVersion => 19` |

### Sub-phase breakdown (Pass 2C estimates)

| Sub-phase | Effort | Notes |
|---|---:|---|
| §10.1 DB + Domain (DAO + freezed entities) | 1.5d | rename v19 |
| §10.2 Repository + 6 use cases | 1d | |
| §10.3 Tab + List UI | 2d | |
| §10.4 Detail screen (drag reorder) | 1.5d | |
| §10.5 Dialogs (4) | 1d | |
| §10.6 Player integration F3 (cut from 2d) | 1.5d | PlaybackQueueService 80% ready |
| §10.7 Bulk action wiring (skip if 1C drop) | 0d | Em recommend skip — VS 1C drop "Thêm vào playlist" |
| §10.8 Tests | 1.5d | |
| **Total** | **9d** | (saved 1d from spec 10d) |

### Wait — if §10.7 skipped because 1C dropped action, when does "Thêm vào playlist" ship?

→ Em propose: ship "Thêm vào playlist" trong **§10.5 (Dialogs)** sub-phase, scope addition cost ~0.25d. So §10.5 → 1.25d. New total still 9d.

→ Or **alternative**: ship "Thêm vào playlist" sau §10 done, in a separate small follow-up PR before public release. Cleaner.

→ **CTO autonomous decision**: ship in §10.5 dialogs sub-phase (one PR, complete feature).

---

## 8. Polish phase (2.75d)

**Branch**: `feat/v2-polish`
**Depends**: All above

| Task | Effort | Note |
|---|---:|---|
| 1 Dark mode tokens applied to all V2 widgets | 0.5d | BrandConfig.darkColorScheme exists |
| 2 WCAG AA contrast verify (SSvid only this cycle) | 0.5d | |
| 3 Reduced motion respect (MediaQuery.disableAnimations) | 0.5d | |
| 4 i18n complete vi/en (~30 new keys × 2 = 60 strings) | 0.5d | **Cut from 5 lang per Q8** |
| 5 Performance (virtualization + 3 indexes + debounce verify) | 0.5d | |
| 6 Telemetry events §18 (10 events) | 0.5d | |
| 7 "What's new" dialog v2.0 first launch | 0.25d | |
| **Total** | **3.25d → 2.75d cut to 2-lang** | |

---

## 9. Buffer phase (3d)

**Branch**: `feat/v2-buffer`
**Depends**: Polish

| Activity | Effort |
|---|---:|
| Manual QA against `docs/qa_checklist.md` updated for v2 | 1d |
| Internal dogfooding | 1d |
| Bug triage + fix | 0.5d |
| Release notes draft | 0.25d |
| Migration smoke test (v1.x DB → v2 startup) | 0.25d |
| **Hidden** Multi-brand smoke test (SSvid V2 + VidCombo v1.x verify FF) | 0.5d (within 1d QA) |
| **Hidden** Rollback test (v2.0 user data → v1.x app) | 0.5d (within 1d QA) |
| **Total** | **3d** ✅ |

---

## 10. Cross-cutting concerns (apply across all phases)

### 10.1 Token migration discipline

- ❌ KHÔNG hardcode hex (`#8D021F`, `#0B63F6`)
- ❌ KHÔNG hardcode spacing (`EdgeInsets.all(16)`)
- ❌ KHÔNG hardcode font (`fontFamily: 'Inter'`)
- ❌ KHÔNG hardcode quota literal (`"15 lượt"` / `"10 lượt"`)
- ✅ DÙNG `AppColors.brand`, `AppSpacing.lg`, `AppTypography.fileName`, `BrandConfig.current.freeDailyDownloads`

### 10.2 Multi-brand discipline

- Mọi widget V2 verify build cả 2 brand: `--dart-define=BRAND=ssvid|vidcombo`
- CI gate Phase 0 + Buffer: dual build smoke test
- VidCombo continues v1.x home until v2.1 (feature flag default false)

### 10.3 Schema rename discipline

- Single commit rename ALL 6 places (CHANGELOG entry)
- v18 → v19 forward-compat: existing rollback path tested

### 10.4 Feature flag rollout

```dart
// lib/core/feature_flags.dart
class FeatureFlags {
  // SSvid: alpha → beta → public flips this default
  // VidCombo: stays false until v2.1 cycle
  static bool get homeV2Enabled {
    if (BrandConfig.current.brand == Brand.vidcombo) return false;
    return _kSSvidV2Default; // toggled at each rollout milestone
  }

  static bool get playlistContextEnabled {
    if (BrandConfig.current.brand == Brand.vidcombo) return false;
    return homeV2Enabled && _kPlaylistFlag;
  }
}
```

### 10.5 Performance budget

- Animation: ≤200ms transitions
- Frame: <16ms render
- Smart input debounce: 500ms
- Search debounce: 300ms
- DB indexes added: `Downloads(addedAt)`, `Downloads(status)`, `UserPlaylistItems(position)`

---

## 11. Decisions still pending Chairman (cumulative Q1-Q14)

### Resolved CTO-autonomous (no Chairman needed)

| ID | Resolution |
|---|---|
| Q7 | Schema rename v15→v16 → v18→v19 — APPLIED |
| Q9 | F3 estimate 1.5d (was 2d) — APPLIED |
| Q10 | Rollback test added to Buffer — APPLIED |
| Q11 | 2-dev parallel recommended — em chọn (Chairman có thể veto) |
| Q12 | Phase 1C drop "Thêm vào playlist" stub, ship in §10.5 dialogs — APPLIED |
| Q13 | Multi-brand HYBRID strategy — APPLIED |
| Phase 0 injection | 1.5d new prerequisite phase — APPLIED |

### Chairman + anh Kỳ MUST decide before Phase 1A starts

| Q | Decision needed | Em recommend |
|---|---|---|
| **Q1** | Spec §2.1/§2.2/§2.4 Tailwind blue tables — DELETE or keep as deprecated reference? | Delete (cleaner) |
| **Q2** | Spec §3.2 Type scale (display.xl 32) vs code Material 3 (displayLarge 48) — align which? | Code wins (spec §3.0 already say "use existing classes") |
| **Q3** | VidCombo font — keep DM Sans hay unify Inter? | Keep DM Sans (brand differentiation) |
| **Q4** | SSvid V2 default theme = dark hay light? | Keep dark default (Nocturne) |
| **Q5** | Card radius: spec 8px default vs SSvid 3px Nocturne | Brand wins (3px for SSvid brand-defining components) |
| **Q6** | Mission Briefing + Home Dark Operator tokens — preserve hay refactor? | Preserve (35+69 call sites pre-existing investment) |
| **Q8** | i18n: 5 lang spec vs 2 lang reality | Cut to 2 (vi/en) for V2 ship; ja/pt/es defer to v2.1 |
| **Q14** | Timeline acceptance: spec 28.5-31.5d vs realistic 36-37d single-dev | Accept truth (or run 2-dev parallel for 25-28d) |

→ **8 Q for Chairman**. Q1-Q6 cần anh Kỳ confirm (REQUIREMENT layer). Q8 + Q14 anh Mỹ quyết.

---

## 12. Risk register consolidated

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|:-:|:-:|---|
| R1 | §5 backward-compat breaks existing FormatPreset records | M | H | §17.2 migration template; backward-compat JSON parse tests |
| R2 | v19 migration vs running v18 user data — idempotency & reversibility | L | H | Drift `forTestWithExecutor` simulate corrupted v18 state; reversible smoke test |
| R3 | Player queue refactor breaks single-track playback | M | H | `playlistContextEnabled` flag; PlayerNotifier additive only |
| R4 | i18n overflow (vi/en strings longer than English) | M | L | `Flexible`/`maxLines` constraints in widgets; build-time key existence check |
| R5 | Performance regression with 1000+ items | M | M | ListView.builder verified; profiling before merge |
| R6 | Per-platform pref auto-save flow breaks | L | H | Rule 2 untouched per spec §5.6; integration test |
| R7 | **VidCombo regression during SSvid V2 dev** (shared core code) | M | H | CI dual-brand build gate each PR |
| R8 | **Hardcoded copy strings leak SSvid context** | H | M | Lint rule no "15"/"10" literal; audit Phase 1A end |
| R9 | **Phantom Inter silent regression on macOS** (system → bundle metric diff) | M | L | Visual diff before/after on 3 weights × 3 platforms |
| R10 | **Spec/code v15→v19 grep confusion** | M | L | Single commit rename ALL 6 places + CHANGELOG |
| R11 | **EffectiveConfigResolver merge edge cases** (15-field) | M | M | Dedicated unit matrix ≥30 cases; ship as separate PR |
| R12 | **VidCombo light-mode V2 layout breaks** (V2 designed dark-first) | M | M | Deferred to v2.1 audit pass |
| R13 | **VidCombo cardRadius 12px frosted vs spec 8px** visual clash | L | L | Use `BrandConfig.current.cardRadius` not literal; v2.1 visual review |
| R14 | DM Sans bundle deferred — VidCombo current also phantom | L | L | Existing behavior unchanged; v2.1 cycle fix both |

---

## 13. Test strategy

### 13.1 Unit tests
- `UrlClassifierService`: 20+ URLs × 7 InputType
- `SmartInputProvider`: debounce timing
- `EffectiveConfigResolver`: ≥30 matrix cases
- `FormatPreset.fromJson`: backward-compat (legacy 7-field, missing fields, extra fields)
- `BuiltinPresetsSeeder`: idempotency
- `UserPlaylistDao`: CRUD scenarios
- `PlaybackQueueService` extension: `playlistContext` field behavior

### 13.2 Widget tests
- `SmartInputBar`: render + state transitions
- `SmartCTAButton`: label per InputType
- `PresetPopover`: select preset, tweak field, modified badge, Tier 2 toggle
- `DownloadRow`: 9 state variants
- `SelectionToolbar`: 4 actions visibility (no "Thêm playlist" v1)
- `PlaylistTab`: empty state, list state
- `AddToPlaylistMenu`: bulk action flow

### 13.3 Integration tests
- Smart input → URL → CTA → download (Rule 1 / 2 / 3 / 3' / 4)
- Bulk delete: confirm → DB + filesystem + UI update
- Playlist add → playlist play → next/previous
- v18 → v19 migration: existing data + new tables
- v2 → v1 rollback: data preservation, no crash

### 13.4 Multi-brand smoke (Buffer phase)
- SSvid build with `homeV2Enabled = true`
- VidCombo build with `homeV2Enabled = false` — verify v1.x home unchanged

### 13.5 Cross-platform (Buffer phase)
- macOS: install + extract + download + playlist (3 features end-to-end)
- Windows: same + verify Inter renders + browser URL launcher fallback
- Linux: same

---

## 14. Definition of Done — per phase

[Same as Roadmap §504-513 plus Pass 2C additions]:

- [ ] All listed files created/modified
- [ ] `fvm flutter test` pass (delta tests + baseline 1667+)
- [ ] `fvm flutter analyze --no-pub` 0 issues (output says "snakeloader")
- [ ] Manual QA on macOS + Windows + Linux
- [ ] Translation keys complete vi/en (cut from 5 langs per Q8)
- [ ] **Multi-brand build smoke**: `--dart-define=BRAND=vidcombo` builds OK
- [ ] PR reviewed by ≥1 person
- [ ] Acceptance criteria verified by QA
- [ ] Documentation updated if user-facing change
- [ ] Feature flag default verified per phase milestone

---

## 15. Mockup gap closure (Pass 2D)

| Gap | Phase | Resolution |
|---|---|---|
| P0 Tab 2 = "Hàng đợi tải" → "Playlist của tôi" | §10 | Tab built per spec |
| P1 Customize ⚙️ icon missing | 1A | Built per spec |
| P1 Preset popover ~40% incomplete | 1A + §5 | Full popover per spec §5.2 |
| P1 "Đã hoàn thành" → "Đã tải" | 1B | i18n update vi/en |
| P1 Audio row "MP4 320kbps" → "MP3 320kbps" | 1B | Use correct format string for audio variant |
| P1 Brand color blue → Wine Red | All | Use `AppColors.brand` runtime, never literal |
| P1 Bắt đầu nhanh dismiss button | 1A | Add `[X]` |
| P2 Tip card visible | 1A | Keep visible (override spec §6 hidden-default) |
| P2 Icon labels (History/Batch) below | 1A | Keep labels (better discoverability) |

---

## 16. Rollback plan

### 16.1 SSvid v2.0 → v1.x rollback paths

| Trigger | Action | Mechanism |
|---|---|---|
| Feature flag remote toggle (backend) | `homeV2Enabled` server-side flip → next app launch shows v1.x home | Backend flag + 5-min cache bust |
| Local user opt-out | Settings toggle "Use classic home" → restart | SharedPreferences local override |
| Critical bug emergency | Hotfix release v2.0.1 with `_kSSvidV2Default = false` | Standard release |
| DB rollback | v19 → v18 user (downgrade) | Spec §17.3 backward-compat: v1.x ignores unknown JSON fields, v19 tables tồn tại nhưng v1.x không touch — safe |

### 16.2 VidCombo (always v1.x during SSvid v2.0 cycle)

- Feature flag `homeV2Enabled` brand-conditional default `false`
- Even if shared core code regresses, VidCombo never sees V2 code path
- Risk: shared core widget regression — mitigated by CI dual-brand build smoke

---

## 17. Next steps after this turn

### Immediate (CTO autonomous, no Chairman block)

1. ✅ Em đã 5 findings doc + 1 hyper-plan committed branch `v2/home-redesign-foundation`
2. ⏳ Em chờ Chairman duyệt 8 Q còn lại
3. ⏳ Anh Kỳ confirm Q1-Q6 (token decisions, REQUIREMENT layer)

### After Chairman + anh Kỳ approve

1. Em apply Q decisions → update spec/code/findings nếu Chairman vetỏ
2. Em start Pass 3 implementation Phase 0 (1.5d)
3. Phase 0 done → start Phase 1A + §5 parallel (if 2-dev) or serial (if 1-dev)
4. Each phase ship as separate PR with feature flag gate
5. After Phase §10 ships → SSvid v2.0.0 closed beta
6. After Polish + Buffer → SSvid v2.0.0 public release
7. +1 cycle (VidCombo port 5.75d) → VidCombo v2.1.0 public release

### What em WILL NOT do without explicit Chairman go

- Push branch `v2/home-redesign-foundation` to any remote (per CLAUDE.md no commit/push without request)
- Start Pass 3 implementation
- Modify any `.dart` / `.rs` / `pubspec.yaml` file
- Apply Q1-Q6 spec changes (REQUIREMENT layer — anh Kỳ owns)
- Run any release/dispatch workflow

---

## 18. Status sau Pass 2F

| ✓ | Hoàn thành |
|---|---|
| ✅ | Consolidated 5 findings (Pass 2A-2E, 1402 dòng) into 1 executable hyper-plan |
| ✅ | 9 phases mapped (Phase 0 + 8 spec phases) |
| ✅ | File-by-file delta inventory |
| ✅ | 14 risk register rows |
| ✅ | Test strategy 5-tier (unit/widget/integration/multi-brand/cross-platform) |
| ✅ | Feature flag rollout pattern coded |
| ✅ | Rollback paths documented |
| ✅ | Definition of Done extended |
| ✅ | Mockup P0/P1/P2 gap closure mapped to phases |
| ✅ | Cumulative 14 Q tracked (7 CTO-autonomous resolved, 8 Chairman pending) |
| ✅ | Realistic 36-37d (1 dev) / 25-28d (2 dev) timeline |
| ✅ | Ship sequence with target dates |

| ⏳ | Wait Chairman |
|---|---|
| ⏳ | Q1-Q6 anh Kỳ approval (escalate via Chairman) |
| ⏳ | Q8 i18n 2-lang confirm |
| ⏳ | Q11 parallelism choice |
| ⏳ | Q14 timeline acceptance |
| ⏳ | Pass 3 implementation start authorization |
