# Pass 03C — IMPLEMENTATION MANIFEST

> ⚠️ **SOURCE OF TRUTH NOTICE — read first**
>
> **`03C-USAGE-REPORT.md` is the authoritative numbers source for Checkpoint A implementation.** This MANIFEST file contains historical drafts in §0–§11 with stale figures (claim "382 keys", "25 missionBriefing", "47 hardcoded", "Tier 2 tagline migration", "BrandConfig getter pattern"). These numbers WERE WRONG and have been corrected.
>
> Use these CORRECTED truths instead:
> - missionBriefing: **16 keep + rename → downloadOptions** / **10 drop** (NOT 25, NOT 14/12)
> - Home-related keys: **408** (NOT 382)
> - Hardcoded user-facing: **49** (52 grep hits − 3 acronym; NOT 47)
> - Brand leak: 1 line at `preset_popover.dart:130`
> - Plural keys: 4 → migrate to `{ one, other }` form via easy_localization plural API
> - Tagline: **DE-SCOPED** (no render surface)
> - BrandConfig: **NO CHANGE**
> - Settings dropdown: **NO CHANGE** (B-lite keeps 15 locale)
> - DownloadStatus + DownloadPriority enum migration: in scope
>
> Implementation agent / future reader: **§12 PATCH supersedes §0–§11 wherever they conflict. When in doubt, defer to USAGE-REPORT.**

---

**Strategy chốt**: **B-lite** (per Chairman + reviewer 2 alignment).
**Scope**: Áp toàn bộ V2 content fix vào codebase. KHÔNG theory, KHÔNG rewrite full 13 locale voice (defer v2.1).
**Quan hệ với 03A/03B**: Áp VOICE.md + TERMINOLOGY.md. Có drift vài chỗ phải sửa inline khi áp (xem §6).

---

## 0. Ground truth từ Step 2 reality probe — ⚠️ STALE, see USAGE-REPORT

| Probe | Kết quả | Implication |
|---|---|---|
| `main.dart:237` | 15 locale enabled (en, vi, es, pt, ja, ar, de, fr, hi, id, ko, ru, th, tr, zh) | Giữ 15 active per B-lite — không disable |
| `localization_key_parity_test.dart` | Strict: cùng key tree + cùng placeholder set across 15 locale | Mọi key change phải áp atomic 15 file |
| `_placeholders` regex | `\{[A-Za-z0-9_]+\}` extract literal placeholder | Bỏ `{plural}` phải bỏ ở cả 15 file. Plural API form `{ "one": "...", "other": "..." }` flatten thành 2 key `.one` + `.other` riêng — placeholder mỗi key phải khớp 15 locale |
| `easy_localization 3.0.7` | Default `ignorePluralRules = true` | Plural API chỉ dùng `one` + `other` branch. Few/many bị ignore. **Phù hợp với B-lite scope** — không gánh ru/ar plural polish, defer v2.1 |
| `BrandConfig.appDescription` | Render surface NULL — `AppConstants.appDescription` getter tồn tại nhưng KHÔNG có call site user-facing | **DROP khỏi must-fix.** Reviewer 2 đúng. |
| `Settings dropdown` (`settings_general_section.dart:85`) | 15 hardcoded `DropdownMenuItem` | B-lite giữ nguyên. KHÔNG đụng. |
| `DownloadStatus.displayLabel` | 12 user-facing call site (home filter chip, list item badge, grid card, browser overlay, bug report, 4 use case error msg) | **P0** — phải migrate sang i18n |
| `DownloadPriority.displayLabel` | 1 call site `download_list_item.dart:1000` user-facing | P0 — migrate cùng |
| `easy_localization plural()` API trong code | KHÔNG có usage hiện tại | Migration là first-use. Cẩn thận. |
| `v2_savedpref_to_preset_importer.dart:195` | `'📌 ${platform.displayName} (đã lưu)'` hardcode VI + emoji | OUT OF SCOPE 03C (không thuộc home). Flag cho session sau. |

---

## 1. 3-tier scope (B-lite quality boundary) — ⚠️ STALE numbers, see USAGE-REPORT

### Tier 1 — Voice rewrite vi + en (production-safe)
- 382 home-related i18n keys (vi + en hand-write theo VOICE.md + TERMINOLOGY.md)
- 25 missionBriefing keys (vi + en hand-write — namespace rename → `downloadOptions`)
- 47 hardcoded Dart strings → i18n (vi + en hand-write)
- DownloadStatus.displayLabel + DownloadPriority.displayLabel migrate i18n (vi + en)
- Tagline replacement (vi + en)
- Title Case → sentence case sweep (vi only)
- emptySubtitle semantic mismatch fix (vi + en)
- Brand leak fix (`Downloads/SSvid` → `Downloads/{appName}`)
- Plural bug fix — migrate sang plural API (vi + en hand-write)

### Tier 2 — Mechanical safety fixes (apply 13 non-vi/en locale)
- Mission Briefing namespace rename: keys renamed atomically across 15 files. **Content 13 locale giữ nguyên** (current military jargon stays — không regression, không cải thiện).
- Plural API key migration: 4 keys converted to `{ "one", "other" }` form across 15 files. **Content 13 locale: copy current template làm `other`, hand-write `.one` mechanical** (no native polish).
- Emoji strip from i18n: ✅ ✨ 💾 ⏸ ▶ ❌ removed across 15 files mechanical sweep.
- Key parity maintained across 15 files for all renamed/added keys.
- New keys added (from killing 47 hardcoded): 13 locale fill bằng EN value (fallback) — explicit `// TODO v2.1 native translate` marker không thể vì JSON, nhưng MANIFEST log lại các key này.

### Tier 3 — Deferred v2.1
- Voice rewrite cho 13 locale (es/pt/de/fr/ja/ko/zh/ar/hi/id/ru/th/tr) — full voice-aware rewrite
- Native plural polish ru (one/few/many/other), ar (zero/one/two/few/many/other), de/fr/es/pt nuance
- Per-locale capitalization rule (German nouns capitalize)
- Tagline localization adapt per locale

---

## 2. File scope — explicit list — ⚠️ STALE counts, see USAGE-REPORT

### 2.1 i18n JSON files (15 files in `assets/translations/`)

Mỗi file sẽ có 3 loại change:
- **A. Mechanical sweep** (15 file): emoji strip, key rename `missionBriefing.*` → `downloadOptions.*`, plural API migration (4 keys → `{one, other}` form), 47 new keys added (Tier 2 fallback EN value)
- **B. Voice rewrite** (chỉ en + vi): 382 home keys + 25 downloadOptions keys content rewritten

### 2.2 Dart files

| File | Change | Tier |
|---|---|---|
| `lib/core/l10n/app_localizations.dart` | Bỏ `String plural` param khỏi 4 plural getter; thêm getter mới cho DownloadStatus + DownloadPriority + new hardcoded migration keys | T1 |
| `lib/features/downloads/domain/entities/download_status.dart` | `displayLabel` thay vì hardcode → return `AppLocalizations.downloadStatusXxx` | T1 |
| `lib/features/downloads/domain/entities/download_priority.dart` | Tương tự | T1 |
| `lib/features/home/presentation/screens/downloads_history_screen.dart` | Bỏ `final plural = ... ? 's' : ''` line + đổi gọi sang plural API | T1 |
| `lib/features/home/presentation/screens/home_download_mixin.dart` | Tương tự + 1 hardcoded EN snackbar | T1 |
| `lib/features/home/presentation/screens/home_batch_download_mixin.dart` | 3 hardcoded EN status messages | T1 |
| `lib/features/home/presentation/widgets/right_panel_item_view.dart` | 18 hardcoded VI strings → i18n | T1 |
| `lib/features/home/presentation/widgets/preset_popover.dart` | 6 hardcoded VI + leak `Downloads/SSvid` | T1 |
| `lib/features/home/presentation/widgets/smart_input_bar.dart` | 4 hardcoded VI tooltips/hint | T1 |
| `lib/features/home/presentation/widgets/customize_icon_button.dart` | 1 hardcoded VI tooltip | T1 |
| `lib/features/home/presentation/widgets/download_list_helpers.dart` | 4 hardcoded EN snackbar messages | T1 |
| `lib/features/home/presentation/widgets/glassmorphism_header.dart` | 1 hardcoded EN tooltip | T1 |
| `lib/features/home/presentation/widgets/download_grouped_image_card.dart` | 3 hardcoded EN/VI mix | T1 |
| `lib/features/home/presentation/widgets/command_bar_preset_chip.dart` | 4 hardcoded format-name labels (acronym OK, kept as-is) | NO CHANGE (acronym standard) |
| `lib/core/config/brand_config.dart` | Add tagline getter pattern (return i18n key suffix, not literal). KHÔNG migrate appDescription (probe = not user-facing). | T1 |
| `lib/core/widgets/app_snack_bar.dart` | NO CHANGE — already renders icon. Just stripping emoji from i18n string. | NO CHANGE |
| `lib/main.dart` | NO CHANGE — keep 15 locale active per B-lite | NO CHANGE |
| `lib/features/settings/presentation/widgets/settings_general_section.dart` | NO CHANGE — keep dropdown 15 items per B-lite | NO CHANGE |
| `test/core/l10n/localization_key_parity_test.dart` | NO CHANGE — must keep strict parity, used as gate | NO CHANGE |

**Total Dart file edit: 13 files (excluding test).**

### 2.3 Tagline strategy

Per probe: `BrandConfig.appDescription` is dead → drop. Tagline phải qua i18n.

i18n key design:
- `app.subtitle.ssvid` — SSvid tagline
- `app.subtitle.vidcombo` — VidCombo tagline

Code resolve:
```dart
// Old: AppLocalizations.appSubtitle returns 'app.subtitle'.tr() (single key)
// New: 
static String get appSubtitle => 
    'app.subtitle.${BrandConfig.current.brand.name}'.tr();
```

i18n value (vi + en):
- `app.subtitle.ssvid.en` = "Save video. Simple. Beautiful."
- `app.subtitle.ssvid.vi` = "Tải video. Đơn giản. Đẹp."
- `app.subtitle.vidcombo.en` = "Download fast. Save clean."
- `app.subtitle.vidcombo.vi` = "Tải nhanh. Lưu sạch."

13 locale: hand-write tagline mechanical adapt (Tier 2). Tagline ngắn, ít rủi ro quality.

Then drop `app.subtitle` single key (legacy "powered by Rust + Flutter") from 15 files.

### 2.4 Tổng số i18n key change ước lượng

| Action | Số key | Locale | Total cells |
|---|---:|---:|---:|
| Voice rewrite Tier 1 | 382 | 2 | 764 |
| Mission Briefing rename + voice (T1) | 25 | 2 | 50 |
| Mission Briefing key rename only (T2) | 25 | 13 | 325 |
| Plural API migration (T1+T2) | 4 → 8 sub-keys | 15 | 120 |
| Emoji strip (T2 mechanical) | ~10 | 15 | 150 |
| New keys from hardcode migration (T1+T2 fallback) | ~50 | 15 | 750 |
| Tagline replace (T1) | 4 brand × locale | 4 (en/vi × 2 brand) | 4 |
| Tagline mechanical 13 locale | 4 brand-key × 13 | 13 × 2 = 26 | 26 |
| Title Case → sentence case sweep (vi only) | ~229 | 1 | 229 |
| **TOTAL est.** | | | **~2400 cells edited** |

---

## 3. Plural API migration spec — concrete (still valid; numbers OK)

### 3.1 4 keys affected
- `home.clearCompletedMessage`
- `home.cleared`
- `home.deleted`
- `home.clearFailedMessage`

### 3.2 Old form (broken)
```json
{
  "home": {
    "clearCompletedMessage": "Delete {count} completed download{plural}?",
    "cleared": "✅ Cleared {count} download{plural}",
    ...
  }
}
```

### 3.3 New form (fix)
```json
{
  "home": {
    "clearCompletedMessage": {
      "one": "Delete {count} completed download?",
      "other": "Delete {count} completed downloads?"
    },
    "cleared": {
      "one": "Cleared {count} download",
      "other": "Cleared {count} downloads"
    },
    ...
  }
}
```

VI (count-neutral, identical for one + other):
```json
{
  "home": {
    "clearCompletedMessage": {
      "one": "Xóa {count} mục đã hoàn thành?",
      "other": "Xóa {count} mục đã hoàn thành?"
    },
    "cleared": {
      "one": "Đã xóa {count} mục",
      "other": "Đã xóa {count} mục"
    }
  }
}
```

### 3.4 13 other locale (mechanical Tier 2)
- For each locale, take current value with `{plural}` placeholder
- `.one` = template với `{plural}` removed (treat as singular)
- `.other` = current template với `{plural}` resolved as plural marker đúng locale (es: `s`, fr: `s`, de: `e/n`, ru/ar/hi: leave as Tier 3 deferred — pick `other` only with no plural form, will look slightly off in count != 1 cases, document)

→ Tier 3 polish v2.1.

### 3.5 Code call site change

Old:
```dart
final plural = completedCount > 1 ? 's' : '';
AppLocalizations.homeClearCompletedMessage(completedCount, plural)
```

New:
```dart
AppLocalizations.homeClearCompletedMessage(completedCount)
```

`AppLocalizations.homeClearCompletedMessage` impl:
```dart
static String homeClearCompletedMessage(int count) =>
    'home.clearCompletedMessage'.plural(count, namedArgs: {'count': '$count'});
```

### 3.6 Parity test mechanic

Plural API form flatten:
- `home.clearCompletedMessage.one` (key)
- `home.clearCompletedMessage.other` (key)

Each must have **same placeholder set across 15 locale**. Solution: dùng `{count}` ở cả `.one` và `.other` cho mọi locale (kể cả khi `.one` redundant) → placeholder set = `{{count}}` cho cả 2 forms. Parity test pass.

---

## 4. Mission Briefing namespace rename spec — ⚠️ STALE (claimed 25, real 16/10), see USAGE-REPORT §1

### 4.1 Old namespace
```
missionBriefing.title = "MISSION BRIEFING" / "BÁO CÁO NHIỆM VỤ"
missionBriefing.targetIntel = "TARGET INTEL" / "MỤC TIÊU"
missionBriefing.arsenal = "QUALITY ARSENAL" / "KHO CHẤT LƯỢNG"
... (25 keys total)
```

### 4.2 New namespace
```
downloadOptions.title          (was missionBriefing.title)
downloadOptions.platform       (was missionBriefing.targetIntel)
downloadOptions.quality        (was missionBriefing.arsenal)
downloadOptions.console        (was missionBriefing.console)
downloadOptions.cancel         (was missionBriefing.abort)
downloadOptions.start          (was missionBriefing.initialize)
downloadOptions.audioStream    (was missionBriefing.audioQuality)
... (25 keys total — 1:1 mapping)
```

### 4.3 Voice rewrite (vi + en — Tier 1)

Sample new content (full list trong implementation step):

| Key | EN new | VI new |
|---|---|---|
| `downloadOptions.title` | Download Options | Tùy chọn tải |
| `downloadOptions.platform` | Platform | Nền tảng |
| `downloadOptions.quality` | Quality | Chất lượng |
| `downloadOptions.console` | Settings | Cài đặt |
| `downloadOptions.cancel` | Cancel | Hủy |
| `downloadOptions.start` | Download | Tải |
| `downloadOptions.audioStream` | Audio | Âm thanh |
| `downloadOptions.videoOnly` | Video Only | Chỉ video |
| `downloadOptions.subtitles` | Subtitles | Phụ đề |
| `downloadOptions.chapters` | Chapters | Chương |
| `downloadOptions.extras` | More Options | Tùy chọn thêm |

(Full mapping ở implement step.)

### 4.4 13 locale Tier 2 (key rename only)

Content giữ nguyên, chỉ rename key. Content sẽ vẫn có "MISSION BRIEFING" / "ARSENAL" / etc. — military voice persists trong 13 locale, **không regression** so với current. Voice polish Tier 3 v2.1.

### 4.5 Code call site change

`app_localizations.dart`: rename 25 getter từ `missionBriefingX` sang `downloadOptionsX`.
- `dart_search` to find all 25 getter call site (3 file: download_config_dialog.dart, config_quality_panel.dart, config_preferences_panel.dart) and update.

---

## 5. Emoji strip spec (still valid)

### 5.1 Affected i18n string patterns
Search regex trong 15 .json file:
```
"^✅\s|^⚡\s|^✨\s|^💾\s|^⏸\s|^▶\s|^❌\s|^⚠️\s|^📌\s"
```

### 5.2 Action

Strip leading emoji + 1 space sau emoji. AppSnackBar/icon component sẽ render icon dựa trên call type (success/info/warning/error).

Examples:
- `"✅ Đã tải xong"` → `"Đã tải xong"`
- `"⚡ Auto-downloading..."` → `"Auto-downloading..."`
- `"✨ URL auto-pasted from clipboard"` → `"URL auto-pasted from clipboard"`

### 5.3 Side effects on call site

`AppSnackBar.success` already renders `Icons.check_circle_rounded` automatically. After strip, snackbar shows: `[icon ✓] [Đã tải xong]` instead of current `[icon ✓] [✅ Đã tải xong]` (double icon).

Negative test: ensure no string is meaningless without emoji (e.g., `"⏸ Đã tạm dừng"` → `"Đã tạm dừng"` still clear → OK).

---

## 6. VOICE.md / TERMINOLOGY.md drift sửa inline (still valid)

Khi áp manifest này, em sẽ update VOICE.md + TERMINOLOGY.md cho khớp:

| Drift | Fix |
|---|---|
| VOICE §2 line 55 nói "7 principles" | Update "8 principles" (P8 đã add) |
| VOICE §3.6 line 277 brand table tagline cũ | Update sang "Tải video. Đơn giản. Đẹp." |
| VOICE §9.1 line 506 length table tagline cũ | Update tương tự |
| VOICE §5.3 BrandConfig literal getter pattern | Đổi sang i18n key suffix pattern (`app.subtitle.${brand}.tr()`) |
| VOICE §8 SSvid emoji selective | Cập nhật: bỏ emoji khỏi i18n hoàn toàn, AppSnackBar icon component lo |
| VOICE §10 plural Option A "(s)" suffix EN | Cập nhật: dùng easy_localization plural API |
| TERMINOLOGY §3.4 status badge | Verify map đúng với DownloadStatus enum migration |

→ Sửa inline khi áp Step 3.

---

## 7. Verify steps — ⚠️ superseded by §12.6 Checkpoint A/B verify gates

Theo thứ tự:
1. **Atomic check 15 file JSON parity**: Run script Python custom verify cùng key tree + cùng placeholder set across 15 file. Trước khi run flutter test.
2. **`fvm flutter analyze --no-pub`**: phải pass (output "snakeloader").
3. **`fvm flutter test test/core/l10n/localization_key_parity_test.dart`**: phải pass.
4. **`fvm flutter test`** full: phải pass — đảm bảo không phá test khác.
5. **Smoke build SSvid macOS**: `fvm flutter build macos --debug --dart-define=BRAND=ssvid`.
6. **Smoke build VidCombo macOS**: `fvm flutter build macos --debug --dart-define=BRAND=vidcombo`.
7. **Manual smoke test (Chairman)**: Open SSvid + VidCombo, switch en/vi, verify:
   - Mission Briefing dialog → "Tùy chọn tải" / "Download Options"
   - Snackbar không double-icon
   - Empty state subtitle đúng surface
   - Tagline đúng brand
   - Quota banner đúng pronoun per brand
   - Clear completed → no "thànhs" appearing for count > 1

Windows build smoke: optional — em sẽ làm nếu có runner; nếu không, defer manual test.

---

## 8. KHÔNG ĐỘNG (out of scope 03C) (still valid; tagline + BrandConfig added to this list per §12.3)

Để Pass 03C không leak scope:
- **NO**: Settings page voice rewrite (defer Pass 04)
- **NO**: Browser feature voice rewrite
- **NO**: Player feature voice rewrite
- **NO**: Premium feature voice rewrite (chỉ home-triggered upsell snackbar)
- **NO**: 13 locale voice polish (Tier 3 — v2.1)
- **NO**: German Title Case rule
- **NO**: Russian/Arabic plural polish
- **NO**: BrandConfig.appDescription migration (probe = dead)
- **NO**: Settings dropdown disable
- **NO**: `v2_savedpref_to_preset_importer.dart` hardcoded VI (out of home)
- **NO**: Stitch prompt addendum integration

Tất cả ghi nhận → backlog v2.1 hoặc Pass 04.

---

## 9. Risk + mitigation (still valid)

| Risk | Mitigation |
|---|---|
| Plural API first-use bug | Test với count = 0, 1, 2, 99 trên en + vi trước commit |
| Parity test fail do placeholder mismatch | Python script atomic apply 15 file; verify placeholder set per-key trước commit |
| 13 locale fallback EN string | Document rõ trong commit message + manifest "Tier 2 fallback — TODO v2.1" |
| Emoji strip phá meaning | Negative test: read mỗi string post-strip và verify tự nó còn rõ nghĩa |
| Brand leak `Downloads/SSvid` regression | Test build VidCombo + verify default save path không có "SSvid" |
| Voice rewrite vi + en mất nghĩa | Cross-check với raw_home_strings.md original để đảm bảo intent preserved |
| Code call site rename leak | Grep all `missionBriefing` post-rename → 0 hits |
| AppSnackBar layout broken sau strip emoji | Visual smoke test snackbar success/error/info on home screen |

---

## 10. Estimated effort — ⚠️ superseded by USAGE-REPORT §11+§12

- **Step 3a — JSON sweep (mechanical 15 file)**: ~1.5h. Python script + manual review.
- **Step 3b — Voice rewrite vi + en (382 home + 25 downloadOptions)**: ~2-3h. Hand-write apply VOICE + TERMINOLOGY.
- **Step 3c — Dart layer (13 file edit)**: ~1.5h.
- **Step 3d — DownloadStatus + DownloadPriority migrate**: ~30min.
- **Step 3e — Plural API migration**: ~30min.
- **Step 3f — Tagline + BrandConfig pattern**: ~30min.
- **Step 3g — VOICE.md + TERMINOLOGY.md drift fix**: ~30min.
- **Step 3h — Verify (analyze, test, build smoke)**: ~1h.

**Total**: 7-9h. 1 session dài hoặc 2 session ngắn. Em đề xuất chạy 1 session — pass 03C là atomic, không nên split giữa.

---

## 11. Trạng thái — ⚠️ superseded by §12.7

- ✅ Step 1 — Manifest (file này)
- ✅ Step 2 — Reality probe (ground truth ở §0)
- ✅ Step 2.5 — Manifest patch (xem §12 — supersedes earlier figures)
- ⏸ Step 3 — Implement: 2 checkpoint A + B (xem §12.6)

---

## 12. Step 2.5 — Manifest Patch (supersedes §0-§11 where listed)

Reviewer 2 phát hiện 5 issues trong manifest gốc. Tất cả đã verify. Patch dưới đây supersede các section liên quan.

### 12.1 Dirty worktree classification (re-verified at Step 2.5 conclusion)

**Note**: Reviewer 2 phát hiện em đã conflate initial-context git status (session start) với current state. Earlier text "5 file + 1 untracked" SAI — đó là state hồi đầu session, không phải state hiện tại.

**Current state** (verified `git status --short`):

| File | Trạng thái | Loại | Conflict với 03C? |
|---|---|---|---|
| `lib/features/home/.../download_list_item.dart` | M (modified) | Color refactor (cs, accentHighlight, borderWidth) | ⚠ Em sẽ migrate `displayLabel` ở file này |
| `lib/features/home/.../filter_chips.dart` | M (modified) | Pure styling refactor (color token extraction) | 🟢 No conflict |
| `lib/features/home/.../home_screen_banners.dart` | M (modified) | Dark theme color/border tweaks | 🟢 No conflict |
| `docs/production-live-deep-audit-2026-04-27.md` | M | Docs (out of 03C scope) | 🟢 |
| `docs/v2/content-audit/03A-VOICE.md` | M | Em đã edit Pass 03A | 🟢 mine |
| `docs/production-live-index.md` | ?? untracked | Docs (out of scope) | 🟢 |
| `docs/v2/content-audit/03B-TERMINOLOGY.md` | ?? untracked | Em đã viết | 🟢 mine |
| `docs/v2/content-audit/03C-MANIFEST.md` | ?? untracked | Em đang viết | 🟢 mine |

**Verify cụ thể**: `git diff` cho 3 code file → KHÔNG có line touching `Text(...)`, `tooltip:`, `hintText:`, `message:`, `label:`. **Dirty code work = pure styling/structure, KHÔNG động i18n / hardcoded user-facing string**.

**Action trước Step 3**:
- Em đề xuất: anh `git add + commit` 3 code file dirty trước khi em start. 1 commit ngắn `wip(home-v2): styling tweaks pre-content-pass`.
- Nếu anh không muốn commit ngay, em vẫn chạy được — em chỉ edit + add new code/keys, KHÔNG xóa/thay existing line. Risk merge conflict thấp nhưng không zero.

### 12.2 missionBriefing — usage audit deferred to fresh report

**Note**: Reviewer 2 phát hiện em đếm sai trong prose (claim 14/12) vs table (16 ✅ / 10 💀). Plus initial audit script có bug: count raw key trong `app_localizations.dart` bao gồm cả canonical getter forwarding line → false positive 26/0.

Đặc biệt `rememberChoice` getter call site = 0 outside, NHƯNG raw key `'missionBriefing.rememberChoice'` được dùng làm **fallback inside `missionBriefingRememberChoiceFor` function** (`app_localizations.dart`:634). Reachable in production. KHÔNG được drop hời hợt.

**New rule** (per reviewer): "Drop only keys with zero getter call site outside app_localizations.dart AND zero raw key call site outside the canonical getter forwarding line." Generated usage report decides — KHÔNG hardcode dead-key list trong manifest.

**Sample mapping (14 confirmed-used by initial audit getter-call-site, 10 likely dead)**:

| Old key | Status (initial signal) | New key (downloadOptions.*) |
|---|---|---|
| abort | ✅ used | cancel |
| arsenal | ✅ used | quality |
| console | ✅ used | settings |
| desc4K, descAudio, descFHD, descHD, descQHD, descSD, descSubtitle, descVideoOnly | ✅ used (8 keys) | unchanged names |
| initialize | ✅ used | start |
| rememberChoice | ⚠ used via fallback (must keep) | rememberChoice |
| rememberChoiceFor | ✅ used | rememberChoiceFor |
| title | ✅ used | title |
| videoOnly | ✅ used | videoOnly |
| audioQuality, chapters, extras, format, platform, sponsorBlock, subtitles, targetIntel, timeRange, videoQuality | ⚠ likely dead — pending fresh report | (DROP if report confirms) |

**Tổng tạm**: 16 confirmed used (gồm rememberChoice fallback). 10 candidates for drop. Fresh report at Checkpoint A start sẽ chốt final số.

**OBSOLETE prose claim "14 used / 12 dead" — discard.**

| Old key | Used? | New key (downloadOptions.*) | Note |
|---|---|---|---|
| abort | ✅ | cancel | Voice rewrite |
| arsenal | ✅ | quality | Section title — replace military jargon |
| audioQuality | 💀 dead | (DROP) | Remove getter + 15 file JSON entry |
| chapters | 💀 dead | (DROP) | Remove |
| console | ✅ | settings | Used at config_preferences_panel.dart:280 |
| desc4K | ✅ | desc4K | Keep name (descriptor for resolution) |
| descAudio | ✅ | descAudio | Keep |
| descFHD | ✅ | descFHD | Keep |
| descHD | ✅ | descHD | Keep |
| descQHD | ✅ | descQHD | Keep |
| descSD | ✅ | descSD | Keep |
| descSubtitle | ✅ | descSubtitle | Keep |
| descVideoOnly | ✅ | descVideoOnly | Keep |
| extras | 💀 dead | (DROP) | Remove |
| format | 💀 dead | (DROP) | Remove |
| initialize | ✅ | start | "Initialize Download" → "Download" / "Tải" |
| platform | 💀 dead | (DROP) | Remove — collision concern moot since dead |
| rememberChoice | ✅ | rememberChoice | Keep |
| rememberChoiceFor | ✅ | rememberChoiceFor | Keep |
| sponsorBlock | 💀 dead | (DROP) | Remove |
| subtitles | 💀 dead | (DROP) | Remove |
| targetIntel | 💀 dead | (DROP) | Remove |
| timeRange | 💀 dead | (DROP) | Remove |
| title | ✅ | title | "MISSION BRIEFING" → "Download Options" / "Tùy chọn tải" |
| videoOnly | ✅ | videoOnly | Keep |
| videoQuality | 💀 dead | (DROP) | Remove |

**Result**: 14 keys migrate sang `downloadOptions.*` namespace. 12 dead keys removed entirely (getter + 15 JSON entries each = 180 cell removed = simplification).

**Code call site change**: 14 `missionBriefingX` getter rename → `downloadOptionsX` getter ở `app_localizations.dart` + 3 file render: `download_config_dialog.dart` + `config_quality_panel.dart` + `config_preferences_panel.dart`.

### 12.3 Tagline — DE-SCOPE (was: §2.3)

Probe verify: `appSubtitle` getter + `homeSubtitle` getter exist trong app_localizations.dart, KHÔNG có call site bên ngoài. Tagline hiện tại = **dead code**.

**New plan**: 
- KHÔNG migrate tagline trong 03C.
- KHÔNG edit BrandConfig.
- `app.subtitle` + `home.subtitle` keys giữ nguyên trong i18n (dead value, không hại).
- Khi nào team thực sự muốn render tagline → Pass 04 (out of scope V2 content).

→ Save 4-5 i18n cell × 15 locale + 1 BrandConfig change. Manifest §3.4 (SSvid tagline B) + VOICE.md §3.4 + §4.4 vẫn ghi nhận tagline cho **future use** — nhưng implement defer.

### 12.4 Plural 13 locale fallback — safe spec (was: §3.4)

Cũ: "de: e/n suffix, ru/ar leave Tier 3" — quá fuzzy.

**Mới**: Cho 13 locale (es/pt/de/fr/ja/ar/ru/hi/id/ko/th/tr/zh), use **current value** với `{plural}` literal removed làm CẢ `.one` lẫn `.other`. Identical strings.

Example es:
```json
"clearCompletedMessage": {
  "one": "¿Eliminar {count} descarga completada?",
  "other": "¿Eliminar {count} descarga completada?"
}
```

→ Grammatically off với count > 1 (Spanish should pluralize) — nhưng:
- Better than current state ("descarga{plural}" literal — completely broken).
- No invented suffix per locale.
- Polish at v2.1 với native review.

EN + VI vẫn voice-aware Tier 1.

### 12.5 Re-scan numbers (was: 382 keys, 47 hardcoded)

Probe lại post-recent-commits:

| Manifest cũ | Re-scan thực tế |
|---|---|
| 382 home-related keys | **408 keys** (gồm 26 missionBriefing) |
| 47 hardcoded user-facing strings | **52 hardcoded** (5 mới từ commits gần đây) |
| 25 missionBriefing keys | **26 keys, 14 used / 12 dead** |
| ~2400 i18n cell edited | **~2200 cell** (giảm 200 do 12 dead key removal × ~15 locale = ~180 saved) |

→ Manifest sẽ point đến số mới ở Step 3 implement. Trước khi edit code, em sẽ chạy 1 lần fresh scan để có truth tức thời.

### 12.6 Step 3 Checkpoint split (was: "1 session 7-9h atomic")

**Checkpoint A — Mechanical/infrastructure**:
1. **Step A.0 — Fresh dead-key + scope report** (mandatory first step):
   - Run script: for each missionBriefing key, count getter call site outside app_localizations.dart + count raw key call site outside canonical forwarding line.
   - Output: `docs/v2/content-audit/03C-USAGE-REPORT.md` with explicit dead/used verdict per key.
   - Re-count home-related keys (current state, post-recent-commits).
   - Re-grep hardcoded user-facing strings (current count, may differ from earlier 52).
   - Lock in numbers BEFORE any edit.
2. Mission Briefing namespace rename — apply ONLY to keys verified used by Step A.0 report. Drop ONLY keys verified dead by report (could be 0-10, not assumed 12). Atomic 15 file JSON + app_localizations.dart getter cleanup + render file call site rename.
3. Plural API migration (4 keys → `{one, other}` form, 15 file JSON, app_localizations.dart helper rewrite, 2 call site rewrite — `downloads_history_screen.dart` + `home_download_mixin.dart`).
4. Emoji strip (15 file JSON mechanical sweep).
5. Enum i18n migrate: `DownloadStatus.displayLabel` + `DownloadPriority.displayLabel` → return `AppLocalizations.X.tr()`. Add 12 new i18n keys (8 status + 3 priority + buffer).
6. Brand leak fix: `'Downloads/SSvid'` → `'Downloads/${BrandConfig.current.appName}'` ở `preset_popover.dart`.
7. **Verify gate**:
   - `flutter analyze --no-pub` pass (output "snakeloader")
   - `flutter test test/core/l10n/localization_key_parity_test.dart` pass
   - `flutter test` full pass
   - Smoke build SSvid macOS debug
8. **Commit "checkpoint A: mechanical content infra"**. Stop. Chairman verify.

**Checkpoint B — en/vi voice rewrite**:
1. 408 home-related keys vi + en hand-write apply VOICE.md + TERMINOLOGY.md.
2. 52 hardcoded → migrate sang i18n (vi + en hand-write).
3. Title Case → sentence case sweep (vi only).
4. emptySubtitle semantic mismatch fix (vi + en).
5. **Verify gate**:
   - `flutter analyze` pass
   - parity test pass
   - Smoke build SSvid + VidCombo macOS debug
   - Manual smoke screen-by-screen
6. **Commit "checkpoint B: en/vi voice rewrite"**. Stop. Chairman verify.

→ KHÔNG chạy 1 lèo. Pause + commit + verify giữa A và B.

**Effort estimate** (revised):
- Checkpoint A: 3-4h (mechanical, automatable, lower risk)
- Checkpoint B: 4-5h (hand-write content, higher quality bar)
- Total: 7-9h vẫn đúng, nhưng split rủi ro

### 12.7 Pre-Step-3 prerequisites (must pass)

- [ ] Chairman commit/stash 3 dirty code file (`download_list_item.dart`, `filter_chips.dart`, `home_screen_banners.dart`). Docs/manifests can stay unstaged.
- [ ] Chairman ack manifest patch §12 (this section, post Reviewer 2 patch)
- [ ] Em chạy Step A.0 (fresh dead-key + scope report) trước khi edit code → output `03C-USAGE-REPORT.md`
- [ ] Em chia checkpoint A theo report — KHÔNG hardcode dead-key list

→ Checkpoint A start chỉ sau khi 4 box trên check.
