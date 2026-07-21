# Pass 03C — Usage Report (Independent Verification)

**Generated**: 2026-05-06 by direct codebase probe.
**Purpose**: Lock authoritative numbers before Step 3 implementation. Reviewer 2 caught 2 round of count errors in earlier manifest — this report is the truth source.
**Method**: Rigorous grep audit with proper canonical-line detection (multi-line getter aware).

---

## 1. missionBriefing usage — final verdict

**Audit rule applied** (per Reviewer 2):
- `getter_outside` = call sites of `missionBriefingX` getter outside `app_localizations.dart` (using word-boundary regex)
- `al_raw_total` = total occurrences of raw key `'missionBriefing.x'` in `app_localizations.dart` (multi-line getter aware)
- `raw_outside` = raw key occurrences in `lib/` outside `app_localizations.dart`
- **USED-direct**: `getter_outside > 0 OR raw_outside > 0`
- **USED-fallback**: `al_raw_total > 1` (raw key appears more than just canonical forwarding line) AND not direct
- **DEAD**: all 0

### 1.1 Final per-key verdict

| key | getOut | rawAlTotal | rawOut | verdict | sample |
|---|---:|---:|---:|---|---|
| abort | 1 | 1 | 0 | USED-direct | `AppLocalizations.missionBriefingAbort,` |
| arsenal | 1 | 1 | 0 | USED-direct | `AppLocalizations.missionBriefingArsenal,` |
| audioQuality | 0 | 1 | 0 | **DEAD** | — |
| chapters | 0 | 1 | 0 | **DEAD** | — |
| console | 1 | 1 | 0 | USED-direct | `AppLocalizations.missionBriefingConsole,` |
| desc4K | 1 | 1 | 0 | USED-direct | `if (h >= 2160) return AppLocalizations.missionBriefingDesc4K;` |
| descAudio | 2 | 1 | 0 | USED-direct | `return AppLocalizations.missionBriefingDescAudio;` |
| descFHD | 1 | 1 | 0 | USED-direct | (h >= 1080) |
| descHD | 1 | 1 | 0 | USED-direct | (h >= 720) |
| descQHD | 1 | 1 | 0 | USED-direct | (h >= 1440) |
| descSD | 1 | 1 | 0 | USED-direct | descSD return |
| descSubtitle | 2 | 1 | 0 | USED-direct | parts list |
| descVideoOnly | 1 | 1 | 0 | USED-direct | descVideoOnly return |
| extras | 0 | 1 | 0 | **DEAD** | — |
| format | 0 | 1 | 0 | **DEAD** | — |
| initialize | 3 | 1 | 0 | USED-direct | initialize return × 3 |
| platform | 0 | 1 | 0 | **DEAD** | — |
| **rememberChoice** | 0 | **2** | 0 | **USED-fallback** | line 634: `if (platform.isEmpty) return 'missionBriefing.rememberChoice'.tr();` (fallback path inside `missionBriefingRememberChoiceFor` function) |
| rememberChoiceFor | 1 | 1 | 0 | USED-direct | label call |
| sponsorBlock | 0 | 1 | 0 | **DEAD** | — |
| subtitles | 0 | 1 | 0 | **DEAD** | — |
| targetIntel | 0 | 1 | 0 | **DEAD** | — |
| timeRange | 0 | 1 | 0 | **DEAD** | — |
| title | 1 | 1 | 0 | USED-direct | dialog title |
| videoOnly | 1 | 1 | 0 | USED-direct | videoOnly title |
| videoQuality | 0 | 1 | 0 | **DEAD** | — |

### 1.2 Final counts

- **USED-direct**: 15 keys → `abort, arsenal, console, desc4K, descAudio, descFHD, descHD, descQHD, descSD, descSubtitle, descVideoOnly, initialize, rememberChoiceFor, title, videoOnly`
- **USED-fallback**: 1 key → `rememberChoice` (reachable via `missionBriefingRememberChoiceFor` when `platform == ""`)
- **DEAD**: 10 keys → `audioQuality, chapters, extras, format, platform, sponsorBlock, subtitles, targetIntel, timeRange, videoQuality`

→ **16 USED / 10 DEAD / 26 total**. Matches Reviewer 2's count.

### 1.3 Drop list (Checkpoint A action)

10 keys safe to drop entirely:
1. `missionBriefing.audioQuality` — JSON entry × 15 locale + getter
2. `missionBriefing.chapters` — same
3. `missionBriefing.extras` — same
4. `missionBriefing.format` — same
5. `missionBriefing.platform` — same
6. `missionBriefing.sponsorBlock` — same
7. `missionBriefing.subtitles` — same
8. `missionBriefing.targetIntel` — same
9. `missionBriefing.timeRange` — same
10. `missionBriefing.videoQuality` — same

Net JSON cell removal: **10 keys × 15 locale = 150 cells removed**. Plus 10 getter declarations removed from `app_localizations.dart`. Cleanup gain.

### 1.4 Keep + rename list (16 keys → downloadOptions namespace)

| Old key | New key | Why this rename |
|---|---|---|
| `missionBriefing.abort` | `downloadOptions.cancel` | "Abort" military → "Cancel" everyday |
| `missionBriefing.arsenal` | `downloadOptions.quality` | "Arsenal" military → section title "Quality" |
| `missionBriefing.console` | `downloadOptions.settings` | "Console" enterprise → "Settings" |
| `missionBriefing.desc4K` | `downloadOptions.desc4K` | Keep — descriptor for resolution |
| `missionBriefing.descAudio` | `downloadOptions.descAudio` | Keep |
| `missionBriefing.descFHD` | `downloadOptions.descFHD` | Keep |
| `missionBriefing.descHD` | `downloadOptions.descHD` | Keep |
| `missionBriefing.descQHD` | `downloadOptions.descQHD` | Keep |
| `missionBriefing.descSD` | `downloadOptions.descSD` | Keep |
| `missionBriefing.descSubtitle` | `downloadOptions.descSubtitle` | Keep |
| `missionBriefing.descVideoOnly` | `downloadOptions.descVideoOnly` | Keep |
| `missionBriefing.initialize` | `downloadOptions.start` | "Initialize Download" engineer → "Start" / "Tải" |
| `missionBriefing.rememberChoice` | `downloadOptions.rememberChoice` | Keep — fallback path |
| `missionBriefing.rememberChoiceFor` | `downloadOptions.rememberChoiceFor` | Keep |
| `missionBriefing.title` | `downloadOptions.title` | "MISSION BRIEFING" → "Download Options" |
| `missionBriefing.videoOnly` | `downloadOptions.videoOnly` | Keep |

→ 16 getter rename in `app_localizations.dart` + 16 key rename × 15 locale = 240 atomic cell rename. Plus call site rename in 3 file: `download_config_dialog.dart`, `config_quality_panel.dart`, `config_preferences_panel.dart`.

---

## 2. Home-related key count (post-recent-commits)

| Namespace | Keys |
|---|---:|
| home | 126 |
| homeBatchDownload | 8 |
| downloads | 47 |
| downloadStatus | 8 |
| downloadFilter | 3 |
| downloadsView | 4 |
| batchOps | 20 |
| duplicateDownload | 7 |
| qualityFallback | 6 |
| streamSelection | 11 |
| csvExport | 5 |
| contextMenu | 24 |
| errorFeedback | 35 |
| common | 18 |
| configDialog | 38 |
| qualityDialog | 22 |
| missionBriefing | 26 |
| **TOTAL home-related** | **408** |
| TOTAL all (en.json) | 2168 |

→ 408 keys is the **scope cap for Tier 1 voice rewrite (vi + en)**. Tier 2 mechanical sweep applies subset (key rename + plural API + emoji strip) across 15 locale.

---

## 3. Hardcoded user-facing strings — current count

Grep regex: `(Text|tooltip|hintText|labelText|message|title|label|content|subtitle)\s*[:(]\s*['"][A-Za-zÀ-ỹ ]{3,}` filtered to exclude `AppLocalizations|debugPrint|TextStyle|TextField|TextSpan...`

### 3.1 Full inventory (52 hits)

| File | Line | Hardcoded string | Lang | Loại |
|---|---:|---|---|---|
| `home_download_mixin.dart` | 1713 | `'Checking premium license. Please try again in a moment.'` | EN | snackbar |
| `home_batch_download_mixin.dart` | 115 | `'Preparing ${urls.length} selected videos...'` | EN | snackbar |
| `home_batch_download_mixin.dart` | 224 | `'Starting downloads: 0/${extractionResults.length}'` | EN | snackbar |
| `home_batch_download_mixin.dart` | 409 | `'Starting downloads: $processed/${extractionResults.length}'` | EN | snackbar |
| `download_list_helpers.dart` | 420 | `'Opened: ${download.filename}'` | EN | snackbar |
| `download_list_helpers.dart` | 427 | `'Failed to open location: ${...}'` | EN | snackbar |
| `download_list_helpers.dart` | 441 | `'URL copied to clipboard'` | EN | snackbar |
| `download_list_helpers.dart` | 448 | `'Failed to copy URL: ${...}'` | EN | snackbar |
| `command_bar_preset_chip.dart` | 367 | `'WebM'` | acronym | label |
| `command_bar_preset_chip.dart` | 372 | `'MKV'` | acronym | label |
| `command_bar_preset_chip.dart` | 387 | `'FLAC'` | acronym | label |
| `smart_input_bar.dart` | 181 | `'Lịch sử tải xuống'` | VI | tooltip |
| `smart_input_bar.dart` | 187 | `'Tải hàng loạt'` | VI | tooltip |
| `smart_input_bar.dart` | 215 | `'Dán link video, playlist, kênh hoặc nhập từ khóa…'` | VI | hint |
| `smart_input_bar.dart` | 220 | `'Xoá'` | VI | tooltip |
| `right_panel_item_view.dart` | 447 | `'Đang chờ tải'` | VI | title (state pending) |
| `right_panel_item_view.dart` | 455 | `'Hủy'` | VI | button |
| `right_panel_item_view.dart` | 484 | `'Đang tải xuống · $percent%'` | VI | title (state downloading) |
| `right_panel_item_view.dart` | 494 | `'Tạm dừng'` | VI | button |
| `right_panel_item_view.dart` | 502 | `'Hủy'` | VI | button |
| `right_panel_item_view.dart` | 522 | `'Đã tạm dừng · $percent%'` | VI | title (state paused) |
| `right_panel_item_view.dart` | 523 | `'Tiếp tục để tải nốt phần còn lại.'` | VI | subtitle |
| `right_panel_item_view.dart` | 529 | `'Tiếp tục'` | VI | button |
| `right_panel_item_view.dart` | 537 | `'Hủy'` | VI | button |
| `right_panel_item_view.dart` | 557 | `'Tải xuống thất bại'` | VI | title (state failed) |
| `right_panel_item_view.dart` | 565 | `'Thử lại'` | VI | button |
| `right_panel_item_view.dart` | 573 | `'Xóa'` | VI | button |
| `right_panel_item_view.dart` | 592 | `'Đã hủy'` | VI | title (state cancelled) |
| `right_panel_item_view.dart` | 593 | `'Bạn có thể tải lại từ đầu nếu cần.'` | VI | subtitle |
| `right_panel_item_view.dart` | 598 | `'Tải lại'` | VI | button |
| `right_panel_item_view.dart` | 606 | `'Xóa'` | VI | button |
| `right_panel_item_view.dart` | 625 | `'Đang chờ mạng'` | VI | title (state waitingForNetwork) |
| `right_panel_item_view.dart` | 633 | `'Hủy'` | VI | button |
| `right_panel_item_view.dart` | 652 | `'Tệp không tìm thấy'` | VI | title (state fileMissing) |
| `right_panel_item_view.dart` | 659 | `'Tải lại'` | VI | button |
| `right_panel_item_view.dart` | 667 | `'Xóa khỏi danh sách'` | VI | button |
| `right_panel_item_view.dart` | 1215 | `'Loại tệp không hỗ trợ phát'` | VI | title (TODO(ui-wording)) |
| `right_panel_item_view.dart` | 1233 | `'Không phát được trong cửa sổ này'` | VI | title (TODO(ui-wording)) |
| `right_panel_item_view.dart` | 1240 | `'Toàn màn hình'` | VI | button |
| `right_panel_item_view.dart` | 1352 | `'Tệp ảnh không tìm thấy'` | VI | title |
| `right_panel_item_view.dart` | 1598 | `'Tốc độ'` | VI | tooltip (TODO(ui-wording)) |
| `right_panel_item_view.dart` | 1621 | `'Toàn màn hình'` | VI | tooltip (TODO(ui-wording)) |
| `download_grouped_image_card.dart` | 655 | `'URL copied to clipboard'` | EN | snackbar |
| `glassmorphism_header.dart` | 699 | `'Batch Download (multiple URLs)'` | EN | tooltip |
| `customize_icon_button.dart` | 47 | `'Tuỳ chỉnh trước khi tải'` | VI | tooltip |
| `preset_popover.dart` | 112 | `'Tạo profile mới…'` | VI | label |
| `preset_popover.dart` | 122 | `'Định dạng'` + `'MP4 (Video)'` | VI | label + value |
| `preset_popover.dart` | 123 | `'Chất lượng'` + `'1080p'` | VI | label + value |
| `preset_popover.dart` | 125 | `'Khi không có chất lượng'` | VI | label |
| `preset_popover.dart` | 129 | `'Vị trí lưu'` | VI | label |
| `preset_popover.dart` | 131 | `'Đổi'` | VI | button |
| `preset_popover.dart` | 159 | `'Mở cài đặt tải nâng cao →'` | VI | label |

### 3.2 Counts by file

| File | Hits |
|---|---:|
| right_panel_item_view.dart | 27 |
| preset_popover.dart | 8 (incl. value strings) |
| smart_input_bar.dart | 4 |
| download_list_helpers.dart | 4 |
| home_batch_download_mixin.dart | 3 |
| command_bar_preset_chip.dart | 3 (acronyms — keep) |
| download_grouped_image_card.dart | 1 |
| glassmorphism_header.dart | 1 |
| customize_icon_button.dart | 1 |
| home_download_mixin.dart | 1 |
| **TOTAL** | **52** |

### 3.3 Migration scope

- **Keep as-is (acronyms)**: 3 in `command_bar_preset_chip.dart` (WebM/MKV/FLAC are format names, technical acronyms standard).
- **Migrate to i18n**: **49 hardcoded strings**.

Plus value-side leak `'Downloads/SSvid'` in `preset_popover.dart` (separate from the 49 — fix via BrandConfig.appName resolution).

---

## 4. Brand leak verification

| File | Line | Issue | Fix |
|---|---:|---|---|
| `preset_popover.dart` | **130** | `value: 'Downloads/SSvid',` literal | Replace with `value: 'Downloads/${BrandConfig.current.appName}',` |

Verified: 1 brand leak total. No `'Downloads/VidCombo'` or other variants found. Single fix point.

---

## 5. Parity test compatibility check (plural API form)

**Question**: If we migrate `home.clearCompletedMessage` (currently flat string) to nested `{ one, other }`, does `localization_key_parity_test.dart` still pass?

**Test logic verify**:
```dart
Map<String, String> _flatten(Map<String, dynamic> source, ...) {
  // Recursively flattens nested objects.
  // value is Map → recurse with prefix.fullKey
  // else → output[fullKey] = value.toString()
}
```

**Analysis**:
- Before: `home.clearCompletedMessage` = 1 flat key
- After: `home.clearCompletedMessage.one` + `home.clearCompletedMessage.other` = 2 flat keys (parent disappears)

**Implication**:
- All 15 locale must atomically migrate to 2-key form. If any locale keeps the old 1-key form, test fails ("locale missing keys").
- Placeholder rule per `_placeholders` regex: extracts `\{[A-Za-z0-9_]+\}` literal.
- en `.one` = "Delete {count} completed download?" → placeholders = `{{count}}`
- en `.other` = "Delete {count} completed downloads?" → placeholders = `{{count}}`
- vi `.one` = "Xóa {count} mục đã hoàn thành?" → `{{count}}` ✓ matches
- vi `.other` = same → `{{count}}` ✓
- 13 locale must also have `{count}` in both `.one` AND `.other` per parity rule

**Verdict**: Parity-safe IF migration is atomic across 15 file. Mechanical sweep handles this.

**Plural API runtime**: easy_localization 3.0.7 default `ignorePluralRules = true` → only uses `.one` (count=1) and `.other` (count!=1). Few/many ignored. Sufficient for B-lite scope.

---

## 6. Other enum migration scope

### 6.1 DownloadStatus.displayLabel

User-facing call sites: 12 (verified Step 2 probe). New i18n keys needed (in `downloadStatus.*` namespace which already exists with 8 keys):
- Match exists for: pending, queued, downloading, paused, completed, failed, cancelled (7 of 8 enum values map cleanly)
- Missing in current i18n: `postProcessing`, `waitingForNetwork`
- Need add 2 new keys to `downloadStatus.*` namespace.

After migration: `displayLabel` getter returns `AppLocalizations.downloadStatusXxx` instead of hardcoded English.

### 6.2 DownloadPriority.displayLabel

Single user-facing call site. Hardcoded EN: 'High', 'Normal', 'Low'.

Need new namespace: `downloadPriority.*` with 3 keys.

After migration: `displayLabel` getter returns `AppLocalizations.downloadPriorityXxx`.

---

## 7. Plural keys migration scope

4 keys affected:
- `home.clearCompletedMessage`
- `home.cleared`
- `home.deleted`
- `home.clearFailedMessage`

For each: split into `{ one, other }` form. Apply 15 locale atomic.

**Code call site**:
- `downloads_history_screen.dart:278` — `final plural = completedCount > 1 ? 's' : '';`
- `downloads_history_screen.dart:283,293,301,328,338,346` — calls to plural getters
- `home_download_mixin.dart:1582` — similar pattern (need verify)

`app_localizations.dart` getter signature change:
- Before: `static String homeClearCompletedMessage(int count, String plural) => 'home.clearCompletedMessage'.tr(namedArgs: {'count': '$count', 'plural': plural});`
- After: `static String homeClearCompletedMessage(int count) => 'home.clearCompletedMessage'.plural(count, namedArgs: {'count': '$count'});`

---

## 8. Emoji strip scope

Search regex (mechanical sweep across 15 .json file):
- Leading emoji + space: `^✅\s|^⚡\s|^✨\s|^💾\s|^⏸\s|^▶\s|^❌\s|^⚠️\s|^📌\s`
- Mid-string emoji: rare, audit case-by-case

**Verified count of emoji-containing strings in en.json + vi.json**: TBD — em sẽ run script đầu Checkpoint A. Estimate 8-12 keys × 15 locale = 120-180 cell modify.

---

## 9. Tagline confirmation

| Key | Render surface? |
|---|---|
| `app.subtitle` | NO call site outside getter `AppLocalizations.appSubtitle` |
| `home.subtitle` | NO call site outside getter `AppLocalizations.homeSubtitle` |
| `BrandConfig.appDescription` | NO call site outside `AppConstants.appDescription` getter |
| `AppConstants.appDescription` | NO user-facing call site |

**Verdict confirmed**: Tagline = dead code at 3 layers. **DE-SCOPED** from Checkpoint A + B.

---

## 10. Final scope numbers — locked

| Item | Truth value |
|---|---|
| missionBriefing keys to keep + rename | **16** (15 direct + 1 fallback) |
| missionBriefing keys to drop | **10** |
| Home-related i18n keys total | **408** (across 17 namespaces) |
| Hardcoded user-facing strings to migrate | **49** (52 minus 3 acronym) |
| Brand leak fix points | **1** (`preset_popover.dart:130`) |
| Plural keys to migrate | **4** |
| Enum migration | **2** classes (DownloadStatus + DownloadPriority) |
| New i18n keys to add | ~14 (8 existing downloadStatus + 2 new postProcessing/waitingForNetwork + 3 priority + 1 buffer) |
| Tagline migration | **DE-SCOPED** |
| BrandConfig change | **NONE** |
| Settings dropdown change | **NONE** (B-lite keep 15 locale) |
| Locale files to touch | **15** (mechanical sweep), **2** (en + vi voice rewrite) |

---

## 11. Checkpoint A scope final

Now using locked numbers from §10:

1. **Drop 10 dead missionBriefing keys** (atomic: 10 keys × 15 .json file = 150 cell + 10 getter declarations in `app_localizations.dart`)
2. **Rename 16 keep keys**: `missionBriefing.*` → `downloadOptions.*` (atomic: 16 keys × 15 .json file = 240 cell rename + 16 getter rename in `app_localizations.dart` + call site rename in 3 file)
3. **Plural API migration** for 4 keys: split each to `{ one, other }` (atomic: 4 keys × 15 .json file = 60 cell + 2 cell sub-keys × 15 = 120 cell + getter rewrite + 2 call site rewrite in dart code)
4. **Emoji strip** mechanical sweep (estimated ~120 cell)
5. **Enum migration**: DownloadStatus + DownloadPriority → return AppLocalizations getter; add ~14 new i18n keys × 15 locale = ~210 cell
6. **Brand leak fix**: 1 line change in `preset_popover.dart:130`
7. **Verify gate**: analyze + parity test + smoke build

**Total Checkpoint A i18n cell touched**: ~150 + 240 + 120 + 120 + 210 = **~840 cells across 15 locale**.

Effort estimate (revised): **3-4h** Checkpoint A. Most automatable via Python script.

---

## 12. Checkpoint B scope final

After A passes:
1. **408 home keys vi + en hand-write rewrite** apply VOICE.md + TERMINOLOGY.md (this is the bulk of Tier 1 work)
2. **49 new keys for hardcoded migration** vi + en hand-write
3. **Title Case → sentence case sweep** vi only — estimate ~229 keys (per Pass 02 §1)
4. **emptySubtitle semantic fix** (1 key vi+en)
5. **Verify gate**: analyze + parity + smoke build SSvid + VidCombo

**Effort estimate**: **4-5h** Checkpoint B.

---

## 13. Pre-implementation prerequisites checklist

- [ ] Chairman commits or stashes 3 dirty code files: `download_list_item.dart`, `filter_chips.dart`, `home_screen_banners.dart`
- [ ] Chairman acks USAGE-REPORT (this file) + manifest patch §12
- [ ] Em chạy Checkpoint A đầu tiên, verify gate pass, commit, STOP
- [ ] Chairman manual smoke verify Checkpoint A commit
- [ ] Em chạy Checkpoint B sau ack
- [ ] Em chạy verify gate B, commit, STOP

---

**Trạng thái**: Step 2.5 + Independent verification = ✅ DONE. Numbers locked.

Trước khi vào Checkpoint A, đợi Chairman ack:
1. ✅ Authority numbers OK?
2. ✅ Checkpoint A scope §11 OK?
3. ✅ Checkpoint B scope §12 OK?
4. ✅ Commit dirty code files trước?

Anh ack 4 box → em vào Checkpoint A ngay (3-4h).
