# Svid v2 Home Redesign — Implementation Roadmap

**Version:** v1.0
**Date:** 2026-05-05
**Companion to:** [Svid_Home_Download_Manager_UI_Spec_v1.1.md](Svid_Home_Download_Manager_UI_Spec_v1.1.md)
**Total estimate:** 28.5-31.5 working days (~5-6 weeks single developer)

## Phase overview

| Phase | Name | Effort | Dependencies | Ship-able? |
|-------|------|--------|--------------|------------|
| 1A | Smart input + preset popover + 2-tier customize + batch context + Windows fallback + Inter font bundle | 6.5d | - | Internal alpha |
| §5 | FormatPreset 3-layer architecture | 5-6d | overlap 1A | - |
| 1B | Download manager rows + 9 states + filter | 4d | 1A | Internal beta |
| 1C | Selection mode + bulk actions | 4-5d | 1B | Internal beta |
| §10 | Playlist của tôi + player integration | 10d | 1B+1C | Feature complete |
| Polish | Dark mode + a11y + i18n + perf | 2-3d | All above | Pre-release |
| Buffer | QA + bug fix | 3d | All above | Release |

```
Week 1: Phase 1A + start §5
Week 2: Finish §5 + Phase 1B
Week 3: Phase 1C + start §10
Week 4: Continue §10 (player integration)
Week 5: Finish §10 + Polish
Week 6: Buffer + ship
```

---

## Phase 1A: Smart input + preset popover + button redesign

**Effort:** 6.5 days (was 6d, +0.5d for Inter font bundle per design spec v1.1)
**Branch:** `feat/v2-smart-input`
**PR title:** `feat(home): v2 smart input with adaptive CTA + preset popover + 2-tier customize`

### Goal
Redesign top action area: smart input field detects intent, primary CTA label adapts, preset popover replaces inline dropdown menu.

### Files to create

| File | Purpose |
|------|---------|
| `lib/features/home/presentation/widgets/smart_input_bar.dart` | Main composite widget |
| `lib/features/home/presentation/widgets/smart_cta_button.dart` | Primary button with adaptive label |
| `lib/features/home/presentation/widgets/customize_icon_button.dart` | ⚙️ icon — Tier 1 customization access (per v1.4 §5.6) |
| `lib/features/home/presentation/widgets/preset_dropdown_button.dart` | Trigger for preset popover |
| `lib/features/home/presentation/widgets/preset_popover.dart` | Popover content (profile selector + 4 fields + Tier 2 toggle) |
| `lib/features/home/presentation/providers/smart_input_provider.dart` | State: detected input type, debounced |
| `lib/features/home/presentation/providers/customize_preferences_provider.dart` | popoverDeepCustomize toggle (Tier 2 only after v1.4) |
| `lib/features/home/domain/services/url_classifier_service.dart` | Pure function: URL → InputType |

### Files to modify

| File | Change |
|------|--------|
| `lib/features/home/presentation/screens/home_screen.dart` | Replace existing top section with `SmartInputBar` |
| `lib/features/home/presentation/screens/home_download_mixin.dart` | Hook into `SmartInputProvider` for submit |
| `assets/translations/{vi,en,ja,pt,es}.json` | New keys: `home.cta.*`, `home.preset.*` |

### Tasks

1. Define `InputType` enum: `empty | singleVideo | playlist | channel | searchKeyword | multipleUrls | unsupportedUrl`
2. Implement `UrlClassifierService.classify(String)` → `InputType` with regex rules per §4.1
3. Create `SmartInputProvider` with 500ms debounce
4. Build `SmartCTAButton` with state machine:
   - empty → disabled
   - singleVideo/multipleUrls → "Tải xuống" / "Tải hàng loạt"
   - playlist/channel/keyword → corresponding label
   - extraction in progress → spinner + "Đang phân tích..."
5. Build `PresetDropdownButton` (label = current effective spec)
6. Build `PresetPopover` (UI only, wires to §5 state — temporary stub if §5 not ready)
7. Wire submit handler:
   - singleVideo → existing `home_download_mixin.startDownload()`
   - multipleUrls → batch dialog (placeholder)
   - playlist → `YouTubePlaylistSheet.show()`
   - channel → `YouTubeChannelSheet.show()`
   - searchKeyword → `YouTubeSearchSheet.show()`
   - unsupportedUrl → branch logic per §4.1.6
8. Build `CustomizeIconButton` (Tier 1):
   - Visible only when input type ∈ {singleVideo, multipleUrls, playlist}
   - Disabled while extracting
   - Click → `DownloadConfigDialog.show()` one-shot (config not saved)
   - Tooltip: "Tuỳ chỉnh trước khi tải"
9. Add Tier 2 toggle to `PresetPopover` footer:
   - Section "Tuỳ chọn nâng cao" with checkbox
   - Wire to `customizePreferencesProvider.popoverDeepCustomize`
   - When ON → preset dropdown label appends `*` indicator
10. Update Rule chain in `home_download_mixin.dart`:
    - Rule 4: if customize icon clicked → DownloadConfigDialog
    - Rule 3': if popoverDeepCustomize ON → DownloadConfigDialog
    - Rule 3: else → silent auto-download (default)
11. Add active preset deleted fallback (per v1.4 §5.4):
    - On `formatPresetsProvider` load: validate `activePresetId` exists in customPresets list
    - If missing → set `activePresetId = 'auto'` + clear `currentConfig` + toast info
12. Extend `DownloadConfigDialog` for batch context (per v1.3 §5.7):
    - Add params: `isBatchContext: bool`, `defaultApplyToAll: bool`
    - When `isBatchContext`: disable Section trim panel + specific quality picker
    - When `defaultApplyToAll`: init `_applyToAll = true`
    - On uncheck "Apply to all" with `remainingCount > 5`: show confirm warning
13. Wire batch flow in `home_batch_download_mixin.dart`:
    - When ⚙️ icon clicked + multi-URL detected → extract first video → open dialog with batch params
    - Apply resulting config to entire batch (reuse existing applyToAll logic)
14. Wire Tier 2 + batch interaction:
    - If `popoverDeepCustomize` ON when batch starts → first video extraction triggers dialog with `applyToAll=ON`
15. **Windows browser fallback** (per v1.5 §6.2):
    - In `popular_sites_grid.dart` (or equivalent Right column widget): detect `Platform.isWindows` on click website
    - Windows: `launchUrl(uri, mode: LaunchMode.externalApplication)` via `url_launcher` package (existing dep)
    - macOS/Linux: existing in-app browser navigation
    - Update tooltip text accordingly (per platform)
16. **Inter font bundle** ✅ DONE in design spec v1.1 commit:
    - InterVariable.ttf (v4.1, 880KB) bundled at `assets/fonts/InterVariable.ttf`
    - SIL OFL license at `assets/fonts/Inter-LICENSE.txt`
    - Registered in `pubspec.yaml` under `flutter.fonts:`
    - Remaining Phase 1A tasks:
      - Verify `Theme.of(context).textTheme` defaults to Inter via `AppTheme`
      - Test fallback: rename Inter file → ensure system font picks up gracefully
      - Visual verify: 4 weights (400/500/600/700) render correctly từ variable font
17. **Total v2 estimate update**: 28-31d → 28.5-31.5d (+0.5d Inter font)

### Test plan

- Unit: `UrlClassifierService` — 20+ test URLs covering all 7 types
- Unit: `SmartInputProvider` debounce behavior
- Widget: `SmartInputBar` render + state transitions
- Widget: `SmartCTAButton` label per state
- Manual: paste various URLs, verify CTA + dialog routing

### Acceptance criteria

- All 7 InputType cases produce correct CTA label
- Multi-URL parsing matches §4.1 (newline/whitespace/comma)
- Debounce 500ms verified
- Preset popover opens/closes smoothly
- ⚙️ Tuỳ chỉnh icon visible/disabled per state matrix (§4.1)
- Tier 1 click → DownloadConfigDialog one-shot
- Tier 2 toggle persistence + `*` indicator on dropdown label
- Active preset deleted → graceful fallback to `auto` built-in
- No regression on existing download flow

### Risks

- Existing `home_screen.dart` may be tightly coupled — refactor carefully
- Preset popover stub means §5 needs to ship before this can be production-ready
- 2 customization tiers must be coordinated with Rule chain priority (Rule 4 > Rule 2 > Rule 3' > Rule 3)

---

## Phase §5: FormatPreset 3-layer architecture

**Effort:** 6 days (was 5-6d, +0.5d for Windows browser fallback + DTO migration spec compliance per v1.5)

**Branch:** `feat/v2-preset-system`
**PR title:** `feat(settings): 3-layer preset config with built-in profiles`

### Goal
Implement `EffectiveDownloadConfigService` (3-layer resolver), extend `FormatPreset`, seed 6 built-in profiles, wire into download flow.

### Files to create

| File | Purpose |
|------|---------|
| `lib/features/settings/domain/services/effective_config_resolver.dart` | 3-layer config resolution |
| `lib/features/settings/domain/entities/format_preset_extended.dart` | Extended FormatPreset entity (freezed) |
| `lib/features/settings/data/datasources/builtin_presets_seeder.dart` | Seed 6 default profiles |
| `lib/features/settings/presentation/providers/active_preset_provider.dart` | activePresetId + currentConfig |
| `lib/core/migrations/v2_format_preset_migration.dart` | Legacy 7-field → 15-field DTO migration (per v1.5 §17.2) |

### Files to modify

| File | Change |
|------|--------|
| `lib/features/settings/data/datasources/format_presets_service.dart` | Add fields: `audioOnly`, `audioBitrate`, `fallbackBehavior`, `saveLocation`, `isBuiltIn`, optional `subtitlesEnabled`, `embedThumbnail`, `embedMetadata`, `embedChapters` |
| `lib/features/home/presentation/screens/home_download_mixin.dart` | Replace Rule 3: `DownloadConfigDialog.show()` → `EffectiveConfigResolver.resolve() + auto-download` |
| `lib/features/home/presentation/widgets/preset_popover.dart` | Wire to `activePresetProvider` |

### Tasks

1. Extend `FormatPreset` with new fields (backward-compat JSON parse)
2. Define `built_in_presets.dart` with 6 const definitions per §5.3
3. Implement `BuiltinPresetsSeeder.ensureSeeded()`:
   - Check `format_presets` SharedPref
   - If empty OR missing builtin IDs → seed
4. Implement `EffectiveConfigResolver.resolve(url, ref) → DownloadConfig`:
   - Layer 1: `PlatformQualityPreference` lookup
   - Layer 2: `currentConfig` (from `activePresetProvider`)
   - Layer 3: `SettingsState`
   - Merge with field-level priority (Layer 1 wins for any non-null field)
5. Modify Rule 3 in download mixin:
   ```dart
   // OLD:
   final config = await DownloadConfigDialog.show(...);
   // NEW:
   final config = await ref.read(effectiveConfigResolver).resolve(videoInfo.url);
   AppSnackBar.info(context,
     message: 'Đang tải với ${activePreset.name}',
     action: SnackBarAction(label: 'Tuỳ chỉnh', onPressed: () => _customizeOnce(...)),
   );
   await startDownloadWithConfig(videoInfo, config);
   ```
6. Add Rule 4 (explicit customization): keep `DownloadConfigDialog.show()` accessible via row action `⋯ → Tuỳ chỉnh cho lần này`
7. `PresetPopover` UI:
   - Profile list with ✓ on active
   - Tweak fields update `currentConfig` in provider
   - "(đã chỉnh sửa)" badge if `currentConfig != activePreset.config`
   - "+ Tạo profile mới..." → modal name input → save as FormatPreset

### Test plan

- Unit: `EffectiveConfigResolver` — matrix test (pref exists/absent × preset selection × tweaked fields)
- Unit: `FormatPreset.fromJson` backward-compat (old JSON without new fields)
- Unit: `BuiltinPresetsSeeder` — idempotency
- Widget: `PresetPopover` — select preset, tweak field, modified badge
- Integration: Rule 3 flow from URL paste to download start

### Acceptance criteria

- Per-platform pref overrides FormatPreset for matching URLs (Rule 2 unchanged)
- 6 built-in presets visible in popover with 🔒 icon
- Tweak field updates `currentConfig` in SharedPreferences immediately
- Tweak does NOT mutate the FormatPreset
- Rule 3 silent auto-download (no dialog popup)
- Snackbar with active preset name + Tuỳ chỉnh action

### Risks

- Backward-compat JSON parse for existing FormatPreset records (mitigated by v1.5 §17.2 DTO migration spec — generate UUID for legacy + skip if `schemaVersion` present)
- `EffectiveConfigResolver` field-merge logic complexity (15+ fields)
- Migration from existing `DownloadConfigDialog`-driven flow
- Forward/backward compat: v2.0 → v1.x rollback must not crash (v1.x ignores unknown JSON fields)

---

## Phase 1B: Download manager rows + 9 states + filter

**Effort:** 4 days
**Branch:** `feat/v2-download-manager-rows`
**PR title:** `feat(downloads): 9 row states + advanced filter system`

### Goal
Expand row UI to cover all 9 `DownloadStatus` values, integrate tags + watch progress, redesign filter UI as icon + popover.

### Files to create

| File | Purpose |
|------|---------|
| `lib/features/downloads/presentation/widgets/download_row.dart` | Composite row widget |
| `lib/features/downloads/presentation/widgets/download_row_states/` | One file per state (9 files) |
| `lib/features/downloads/presentation/widgets/filter_popover.dart` | Filter icon + popover content |
| `lib/features/downloads/presentation/widgets/sort_dropdown.dart` | 6 sort options |
| `lib/features/downloads/presentation/widgets/tag_chip_inline.dart` | Tag display in row |
| `lib/features/downloads/presentation/widgets/watch_progress_overlay.dart` | Thumbnail overlay |

### Files to modify

| File | Change |
|------|--------|
| `lib/features/downloads/presentation/screens/downloads_screen.dart` | Replace row rendering with `DownloadRow` |
| `lib/features/downloads/presentation/providers/filter_provider.dart` | Add `sortOrder`, `viewMode` (list/grid) |
| `lib/features/downloads/presentation/providers/filtered_downloads_provider.dart` | Wire sort logic |

### Tasks

1. Create base `DownloadRow` with shared layout (thumbnail + content + actions)
2. Implement state-specific widgets per §8.3 (9 states):
   - `CompletedRowState`, `DownloadingRowState`, `PostProcessingRowState`, `QueuedRowState`, `PendingRowState`, `PausedRowState`, `FailedRowState`, `CancelledRowState`, `WaitingForNetworkRowState`
3. Each state defines: metadata text, action icon, visual treatment, progress bar visibility
4. Update `vi.json` + 4 other lang: "Đã hoàn thành" → "Đã tải", new state labels
5. Build `FilterPopover` exposing existing filters (media type / platform / status / tags / watch state)
6. Add badge to filter icon: show count of active filters
7. Build `SortDropdown` with 6 options, wire to `filterProvider`
8. Add tag chip inline display (max 3 + "+N")
9. Add watch progress overlay (Phase 22 integration)
10. Add drag handle `≡` for queued rows (Phase 73 integration)

### Test plan

- Widget: each state renders correct metadata + actions
- Widget: progress bar only on downloading + postProcessing
- Widget: filter popover toggles filters correctly
- Widget: sort options change list order
- Manual: navigate through real downloads with mixed states

### Acceptance criteria

- All 9 states visually distinct
- Action icons consistent per §8.3 table
- Filter badge accurate
- Tag chips clickable → filter list
- Watch progress overlay accurate
- Drag handle only on queued rows

### Risks

- Tight coupling with existing `download_card.dart` may need refactor
- 9 states × test = high test surface

---

## Phase 1C: Selection mode + bulk actions

**Effort:** 4-5 days
**Branch:** `feat/v2-bulk-selection`
**PR title:** `feat(downloads): multi-select with bulk actions toolbar`

### Goal
Implement selection mode with checkbox per row, selection toolbar with 5 actions, keyboard shortcuts.

### Files to create

| File | Purpose |
|------|---------|
| `lib/features/downloads/presentation/providers/selection_provider.dart` | Selected IDs set + mode state |
| `lib/features/downloads/presentation/widgets/selection_toolbar.dart` | Bulk actions toolbar |
| `lib/features/downloads/presentation/widgets/bulk_delete_confirm_dialog.dart` | Confirm dialog with 2 options |
| `lib/features/downloads/presentation/widgets/bulk_more_menu.dart` | "⋯ Khác" overflow menu |
| `lib/features/downloads/domain/services/bulk_action_service.dart` | Execute actions on selected items |

### Files to modify

| File | Change |
|------|--------|
| `lib/features/downloads/presentation/widgets/download_row.dart` | Add checkbox visibility logic (hover / mode) |
| `lib/features/downloads/presentation/screens/downloads_screen.dart` | Toolbar swap (search/sort vs selection) |

### Tasks

1. `SelectionProvider`: track `Set<String>` of IDs, `isSelectionMode` bool
2. Checkbox in `DownloadRow`: visible if hover OR selection mode active
3. Click row in selection mode → toggle selection
4. Shift+Click → range select between last clicked + current
5. Cmd/Ctrl+A → select all visible
6. Esc → exit selection mode
7. Selection toolbar: 5 actions (Phát / Thêm vào playlist / Xoá / Khác / Huỷ)
8. Mixed-state handling: actions enabled if ≥1 valid item, skipped items show tooltip
9. `BulkDeleteConfirmDialog` with 2 radio options
10. `BulkActionService.execute()`:
    - Phát: queue to player
    - Thêm vào playlist: open `AddToPlaylistMenu` (depends on §10)
    - Xoá: confirm → delete from DB + optionally file
    - Khác: dropdown menu
11. Wire keyboard shortcuts at screen level

### Test plan

- Unit: `SelectionProvider` add/remove/toggle/clear
- Unit: `BulkActionService.execute` per action
- Widget: checkbox visibility (hover, mode)
- Widget: toolbar swap on first selection
- Widget: keyboard shortcuts (Cmd+A, Esc, Shift+Click)
- Integration: bulk delete updates DB + UI

### Acceptance criteria

- Hover row → checkbox visible
- First selection → all rows show checkbox
- Selection toolbar replaces normal toolbar
- Cmd+A selects all visible only (not filtered out)
- Esc exits + clears selection
- Bulk delete confirm with 2 options works
- Mixed-state action shows skipped count

### Risks

- Player integration for "Phát" needs `lib/features/player/` API stable
- "Thêm vào playlist" depends on §10 — stub if needed

---

## Phase §10: Playlist của tôi + player integration

**Effort:** 10 days
**Branch:** `feat/v2-user-playlists`
**PR title:** `feat(playlists): user-created playlists with player integration`

### Goal
Full implementation of internal user playlists: DB schema, domain layer, UI tab, player queue integration.

### Sub-phases

#### §10.1 DB + Domain (1.5d)
- Files: `lib/core/database/tables/user_playlists.dart`, `lib/core/database/migrations/v16_user_playlists.dart`
- **Schema check (per v1.5 review fix)**: `UserPlaylistItems.downloadId` is `IntColumn` (matches `Downloads.id` autoIncrement int). `UserPlaylists.id` is `TextColumn` UUID (portable for future export/sync).
- DAO: `UserPlaylistDao` with stream watchers
- Migration script reversible

#### §10.2 Repository + Use cases (1d)
- `UserPlaylistRepository` interface + impl
- 6 use cases per §10.2

#### §10.3 Tab + List UI (2d)
- Files: `playlist_tab.dart`, `playlist_card.dart`, `playlist_search.dart`
- Empty state per §14
- Provider: `myPlaylistsProvider` watching DB

#### §10.4 Detail screen (1.5d)
- Files: `playlist_detail_screen.dart`, `playlist_item_row.dart`
- Drag to reorder (using `flutter_reorderable_list` or similar)
- Add video flow (open downloads picker)

#### §10.5 Dialogs (1d)
- `CreatePlaylistDialog`, `RenamePlaylistDialog`, `DeletePlaylistConfirmDialog`, `AddToPlaylistMenu`

#### §10.6 Player integration (2d)
- Files: modify `lib/features/player/presentation/providers/player_providers.dart`
- Add `PlaylistContext` to `PlayerState`
- Next/Previous controls when in playlist mode
- Auto-next on item end (toggleable)
- Queue UI in player (collapsible panel)

#### §10.7 Bulk action wiring (0.5d)
- Phase 1C "Thêm vào playlist" → `AddToPlaylistMenu`

#### §10.8 Tests (1.5d)
- Unit: DAO + use cases (CRUD scenarios)
- Widget: tab, list, detail, dialogs
- Integration: bulk add → playlist → play

### Risks

- DB migration must be reversible AND coexist with existing v15 schema
- Player queue refactor may affect existing single-track playback
- Reorder drag UX complexity
- 1000-item performance (need virtualization in detail screen)

---

## Polish phase: Dark mode + a11y + i18n + perf

**Effort:** 2-3 days
**Branch:** `feat/v2-polish`

### Tasks

1. **Dark mode tokens** (§12.1) applied to all new widgets
2. **WCAG AA contrast verify** with design system tool
3. **Reduced motion** respected (`MediaQuery.disableAnimations`)
4. **Translation keys** completed for vi/en/ja/pt/es (~30 new keys)
5. **Performance**:
   - `ListView.builder` virtualization verified
   - DB indexes added: `Downloads(addedAt)`, `Downloads(status)`, `UserPlaylistItems(position)`
   - Debounce verified (search 300ms, smart input 500ms)
6. **Telemetry events** (§18) wired to existing analytics service
7. **"What's new" dialog** for v2.0 first launch

### Acceptance criteria

- All §15 acceptance items checked
- Dark mode visually verified on all screens
- 5 languages render without overflow
- Lighthouse-equivalent perf check passes (<16ms frame)

---

## Buffer phase: QA + bug fix

**Effort:** 3 days

### Activities

- Manual QA against [docs/qa_checklist.md](qa_checklist.md) updated for v2
- Internal dogfooding (1-2 days)
- Bug triage + fix
- Release notes draft
- Migration smoke test (v1.x DB → v2 startup)

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| §5 backward-compat breaks existing FormatPreset records | Medium | High | Comprehensive JSON parse tests; graceful fallback to defaults |
| §10 DB migration v16 conflicts with concurrent v15 work | Low | High | Lock branch; coordinate with mydev/production-cleanup |
| Player queue refactor breaks single-track playback | Medium | High | Feature flag `playlistContextEnabled`; rollout staged |
| Translation gaps in 5 languages cause overflow | High | Low | Build-time check for missing keys; max-width constraints |
| Performance regression with 1000+ items | Medium | Medium | Profile before merge; virtualization tests |
| Existing per-platform pref auto-save flow breaks | Low | High | Rule 2 untouched; integration test before merge |

---

## Parallel work opportunities

When multiple developers available:

- **Track A**: Phase 1A → 1B → 1C (UI/UX heavy)
- **Track B**: §5 (data/services heavy) — overlap with 1A
- **Track C**: §10 DB + Domain (independent until UI phase) — start anytime after week 1

Single developer: serial phases as outlined.

---

## Rollout strategy

1. **Internal alpha** after Phase 1A+§5: dev team only, feature flag `homeV2Enabled`
2. **Internal beta** after Phase 1B+1C: extended team, dogfooding
3. **Closed beta** after §10: invite-only, ~50 users
4. **Public release** after Polish+Buffer: feature flag flip default ON
5. **Rollback plan**: feature flag OFF reverts to v1 home screen (keep both code paths for 1 release cycle)

---

## Definition of Done (per phase)

- [ ] All listed files created/modified
- [ ] All tests pass (`flutter test`)
- [ ] `flutter analyze --no-pub` clean
- [ ] Manual QA on macOS + Windows + Linux
- [ ] Translation keys complete in 5 languages
- [ ] PR reviewed by ≥1 person
- [ ] Acceptance criteria verified by QA
- [ ] Documentation updated if user-facing change
