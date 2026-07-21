# Pass 05 — Post-Merge Content Audit

**Trigger**: Merge của 3 PRs (#232 #233 #234) + V2 reconcile + User Playlist v20 vào `v2/home-redesign-foundation` HEAD `7cf8a5ae`. Em audit content layer post-merge theo Lớp 1/2/3 đã cam kết với Chairman.

**Verdict**: 7 regressions phát hiện + đã fix. Final gates pass.

---

## 0. Verify gates final

| Gate | Result |
|---|---|
| All 15 .json valid | ✅ Pass |
| `flutter analyze --no-pub` | ✅ 0 errors (21 info/warning đều từ PR #232 instrumentation, không phải content scope) |
| `localization_key_parity_test` | ✅ Pass (15 locale strict) |

---

## 1. Regressions phát hiện + đã fix

### 1.1 🔴 Broken JSON từ merge (en.json + vi.json)

**Symptom**: en.json/vi.json parse fail tại line 2555 — stray block 3 keys `descAudio/descVideoOnly/descSubtitle` chèn nhầm vào namespace `rightPanel`, missing comma trước.

**Cause**: Merge resolution `git merge` không clean — 3 keys cũ từ `missionBriefing` namespace bị orphan paste vào `rightPanel`.

**Fix**: Stripped 3 stray keys khỏi rightPanel ở en+vi (downloadOptions namespace đã có voice-rewritten versions từ Phase 1).

### 1.2 🔴 Missing `}` ở 13 non-en/vi locale

**Symptom**: 13 locale (es/pt/ja/ar/de/fr/hi/id/ko/ru/th/tr/zh) fail JSON parse — rightPanel namespace không có closing brace, nối thẳng sang floatingCapture.

**Cause**: Same merge corruption pattern.

**Fix**: Inserted missing `}` + comma sau `noEmbedSubtitle` line ở 13 file.

### 1.3 🟠 Parity gap 380 keys across 14 non-en locale

**Symptom**: Sau khi fix JSON parse, parity test fail — 13 locale missing 20-32 keys mỗi locale.

**Cause**: PR #234 dialog contract redesign + User Playlist v20 thêm new keys vào en+vi nhưng không vào 13 locale khác.

**Fix**: Filled missing keys với EN value (Tier 2 mechanical fallback per B-lite). Total 380 keys filled across 14 locales.

### 1.4 🔴 9 zombie `missionBriefingDesc*` getters trong app_localizations.dart

**Symptom**: 9 getters reference dead i18n keys `missionBriefing.desc*` (namespace đã rename → `downloadOptions` ở Phase 1). Runtime sẽ trả key path thay vì translated text.

**Cause**: Merge đã apply Phase 1 rename trong content nhưng không apply trong getter declarations.

**Fix**: Deleted 9 dead getter lines (line 790-800). Verified: 0 call sites cho `missionBriefingDesc*` outside app_localizations.dart.

### 1.5 🔴 5 brand leak strings

**Symptom**: Literal "Svid" trong i18n value sẽ render nguyên trên VidCombo build:
- `configDialog.containerChangedWarning` (en+vi) — "Svid will use {resolved}"
- `configDialog.qualityFallbackWarning` (en+vi) — "Svid will use {resolved}"
- `floatingCapture.popupBrand` (15 locale) — literal "Svid"
- `floatingCapture.popupActionOpenInApp` (15 locale) — "Open in Svid"
- `floatingCapture.popupMenuOpenApp` (15 locale) — "Open Svid"

**Cause**: PR #233 floatingCapture + PR #234 dialog contract authored với Svid context, không sử dụng `{appName}` placeholder.

**Fix**: 
- Replaced literal "Svid" → `{appName}` placeholder trong 5 keys × 15 locale = 75 cell
- Updated `configDialogQualityFallbackWarning` + `configDialogContainerChangedWarning` getters trong app_localizations.dart để pass `appName: BrandConfig.current.appName` vào namedArgs
- floatingCapture popup: `floating_window_main.dart:111` đã có `replaceAll('{appName}', BrandConfig.current.appName)` substitution — fix là parity-compliant

### 1.6 🟡 Banned vocab "Tải về"

**Symptom**: `floatingCapture.popupActionDownload` VI = "Tải về" — vi phạm TERMINOLOGY §3.1 canonical action verb (canonical: "Tải").

**Cause**: PR #233 không tham chiếu TERMINOLOGY.md.

**Fix**: "Tải về" → "Tải" trong vi.json.

### 1.7 🟡 Terminology inconsistency "danh sách phát"

**Symptom**: `playlist.fetching` VI = "Đang tải danh sách phát…" — TERMINOLOGY §3.2 canonical = "playlist" (loanword preserved per industry VN tech standard).

**Cause**: User Playlist v20 i18n authored với traditional VN translation.

**Fix**: "danh sách phát" → "playlist" trong vi.json.

---

## 2. Anti-pattern audit final state

| Anti-pattern | Pre-fix | Post-fix |
|---|---|---|
| AP1 — Mission Briefing voice in i18n value | 0 | ✅ 0 |
| AP2 — `missionBriefing` namespace exists | NO | ✅ NO |
| AP3 — `{plural}` literal placeholder | 0 | ✅ 0 |
| AP4 — `missionBriefingX` getter call site | 0 | ✅ 0 |
| AP5 — Zombie `missionBriefingX` getter declarations | **9** 🔴 | ✅ 0 |
| AP6 — Brand leak (literal "Svid"/"VidCombo") | **5** 🔴 | ✅ 0 |
| AP7 — Leading emoji in i18n strings | 0 | ✅ 0 |

---

## 3. Tinh túy preserved — 2 sides

### Side A — Phase 1-7 work session này

| Tinh túy | Status |
|---|---|
| Mission Briefing → downloadOptions (16 keep, 10 drop) | ✅ Preserved |
| Voice rewrite en+vi (16 downloadOptions keys) | ✅ Preserved |
| Plural API migration 4 keys | ✅ Preserved |
| Emoji strip 15 locale | ✅ Preserved |
| 49 hardcoded → i18n migration | ✅ Preserved |
| Title Case → sentence case sweep VI 201 keys | ✅ Preserved |
| Brand leak fix `Downloads/Svid` → `{appName}` | ✅ Preserved |
| Enum `displayLabel` migration | ✅ Preserved |
| 7 strategic voice rewrite (emptySubtitle, tagline, etc.) | ✅ Preserved |
| 60 missing keys parity fix | ✅ Preserved |

### Side B — Merge-side work (anh Kỳ + main)

| Tinh túy | Status |
|---|---|
| PR #232 instrumentation (Sentry + telemetry + PII) | ✅ Preserved (out of content scope, but i18n strings clean) |
| PR #233 floatingCapture v2.1 | ✅ Preserved + fixed brand leak |
| PR #234 dialog contract (qualityIntent/fileType) | ✅ Preserved + fixed brand leak |
| User Playlist v20 (membership API + AddToPlaylistDialog) | ✅ Preserved + fixed terminology inconsistency |
| Box 3 right sidebar player lifecycle hardening | ✅ Preserved |
| 15-lang i18n parity (Playlist v20 keys) | ✅ Preserved + filled 380 missing keys |

---

## 4. New content compliance check

### 4.1 `playlist.*` namespace (User Playlist v20)

| Key | Voice compliance |
|---|---|
| `playlist.addDialog.title` ("Add {count} to playlist" / "Thêm {count} vào playlist") | ✅ Sentence case, friendly conversational |
| `playlist.addDialog.empty` ("No playlists yet — create your first below.") | ✅ Action-oriented per VOICE P2 |
| `playlist.addDialog.createNew` ("Create new playlist") | ✅ Verb-first per VOICE V1 |
| `playlist.addDialog.nameHint` ("Playlist name") | ✅ Concise per VOICE P4 |
| `playlist.addDialog.nameRequired` ("Enter a playlist name") | ✅ Action verb |
| `playlist.addSuccess` ("Added {count} to {name}") | ✅ Past tense, count-aware |
| `playlist.rowMenu.addTo` ("Add to playlist…") | ✅ Verb-first |
| `playlist.fetching` ("Đang tải playlist…" — fixed) | ✅ Canonical "playlist" |

### 4.2 `floatingCapture.*` namespace (PR #233)

| Key | Voice compliance |
|---|---|
| `floatingCapture.settingsTitle` ("Floating capture" / "Bắt nhanh từ clipboard") | ✅ |
| `floatingCapture.popupActionDownload` ("Tải" — fixed) | ✅ Canonical verb |
| `floatingCapture.popupBrand` (`{appName}` — fixed) | ✅ Brand-aware |
| `floatingCapture.popupQuotaRemaining` ("Còn {count} lượt hôm nay") | ✅ Pronoun-drop OK per VidCombo voice |
| `floatingCapture.popupSnooze*` (1 day / 1 hour / etc.) | ✅ Concise |

### 4.3 `configDialog.*` new keys (PR #234)

| Key | Voice compliance |
|---|---|
| `configDialog.qualityFallbackWarning` (`{appName}` — fixed) | ✅ |
| `configDialog.containerChangedWarning` (`{appName}` — fixed) | ✅ |
| `configDialog.bestAvailableAuthRequired` | ✅ Functional |
| `configDialog.advancedOptions` / `advancedSummary` | ✅ Concise |

---

## 5. Files touched (post-merge audit fixes)

### i18n (15 locales)
- `assets/translations/{en,vi,es,pt,ja,ar,de,fr,hi,id,ko,ru,th,tr,zh}.json` — fixed JSON parse + parity gap + brand leak + vocab + terminology

### Dart code
- `lib/core/l10n/app_localizations.dart` — removed 9 zombie getters, added `appName` namedArg to 2 configDialog warning getters

### Docs
- `docs/v2/content-audit/05-POST-MERGE-AUDIT.md` (this file)

**NOT touched**: visual UI / layout / brand tokens / instrumentation logic — out of content lane.

---

## 6. Em không ký gì còn pending

✅ Em ký final: content layer ready production, 7 regressions fixed, all gates pass.

✅ Em không ký:
- Visual UI (lane của session khác — Opus/agent visual)
- Smoke build Svid + VidCombo macOS (Chairman manual verify trên desktop)
- Test failure 15 pre-existing (premium payment integration / hardware fingerprint / window service — pre-existing trước merge, không phải scope content)

---

## 7. Recommendation tiếp theo

**Em đề xuất Chairman / Opus session khác**:
1. Smoke build cả 2 brand (Svid + VidCombo) macOS debug → verify visual không regress
2. Manual sample read: switch language en/vi trên running app, verify content render đúng
3. Verify `floatingCapture` popup brand-aware substitution actually works on VidCombo build (visual smoke)
4. Quyết commit boundary: em đề xuất 1 commit duy nhất `fix(home-v2): post-merge content regressions — JSON parse + parity + brand leak + zombie getters`

**Em sẵn sàng standby cho re-audit nếu có thêm content drift sau visual session.**
