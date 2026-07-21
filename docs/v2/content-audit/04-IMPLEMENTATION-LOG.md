# Pass 04 — Implementation Log

**Status**: ✅ Phase 1–7 complete. Final gates pass.
**Verify gates**:
- `fvm flutter analyze --no-pub` — **No issues** (snakeloader)
- `fvm flutter test test/core/l10n/localization_key_parity_test.dart` — **PASS** (15 locale parity strict)
- `fvm flutter test test/features/downloads/domain/entities/download_status_test.dart` — **PASS** (enum migration verified)
- Full `flutter test` — 2960+ pass, 1 unrelated pre-existing failure (`window_service_test` size assertion — Chairman WIP, not 03C scope)

**Worktree state**: dirty (intentionally, parallel with Chairman's playlist + context-menu WIP). My changes layered on top, verified non-conflicting at file level.

---

## What changed

### Phase 1 — JSON migration (15 locale, atomic)

- **Mission Briefing namespace rewrite**: `missionBriefing.*` (26 keys) → `downloadOptions.*` (16 keep+rename) + 10 dead keys dropped per USAGE-REPORT verdict (15+1 used, rememberChoice via fallback).
- **Voice rewrite cho en+vi 16 keys**: "MISSION BRIEFING" → "Download Options" / "Tùy chọn tải"; "ABORT" → "Cancel" / "Hủy"; "INITIALIZE DOWNLOAD" → "Download" / "Tải"; "QUALITY ARSENAL" → "Quality" / "Chất lượng"; etc.
- **13 non-en/vi locale** giữ content cũ dưới key mới (Tier 2 mechanical — no regression, no improvement, polish v2.1).
- **Plural API migration**: 4 keys (`home.clearCompletedMessage`, `cleared`, `deleted`, `clearFailedMessage`) flat string → `{ one, other }` sub-keys. Applied 15 file atomic. en đúng plural form, vi count-neutral identical, 13 others mechanical fallback.
- **Emoji strip**: removed leading `✅⚡✨💾⏸▶❌⚠️📌` from i18n strings 15 file. AppSnackBar component already renders icon — eliminates double-icon collision per VOICE.md §8.
- **Pre-existing parity gap fix**: 60 keys en/vi had that 13 other locales didn't → filled with EN value as Tier 2 mechanical fallback. **Parity test now passes for first time**.
- **5 new keys added**: `downloadStatus.postProcessing`, `downloadStatus.waitingForNetwork`, `downloadPriority.{high,normal,low}`.

### Phase 2 — AppLocalizations getter refactor

- Renamed 16 `missionBriefingX` getters → `downloadOptionsX`.
- Dropped 10 dead `missionBriefingX` getters.
- Rewrote 4 plural getters: removed `String plural` parameter, switched to `easy_localization.plural()` API. Old API param `(int, String) → tr` replaced by `(int) → plural`.
- Added new getters: `statusPostProcessing`, `statusWaitingForNetwork`, `priorityHigh/Normal/Low`, `downloadOptions*` family.
- Plus 30+ new home/rightPanel/preset getters cho hardcoded migration.

### Phase 3 — Enum displayLabel migration

- `DownloadStatus.displayLabel` → returns `AppLocalizations.statusXxx` (was hardcoded English). Affects 12 user-facing call sites: filter chip, list item badge, grid card, browser overlay, bug report, 4 use case error messages.
- `DownloadPriority.displayLabel` → returns `AppLocalizations.priorityXxx` (was 'High'/'Normal'/'Low' hardcoded).
- Test `download_status_test.dart` updated: assertions now check non-empty + unique keys (locale-agnostic) instead of literal English.

### Phase 4 — Brand leak + call site renames

- **Brand leak fix**: `preset_popover.dart:130` `'Downloads/Svid'` → `'Downloads/${BrandConfig.current.appName}'`. VidCombo build no longer leaks "Svid" string.
- **3 missionBriefing render files** rename getter call sites:
  - `download_config_dialog.dart` (5 unique getters)
  - `config_preferences_panel.dart` (1)
  - `config_quality_panel.dart` (10)
- **Plural call sites rewrite**: removed broken `plural = count > 1 ? 's' : ''` line + getter call signature update at:
  - `downloads_history_screen.dart` (clearCompletedDialog + clearFailedDialog)
  - `home_download_mixin.dart` (showClearCompletedDialog + showClearFailedDialog)
  - **Active production bug fixed**: VI users no longer see "Xóa 5 tải xuống đã hoàn thànhs?" garbage text.

### Phase 5 — Hardcoded migration (49 strings)

Migrated 49 hardcoded user-facing strings to i18n across 9 files (3 acronym labels in `command_bar_preset_chip.dart` legitimately kept):

| File | Strings migrated |
|---|---:|
| `right_panel_item_view.dart` | 27 (state cards: pending/downloading/paused/failed/cancelled/waitingForNetwork/fileMissing + player overlay + tooltips) |
| `preset_popover.dart` | 8 (createProfile button, 4 quick-customize labels, change button, advanced settings) |
| `smart_input_bar.dart` | 4 (history/batch tooltips, URL hint, clear tooltip) |
| `download_list_helpers.dart` | 4 (open/copy URL snackbars, error variants) |
| `home_batch_download_mixin.dart` | 4 (preparing/starting batch progress messages) |
| `home_download_mixin.dart` | 1 (premium license check snackbar) |
| `download_grouped_image_card.dart` | 1 (copy URL snackbar) |
| `glassmorphism_header.dart` | 1 (batch download tooltip) |
| `customize_icon_button.dart` | 1 (customize-before-download tooltip) |

New i18n namespaces created: `rightPanel.*` (22 keys for state cards + actions + tooltips). Plus 8 home preset/snackbar/tooltip key additions.

### Phase 6 — VI Title Case → sentence case sweep

- Mechanical sweep of `vi.json`: identified Title Case multi-word values (≥70% words capitalized) and converted to sentence case per VOICE.md §7.1.
- **201 keys converted**. Sample: "Trang Phổ Biến" → "Trang phổ biến", "Mở Trình Duyệt" → "Mở trình duyệt", "Tải Xuống Gần Đây" → "Tải xuống gần đây", "Chất Lượng Tốt Nhất" → "Chất lượng tốt nhất", "Cài Đặt Thêm" → "Cài đặt thêm".
- Skipped namespaces with proper nouns: `platforms`, `app`, `mediaInfo`, `settingsBinaries`, `settingsCodecHelp`, `browser`. Acronyms preserved.
- Other 14 locales NOT swept (German nouns must stay capitalized — defer to v2.1 native review).

### Phase 7 — Voice rewrite (high-impact strategic fixes)

7 keys voice-rewritten en+vi for highest production impact:

| Key | Before | After (en) | After (vi) |
|---|---|---|---|
| `downloads.emptySubtitle` | (vi out of sync with surface) | "Paste a link above to start" | "Dán link ở trên để bắt đầu" |
| `home.subtitle` / `app.subtitle` | "powered by Rust + Flutter" | "Save video. Simple. Beautiful." | "Tải video. Đơn giản. Đẹp." |
| `home.preferenceSaveFailed` | "Failed to save platform preference" | "Could not save preference. Try again." | "Không lưu được tùy chọn. Thử lại." |
| `home.insufficientSpace` | "Not enough disk space..." | "Not enough disk space. Free up space or choose another folder." | "Không đủ dung lượng ổ đĩa. Dọn bớt hoặc đổi thư mục lưu." |
| `home.urlHint` | with trailing "..." | trimmed | trimmed |
| `streamSelection.comboHint` | "yt-dlp will merge..." (engineer leak) | "The app will merge the selected video and audio." | "App sẽ ghép video và âm thanh đã chọn." |

**Critical UX bug fixed**: `downloads.emptySubtitle` previously said "Bắt đầu tải xuống từ màn hình Trang chủ" while user was ALREADY on Home screen. Now correctly directs user to "Dán link ở trên để bắt đầu" (matching surface).

---

## Verified by automated gates

- ✅ `flutter analyze --no-pub` — 0 issues
- ✅ Locale parity test — strict 15-locale parity now enforceable
- ✅ Enum migration test — passes with new locale-agnostic contract
- ✅ Full test suite — 2960+ pass (1 pre-existing unrelated failure)
- ⚠ Smoke build Svid + VidCombo macOS — NOT YET RUN (Chairman to verify on local desktop)

---

## NOT done (defer)

Per B-lite scope discipline + manifest §8 KHÔNG ĐỘNG list:

- Voice rewrite for 13 non-en/vi locales (es, pt, de, fr, ja, ko, zh, ar, hi, id, ru, th, tr) — Tier 3 v2.1 with native reviewer.
- Plural polish for ru (one/few/many/other), ar (zero/one/two/few/many/other), de/fr/es/pt — v2.1.
- German nouns capitalization (only locale that preserves Title Case for nouns).
- Voice rewrite of 408 home keys beyond the 7 strategic ones — many strings already vastly improved by Phase 6 sentence case sweep + Phase 1 Mission Briefing rename + Phase 5 hardcoded migration. Remaining gap: per-string voice tuning of secondary surfaces.
- Settings/Browser/Player/Premium feature voice rewrite — out of home scope.
- `BrandConfig.appDescription` migration — confirmed dead code (no render surface), de-scoped.
- Settings language dropdown — kept 15 items per B-lite (no regression for existing locale users).
- Tagline rendering — `app.subtitle` + `home.subtitle` getter exist, no call site, future Pass 04+ when team wants tagline visible.

---

## Files changed by this implementation

### i18n (15 locales)
- `assets/translations/{en,vi,es,pt,ja,ar,de,fr,hi,id,ko,ru,th,tr,zh}.json` — all 15

### Dart code
- `lib/core/l10n/app_localizations.dart` — getter rename + plural API + new keys (~70 line delta)
- `lib/features/downloads/domain/entities/download_status.dart` — displayLabel migration
- `lib/features/downloads/domain/entities/download_priority.dart` — displayLabel migration
- `lib/features/downloads/presentation/widgets/download_config_dialog.dart` — getter rename
- `lib/features/downloads/presentation/widgets/config_preferences_panel.dart` — getter rename
- `lib/features/downloads/presentation/widgets/config_quality_panel.dart` — getter rename
- `lib/features/home/presentation/screens/downloads_history_screen.dart` — plural API
- `lib/features/home/presentation/screens/home_download_mixin.dart` — plural API + 1 hardcoded
- `lib/features/home/presentation/screens/home_batch_download_mixin.dart` — 4 hardcoded
- `lib/features/home/presentation/widgets/right_panel_item_view.dart` — 27 hardcoded migrate
- `lib/features/home/presentation/widgets/preset_popover.dart` — 8 hardcoded + brand leak
- `lib/features/home/presentation/widgets/smart_input_bar.dart` — 4 hardcoded + import
- `lib/features/home/presentation/widgets/customize_icon_button.dart` — 1 hardcoded + import
- `lib/features/home/presentation/widgets/glassmorphism_header.dart` — 1 hardcoded
- `lib/features/home/presentation/widgets/download_list_helpers.dart` — 4 hardcoded
- `lib/features/home/presentation/widgets/download_grouped_image_card.dart` — 1 hardcoded

### Test
- `test/features/downloads/domain/entities/download_status_test.dart` — assertion updated

### Docs
- `docs/v2/content-audit/01-SCAN-home.md`, `02-DEEPDIVE-home.md`, `03A-VOICE.md`, `03B-TERMINOLOGY.md`, `03C-MANIFEST.md`, `03C-USAGE-REPORT.md`, `04-IMPLEMENTATION-LOG.md` (this file).

**NOT touched** (Chairman's parallel WIP):
- `lib/core/database/app_database.dart`
- `lib/core/navigation/right_panel.dart`
- `lib/features/downloads/data/datasources/download_local_datasource.dart`
- `lib/features/downloads/data/repositories/download_repository_impl.dart`
- `lib/features/downloads/domain/entities/download_context_menu_action.dart`
- `lib/features/downloads/domain/repositories/download_repository.dart`
- `lib/features/downloads/domain/services/download_context_menu_service.dart`
- `lib/features/downloads/presentation/providers/{download_providers,filter_provider,filtered_downloads_provider}.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/home/presentation/widgets/{download_grid_card,download_list_item,downloads_list,filter_chips,home_screen_banners}.dart`
- `lib/features/youtube_playlist/presentation/screens/youtube_playlist_sheet.dart`
- All untracked playlist + context menu Chairman files

---

## Recommended commit boundary

Em đề xuất Chairman split commit:

**Commit 1 — "feat(home-v2): mission briefing → download options voice + plural API + i18n parity"**
- Phase 1 + 2 i18n + AppLocalizations refactor
- Phase 3 enum migration
- Phase 4 brand leak + call site rename
- All 15 locale .json files

**Commit 2 — "feat(home-v2): migrate hardcoded strings + Title Case sweep + voice fixes"**
- Phase 5 hardcoded migration (9 widget files)
- Phase 6 vi.json sentence case sweep (201 keys)
- Phase 7 voice rewrite (7 strategic keys)
- Test fix `download_status_test.dart`

**Commit 3 (separate, Chairman's choice)**: Chairman's playlist + context-menu WIP — không phải scope 03C.

---

**Em không tự commit** — anh review final state + decide commit boundary.
