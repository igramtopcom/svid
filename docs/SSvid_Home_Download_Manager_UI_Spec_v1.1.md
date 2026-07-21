# SSvid Home / Download Manager UI Spec

**Version:** Draft v1.5
**Date:** 2026-05-05
**Supersedes:** v1.4, v1.3, v1.2, v1.1 (2026-05-05), v1.0 (2026-05-04)
**Scope:** Home screen / Download Manager screen only
**Primary flow:** Paste link or enter keyword → app detects intent → show results or download using preset
**Layout shell:** Top bar + left column + right column

## Changelog v1.4 → v1.5

External review feedback (Gemini) — 4 P1 issues all valid:

- **§10.1 schema fix**: `UserPlaylistItems.downloadId` đổi từ `TextColumn` → `IntColumn` để match `Downloads.id` (existing `IntColumn autoIncrement`). FK type mismatch sẽ không compile.
- **§10.0 mới**: Clarify relationship giữa Smart Collections (existing, dynamic filter), PlaybackQueue (existing, session-scoped), và Playlist của tôi (NEW, manual ordered list). 3 concepts cùng tồn tại, không gộp.
- **§17.2 mới**: FormatPreset DTO migration code — convert legacy 7-field records sang 15-field new schema với UUID + defaults cho fields mới.
- **§6.2 update**: Thêm platform-specific behavior table — Windows mở system browser qua `url_launcher` (vì `webview_flutter` không support Windows), macOS/Linux giữ in-app browser tab.

## Changelog v1.3 → v1.4

Self-audit pass — 7 P0 + 1 critical P1 resolved:

- §5.4 thêm rule fallback khi `activePresetId` trỏ tới preset bị xoá → revert `auto` built-in.
- §5.5 update Rule chain — bỏ `alwaysAskConfig` (Tier 3 dropped).
- §5.6 **drop Tier 3** (setting trong Settings → Quality → Advanced). Còn 2 tiers: ⚙️ icon + popover toggle.
- §5.6 thêm note "Tier scope": tiers chỉ apply ở context có Tải xuống button (Home + sheets), không apply ở smart input CTA mode "Tìm kiếm"/"Xem kênh"/"Xem playlist".
- §5.6 thêm rule: `PlatformQualityPreference` auto-save chỉ trigger qua Rule 4 / Rule 3' (user explicit pick qua dialog). Rule 3 (silent) không save → giữ nguyên existing save logic, no code change.
- §7 clarify: ⚙️ icon KHÔNG bị disable bởi quota=0. Chỉ Tải xuống button bị disable.
- §8 explicit: tab 2 = "Playlist của tôi" (bỏ điều kiện về queue manager).
- §13 tab order: thêm `customize icon` giữa batch và preset.
- §15 acceptance: bỏ items Tier 3, gộp Tier 2 ownership.
- Roadmap Phase 1A: bỏ task Tier 3 setting, gộp providers, giảm scope nhẹ.
- History icon **giữ nguyên** trong control bar (chưa xoá theo quyết định trước).

## Changelog v1.2 → v1.3

- §5.7 mới — "Batch context customization" cover câu hỏi "100 URL → 100 dialog?".
- Default `applyToAll = ON` cho batch context (single click customize cho cả batch).
- `DownloadConfigDialog` thêm 2 params: `isBatchContext` + `defaultApplyToAll`.
- Batch context disable Section trim + specific quality picker (per-video options không apply được cho batch).
- Warn toast khi user uncheck "Apply to all" trong batch.
- §15 acceptance bổ sung 5 items cho batch context.

## Changelog v1.1 → v1.2

- §4 control bar: thêm icon `⚙️ Tuỳ chỉnh` giữa Batch và Preset dropdown — entry point one-shot cho `DownloadConfigDialog` (subtitle, section trim, codec, embed, sponsorblock).
- §5.2 popover footer: thêm toggle "Tuỳ chỉnh chuyên sâu trước khi tải" — sticky preference cho power user.
- §5.5 Rule chain mở rộng: thêm Rule 3' (toggle ON behavior) + Rule 4 (explicit `⚙️` click).
- §5.6 mới — "Customization access tiers" (3 tier: icon / popover toggle / settings).
- §15 acceptance bổ sung 4 items cho 3 entry points.

## Changelog v1.0 → v1.1

- §5 rewritten with explicit 3-layer config model mapped to existing `PlatformQualityPreference` + `FormatPreset`.
- §8.3 expanded from 5 to 9 row states (added `pending`, `postProcessing`, `paused`, `cancelled`, `waitingForNetwork`).
- §10 detailed with DB schema, domain entities, player integration scope.
- §4.1 multi-URL parsing rules + unsupported URL decision tree clarified.
- §8.1 sort options enumerated.
- §9.2 renamed `[Thêm]` → `[Khác]` (icon `⋯`) to remove ambiguity with "Thêm vào playlist".
- New §17 Migration, §18 Telemetry, §19 Performance.
- Dark mode tokens added in §12.

---

## 1. Mục tiêu

Biến Home thành công cụ tải và quản lý media nhanh, rõ, không trùng chức năng. User bắt đầu bằng một input duy nhất, cấu hình preset tải mặc định một lần, sau đó quản lý lịch sử tải và playlist nội bộ trong cùng một màn.

- Giữ layout shell: top bar, left column, right column.
- Left column: smart input, plan strip, Lịch sử tải xuống, Playlist của tôi.
- Right column: Bắt đầu nhanh, Mở nhanh website.
- Bỏ trùng lặp: Premium + Nâng cấp cùng lúc, platform shortcut ở left column, dropdown trong nút Tải xuống.
- Download history trở thành download manager + media manager (rows, bulk select, playlist).

---

## 2. Layout tổng thể

| Vùng | Vai trò | Thành phần |
|---|---|---|
| Top bar | Điều hướng cấp app | Logo, Trang chủ, Đăng ký, Chuyển đổi, Trình duyệt, Nâng cấp/Premium, notification, settings, theme, window controls |
| Left column | Thao tác và quản lý nội dung | Smart input, preset, plan strip, Lịch sử tải xuống, Playlist của tôi |
| Right column | Hướng dẫn và shortcut | Bắt đầu nhanh, Mở nhanh website |

**Responsive (P1):**
- ≥1280px: 3 columns full
- 1024-1279px: right column collapse thành button toggle
- <1024px: stack 1 column, right column ẩn

---

## 3. Top bar

Không hiển thị đồng thời **Premium** và **Nâng cấp**.

| User state | Hiển thị | Không hiển thị |
|---|---|---|
| Free user | Nút `Nâng cấp` góc phải | Badge Premium |
| Premium user | Badge/menu Premium | Nút Nâng cấp |

**"Trình duyệt" tab role**: Navigate tới `lib/features/browser/` (in-app WebView), KHÔNG phải platform shortcut. Khi click "Mở nhanh website → YouTube" từ right column → chuyển sang tab Trình duyệt + load URL.

**Plan strip CTA + top bar Nâng cấp**: Nếu cùng visible, plan strip CTA phải là **text link** (`Nâng cấp →`), không phải button. Top bar Nâng cấp = primary, plan strip = contextual.

---

## 4. Smart input

Entry point chính. Nhận paste link, drag/drop, gõ keyword, multiple URLs.

**Cấu trúc control:**

```text
[Input link hoặc từ khóa] [History icon] [Batch icon] [Customize icon ⚙️] [Preset dropdown] [Primary CTA]
```

| Control | Hiển thị | Behavior |
|---|---|---|
| Input | Placeholder: "Dán link video, playlist, kênh hoặc nhập từ khóa..." | Enter để submit |
| History icon | Icon-only, tooltip "Lịch sử tải xuống" | Scroll/focus tới section history |
| Batch icon | Icon-only, tooltip "Tải hàng loạt" | Mở batch dialog |
| **Customize icon** ⚙️ | Icon-only, tooltip "Tuỳ chỉnh trước khi tải" | Mở `DownloadConfigDialog` cho lần tải này (one-shot, không lưu). Disabled khi URL chưa valid hoặc đang phân tích. Hidden cho channel/search keyword. |
| Preset dropdown | Vd: "MP4 · 1080p" | Mở popover (xem §5) |
| Primary CTA | Vd: "Tải xuống" | Không có dropdown. Label đổi theo input. |

### 4.1 Smart detection rules

**Detection order** (first match wins):

1. **Trống** (chỉ whitespace) → CTA disabled
2. **Multiple URLs**: ≥2 URL hợp lệ phân tách bằng newline `\n` HOẶC whitespace HOẶC comma `,` → CTA = "Tải hàng loạt", submit → mở batch dialog
3. **Single video URL**: 1 URL match `VideoPlatform.detectFromUrl()` → CTA = "Tải xuống"
4. **Playlist URL**: URL chứa `?list=` (YouTube) hoặc tương đương → CTA = "Xem playlist", mở `YouTubePlaylistSheet`
5. **Channel URL**: URL match channel pattern (`youtube.com/@`, `tiktok.com/@`) → CTA = "Xem kênh", mở `YouTubeChannelSheet`
6. **Unsupported URL** (có `http(s)://` + valid TLD nhưng platform không support):
   - HTTP(S) + valid host → CTA = "Mở trình duyệt", submit → tab Trình duyệt + load URL
   - Else → CTA = "Tìm kiếm" + warning toast "URL không hợp lệ, thử tìm kiếm thay thế"
7. **Text keyword** (không phải URL) → CTA = "Tìm kiếm", mở `YouTubeSearchSheet`

**Debounce**: 500ms sau keystroke cuối mới re-detect. URL invalid >2s → revert CTA về "Tải xuống" disabled.

**Multi-URL parsing**:
```
"https://yt.com/a https://tiktok.com/b" → 2 URLs
"https://yt.com/a, https://tiktok.com/b" → 2 URLs
"https://yt.com/a\nhttps://tiktok.com/b" → 2 URLs
"check this https://yt.com/a" → 1 URL (mixed text → ignore non-URL)
```

### 4.2 Extraction states

| State | UI feedback |
|---|---|
| Idle (URL valid, chưa submit) | CTA enabled, sub-label dropdown reflect preset |
| Đang phân tích | CTA disabled, spinner trong button, label "Đang phân tích..." |
| Extract success | CTA enabled, snackbar/auto-download theo Rule chain |
| Extract fail | Inline error dưới input, retry button |
| Network offline | Banner cảnh báo trên smart input |

Rules:
- Không tự auto-tải playlist/channel — luôn show dialog cho user pick.
- Search/playlist/channel render nội dung trong dialog, không inline trong Home.
- CTA không có dropdown ở mọi state.

---

## 5. Preset download (3-layer model)

### 5.1 Architecture — 3 layers config resolution

```
┌─ Layer 1: PlatformQualityPreference (auto, per-URL) ─┐
│ Map: lib/features/settings/domain/entities/           │
│      platform_quality_preference.dart                 │
│ 15 fields, auto-saved khi user pick qua dialog        │
│ Detect platform từ URL → if pref tồn tại → WIN        │
└────────────────────────────────────────────────────────┘
                  ↓ fallback nếu không có pref
┌─ Layer 2: Active FormatPreset (manual, global) ──────┐
│ Map: lib/features/settings/data/datasources/          │
│      format_presets_service.dart                      │
│ Active preset id lưu SharedPreferences                │
│ + currentConfig override khi user tweak popover       │
└────────────────────────────────────────────────────────┘
                  ↓ fallback cho field nào FormatPreset không cover
┌─ Layer 3: SettingsState global defaults ─────────────┐
│ codec, container, fps preferences                     │
└────────────────────────────────────────────────────────┘
```

**Resolver**: `EffectiveDownloadConfigService.resolve(url) → DownloadConfig`

```
1. Detect platform từ URL
2. Đọc PlatformQualityPreference.getPreference(platform)
3. Nếu có → merge fields có giá trị, tiếp với Layer 2 cho field null
4. Đọc currentConfig (active FormatPreset + popover overrides)
5. Merge với Layer 3 SettingsState
6. Return final DownloadConfig
```

### 5.2 Preset popover layout

```
┌─ Tùy chọn tải mặc định ────────────────────┐
│                                             │
│ ── Profile ─────────────────────────────── │
│ ✓ Tự động (cao nhất)         🔒 built-in  │
│   1080p MP4                  🔒 built-in  │
│   720p tiết kiệm             🔒 built-in  │
│   Audio MP3 320k             🔒 built-in  │
│   4K cao nhất                🔒 built-in  │
│   Lưu trữ (4K + sub + meta)  🔒 built-in  │
│   ─────────                                │
│   <user-created presets>                   │
│   ─────────                                │
│   + Tạo profile mới...                     │
│                                             │
│ ── Tùy chỉnh nhanh ───────────────────────  │
│ Định dạng:           MP4 (Video)     ▼     │
│ Chất lượng:          1080p           ▼     │
│ Khi không có:        Gần nhất       ▼     │
│ Vị trí lưu:    Downloads/SSvid    [Đổi]    │
│                                             │
│ ── Tuỳ chọn nâng cao ──────────────────── │
│ ☐ Tuỳ chỉnh chuyên sâu trước khi tải       │
│   Khi bật, click Tải xuống sẽ mở dialog    │
│   cấu hình chi tiết.                        │
│                                             │
│ ⚙️  Mở cài đặt tải nâng cao →             │
└─────────────────────────────────────────────┘
```

### 5.3 Built-in FormatPresets (seed on first run)

| ID | Tên | Config |
|----|-----|--------|
| `auto` | Tự động (cao nhất) ⭐ default | `containerFormat: auto, maxResolution: 0, fallback: nearest` |
| `1080p_mp4` | 1080p MP4 | `mp4, h264, 1080p` |
| `720p_compact` | 720p tiết kiệm | `mp4, h264, 720p` |
| `audio_mp3_320` | Audio MP3 320k | `mp3, audioOnly, 320kbps` |
| `4k_max` | 4K cao nhất | `mp4, 2160p, fallback: nearest` |
| `archive` | Lưu trữ | `mkv, best, +sub +metadata +chapters` |

Built-in **read-only** (`isBuiltIn: true`), có icon 🔒. User chỉ **clone**, không edit/delete.

### 5.4 State management

| Variable | Type | Where |
|----------|------|-------|
| `activePresetId` | String | SharedPreferences `active_preset_id` |
| `currentConfig` | `DownloadConfig` | SharedPreferences `current_config` (JSON) |
| `customPresets` | `List<FormatPreset>` | SharedPreferences `format_presets` (existing) |

| User action | Effect |
|-------------|--------|
| Mở popover | Hiển thị active preset (✓), 4 fields = `currentConfig` |
| Chọn preset khác | `activePresetId` updated, `currentConfig` = preset.config |
| Tweak field inline | `currentConfig` updated, badge "(đã chỉnh sửa)" cạnh active preset |
| Click "+ Tạo profile mới..." | Modal "Tên?" → tạo FormatPreset từ snapshot `currentConfig` |
| Đóng popover | Apply `currentConfig` cho mọi download tiếp theo |
| Click "Mở cài đặt tải nâng cao →" | Navigate Settings → Quality section |

**Important**: Tweak field KHÔNG auto-save vào active preset. Save = explicit qua "+ Tạo profile mới" hoặc Settings → Quality.

**Active preset deleted fallback**: Nếu user xoá preset đang active (vd qua Settings → Quality), `activePresetId` trỏ tới ID không tồn tại → app phải:

1. Detect khi load: `customPresets.firstWhereOrNull((p) => p.id == activePresetId) == null`
2. Set `activePresetId = 'auto'` (built-in default) + clear `currentConfig`
3. Persist immediately vào SharedPreferences
4. Toast info: "Profile đang dùng đã bị xoá. Đã chuyển sang 'Tự động'."

### 5.5 Rule chain integration với download flow

Sửa [home_download_mixin.dart:382-435](lib/features/home/presentation/screens/home_download_mixin.dart):

```dart
// Rule 1: Single quality → auto-download (KHÔNG ĐỔI)
// Rule 2: PlatformQualityPreference EXISTS → auto-download (KHÔNG ĐỔI, snackbar giữ nguyên)
// Rule 3: No per-platform pref + popoverDeepCustomize=OFF
//   → silent auto-download với active preset (snackbar "Đang tải với <preset name>")
// Rule 3' (MỚI): No per-platform pref + popoverDeepCustomize=ON
//   → mở DownloadConfigDialog (giữ persistent preference cho session)
// Rule 4 (MỚI): User click ⚙️ icon trên action bar TRƯỚC khi click Tải xuống
//   → mở DownloadConfigDialog one-shot, override Rule 3/3' cho lần này
// Rule 5: User explicit "Tùy chỉnh cho lần này" từ row action sau download bắt đầu
//   → cho retry/edit per-row (không áp dụng cho download active)
```

### 5.6 Customization access tiers

2 cơ chế cho user truy cập `DownloadConfigDialog`, phục vụ persona khác nhau:

| Tier | Vị trí | Persistence | Cost | Persona |
|------|--------|-------------|------|---------|
| **1. Icon `⚙️ Tuỳ chỉnh`** | Action bar (smart input) | One-shot per click | 1 click | Casual user thỉnh thoảng customize |
| **2. Toggle popover** | Trong preset popover, section "Tuỳ chọn nâng cao" | Sticky cho đến khi tắt | 1 toggle + N click Tải xuống | Power user trong session |

**Hierarchy logic** (ưu tiên cao → thấp):

```
1. Icon ⚙️ click trên action bar (one-shot)         → Rule 4 fires
2. Per-platform pref tồn tại                          → Rule 2 fires (auto-download)
3. Toggle popover ON                                  → Rule 3' fires (open dialog)
4. Default                                            → Rule 3 fires (silent auto-download)
```

**Key behaviors:**

- Click icon ⚙️ **luôn thắng** mọi setting/toggle khác — đây là "I want to customize THIS download specifically".
- Per-platform pref **không bị bypass** bởi toggle — Rule 2 vẫn ưu tiên cao hơn để tôn trọng "đã lưu cho YouTube" intent.

**Tier scope** — context nào tier áp dụng:

| Context | ⚙️ icon | Toggle popover |
|---------|---------|----------------|
| Smart input → CTA "Tải xuống" (single video URL) | ✅ | ✅ |
| Smart input → CTA "Tải hàng loạt" (multi-URL) | ✅ (with `isBatchContext=true`) | ✅ (with `applyToAll=ON`) |
| Smart input → CTA "Tìm kiếm" / "Xem kênh" / "Xem playlist" | ❌ Hidden (không có Tải xuống ở stage này) | ⚠️ Bypass (sheet mở riêng) |
| Trong search/channel/playlist sheet → click Tải xuống cho 1 item | N/A (không có icon trong sheet) | ✅ Apply (sheet honor toggle) |
| Trong sheet → click bulk download | N/A | ✅ Apply (with `applyToAll=ON`) |

→ Nguyên tắc chung: **ở mọi nơi có nút Tải xuống và toggle ON → tier 2 enable**, dù là Home action bar hay nested sheets.

**Per-platform pref auto-save behavior:**

`PlatformQualityPreference` chỉ auto-save khi user **explicit pick qua DownloadConfigDialog** (Rule 4 hoặc Rule 3'). Default flow Rule 3 (silent) **KHÔNG** trigger save. → Logic save existing trong [home_download_mixin.dart](lib/features/home/presentation/screens/home_download_mixin.dart) **không cần đổi** — tự nhiên work với rule chain mới.

Hệ quả: user dùng default flow lâu ngày sẽ KHÔNG có per-platform pref nào. Đó là intentional — silent flow tôn trọng global active preset.

**Toggle popover state:**

- Lưu trong SharedPreferences key `popover_deep_customize`.
- Default OFF.
- Khi ON → label preset dropdown thêm dấu `*` để hint user (vd `MP4 · 1080p *`).
- Khi click Tải xuống với toggle ON → mở dialog → save → tải. Toggle KHÔNG auto-reset.

### 5.7 Batch context customization

Khi input là multi-URL hoặc batch icon click, customization tiers behave khác để tránh dialog spam.

**Behavior matrix:**

| Tier | Single URL | Batch (≥2 URLs) |
|------|-----------|-----------------|
| ⚙️ icon (Rule 4) | Dialog cho video đó | Dialog với `isBatchContext=true`, `defaultApplyToAll=ON` |
| Toggle popover (Rule 3') | Dialog cho video đó | Dialog 1 lần cho video đầu, `applyToAll=ON` |
| Default (Rule 3) | Silent với active preset | Silent batch với active preset cho **tất cả** |

**Nguyên tắc**: Batch context **luôn force `applyToAll = ON` defaulted**. User có thể uncheck nếu thực sự muốn per-video, nhưng phải explicit opt-in.

### 5.7.1 DownloadConfigDialog batch mode

Dialog API extension:

```dart
DownloadConfigDialog.show(
  context, videoInfo, platform,
  remainingCount: urls.length - currentIndex,
  isBatchContext: true,        // NEW
  defaultApplyToAll: true,     // NEW
);
```

**Disabled options trong batch context** (per-video, không apply được cho batch):

| Option | Single | Batch |
|--------|--------|-------|
| Quality selection | ✅ Pick specific | ⚠️ Auto-match với fallback (vì mỗi video có quality khác nhau) |
| Codec/container/fps | ✅ | ✅ Apply all |
| Subtitles | ✅ | ✅ Apply all |
| SponsorBlock (YouTube) | ✅ | ✅ Apply all |
| Embed metadata/thumbnail/chapters | ✅ | ✅ Apply all |
| **Section trim** (start/end time) | ✅ | ❌ **Disabled** (grey-out với tooltip "Không khả dụng cho tải hàng loạt") |
| **Specific quality override** | ✅ | ❌ **Disabled** (chỉ giữ auto-match) |

### 5.7.2 Apply to all uncheck warning

Nếu user uncheck "Apply to all" khi `remainingCount > 5`:

```
┌─ ⚠️ Cảnh báo ───────────────────────────────┐
│ Bạn sẽ thấy dialog cấu hình cho mỗi {N}     │
│ video trong batch. Tiếp tục?                 │
│                                              │
│            [Huỷ]  [Tiếp tục]                │
└──────────────────────────────────────────────┘
```

→ Default click "Huỷ" để re-check.

### 5.7.3 Worst case prevention

So với code hiện tại (potentially 100 dialogs nếu user không check "Apply to all"):

| Scenario | v1.x current | v1.3 design |
|----------|--------------|-------------|
| 100 URLs YouTube + có per-platform pref | 0 dialog | 0 dialog (Rule 2) ✅ |
| 100 URLs + active preset, default flow | Per-video dialog popup | 0 dialog (Rule 3) ✅ |
| 100 URLs + ⚙️ click | Manually check Apply all | 1 dialog (default ON) ✅ |
| 100 URLs + Tier 2 ON | Per-video dialog | 1 dialog (force applyToAll=ON) ✅ |
| 100 URLs + user uncheck Apply all | 100 dialogs | Warn toast → user explicit confirm ✅ |

→ v1.3 prevent 100-dialog UX disaster ở mọi entry point trừ explicit user opt-in.

---

## 6. Right column

Hai box mặc định:

1. **Bắt đầu nhanh** — onboarding 3 bước, dismissible (lưu state vào SharedPreferences).
2. **Mở nhanh website** — 9 platform shortcuts: YouTube, TikTok, Facebook, Instagram, X, Reddit, Pinterest, Vimeo, "Thêm website".

Không hiển thị mặc định: Storage, Session Pulse, Download Details, Shortcuts, Tip card.

### 6.2 Click website behavior (cross-platform)

`webview_flutter` chưa support Windows ([top_navigation_bar.dart:135](lib/core/navigation/top_navigation_bar.dart:135) hide browser tab on Windows). Cần fallback platform-specific:

| Platform | Click website → | Implementation |
|----------|-----------------|----------------|
| macOS | Chuyển tab Trình duyệt + load URL | Existing `app_scaffold` navigation |
| Linux | Chuyển tab Trình duyệt + load URL | Existing |
| Windows | Mở system browser (default browser của user) | `url_launcher` package, `launchUrl(uri, mode: LaunchMode.externalApplication)` |

**Tooltip platform-specific:**
- macOS/Linux: "Mở [website] trong trình duyệt tích hợp"
- Windows: "Mở [website] trong trình duyệt hệ thống"

**Empty state if browser tab hidden** (Windows): không có "Trình duyệt" tab trên top bar → "Mở nhanh website" panel vẫn hiện, click → external browser. Không bị mất feature.

---

## 7. Plan strip

```text
Gói miễn phí · Bạn còn 15 lượt tải hôm nay · Nâng cấp →
```

| Quota state | Behavior |
|-------------|----------|
| >5 lượt | Text bình thường, CTA = text link |
| 1-5 lượt | Text màu cảnh báo (orange), CTA prominent text link |
| 0 lượt | Block button Tải xuống → click → mở paywall dialog |
| Premium | Hide strip HOẶC hiện "Premium · không giới hạn" |

**Quota reset**: 00:00 local time (existing behavior, không đổi).

**Quota vs other controls** (independent gates):

| Control | Disable bởi quota=0? | Lý do |
|---------|----------------------|-------|
| Nút Tải xuống | ✅ Block + paywall | Đây là gate chính của quota |
| Nút Tải hàng loạt | ✅ Block + paywall | Bulk = nhiều downloads |
| Icon ⚙️ Tuỳ chỉnh | ❌ Vẫn enable | Configure không tốn quota; user có thể prep config trước khi nâng cấp |
| Preset dropdown | ❌ Vẫn enable | Setting only, không tốn quota |
| Smart input typing/paste | ❌ Vẫn enable | Input không tốn quota |
| Sheets (search/channel/playlist) | ⚠️ CTA Tải bên trong block, nhưng browse OK | View free, download tốn quota |

---

## 8. Download manager

### 8.1 Tabs + toolbar

```
[Tab: Lịch sử tải xuống] [Tab: Playlist của tôi]
─────────────────────────────────────────────────
[☐ Select all] [🔍 Search] [↕️ Sort ▼] [☰ Filter] [⊞⊟ View]
```

**Sort options** (dropdown):
- Mới nhất ↓ (default — `addedAt DESC`)
- Cũ nhất ↑
- Theo tên A→Z / Z→A
- Theo size (lớn→nhỏ / nhỏ→lớn)
- Theo trạng thái

**Filter** (icon-only, click → popover):
- Filter trong popover: media type, platform, status, tags, watch state
- Active filter → icon có badge số filter đang áp dụng

**View toggle**: list (default) / grid

**Search placeholder**: "Tìm trong lịch sử..."

### 8.2 Row layout

Normal row:
```
[thumbnail] Title / Source / Metadata [Action icon] [⋮ More]
```

Hover row:
```
[checkbox] [thumbnail] Title / Source / Metadata [Action icon] [⋮ More]
```

Rules:
- Checkbox xuất hiện khi hover hoặc selection mode active
- Action cuối row = icon-only (Play/Pause/Retry/Resume/Cancel)
- "Mở thư mục" thuộc menu `⋮` More, không phải action chính
- Tooltip + aria-label bắt buộc

### 8.3 Row states (9 states)

| State | Metadata | Action icon | Visual treatment |
|-------|----------|-------------|------------------|
| `completed` (Đã tải) | `Đã tải · MP4 · 1080p · 224.51 MB · 28/04/2026 14:21` | ▶️ Play | Badge xanh nhẹ, row trắng |
| `downloading` (Đang tải) | `Đang tải · 43% · 1.02 GB / 2.38 GB · 12.4 MB/s · Còn 1m 32s` | ⏸ Pause | Row blue-50, progress bar full-width 2px dưới metadata |
| `postProcessing` (Đang chuyển đổi) | `Đang chuyển đổi · FFmpeg merging...` | ⋮ More only | Row purple-50, indeterminate spinner |
| `queued` (Đang chờ) | `Đang chờ · 0 B / 3.24 GB` | ⋮ More (drag handle ≡ bên trái) | Badge xám-xanh, không progress bar |
| `pending` (Sắp tải) | `Sắp tải · chuẩn bị...` | ⋮ More | Badge xám rất nhạt |
| `paused` (Tạm dừng) | `Tạm dừng · 43% · 1.02 GB / 2.38 GB` | ▶️ Resume | Row gray-50, progress bar dimmed |
| `failed` (Lỗi) | `Lỗi · {errorMessage}` | 🔁 Retry | Row red-50, badge đỏ |
| `cancelled` (Đã huỷ) | `Đã huỷ · 28/04/2026 14:21` | 🔁 Retry | Row gray-100, opacity 70% |
| `waitingForNetwork` (Chờ mạng) | `Chờ kết nối mạng · auto-retry khi online` | ⋮ More | Row yellow-50, network icon |

Audio row variant:
- Thumbnail: waveform icon + duration
- Metadata: `MP3 · 320kbps · 8.45 MB`

Image row variant:
- Thumbnail: image preview
- Metadata: `JPG · 1920×1080 · 2.45 MB` (no duration)

Rules:
- Progress bar **chỉ** ở `downloading` + `postProcessing`. Bar full-width của content row, 2px height, color blue-500.
- Đổi nhãn "Đã hoàn thành" → "Đã tải" (cần update [vi.json](assets/translations/vi.json) + en/ja/pt/es).
- Drag handle `≡` chỉ hiện ở row `queued` để reorder priority (Phase 73 feature).

**Tags display** (Phase 73.4 integration):
- Nếu row có tag → hiển thị inline chip dưới title (max 3 tag, "+N" nếu nhiều)
- Click tag → filter list theo tag đó

**Watch progress** (Phase 22 integration):
- Nếu `completed` row có watch progress → 2px overlay bar trên thumbnail (red-500, % của total duration)

---

## 9. Multi-select và bulk actions

### 9.1 Checkbox behavior

| Trạng thái | Checkbox | Toolbar |
|-----------|----------|---------|
| Normal | Hidden, hiện khi hover row | Search/sort/filter |
| Hover | Checkbox đầu row | Không đổi |
| Tick 1 row | All rows show checkbox; selected = checked | → Selection toolbar |
| Tick "Select all" | All visible rows selected | → Selection toolbar |

### 9.2 Selection toolbar

```text
[n đã chọn] [▶️ Phát] [➕ Thêm vào playlist] [🗑️ Xoá] [⋯ Khác] [✕ Huỷ]
```

(Đổi `[Thêm]` v1.0 → `[⋯ Khác]` để không nhầm với "Thêm vào playlist")

### 9.3 Bulk action rules

| Action | Áp dụng cho | Behavior |
|--------|------------|----------|
| ▶️ Phát | `completed` items | Phát theo thứ tự selection. Nếu chọn 5/3 ready → toast "Chỉ phát 3/5 mục đã tải" |
| ➕ Thêm vào playlist | `completed` items | Mở `AddToPlaylistMenu` (xem §10). Item chưa hoàn tất bị skip |
| 🗑️ Xoá | Mọi state | Confirm dialog (§9.4) |
| ⋯ Khác | Mọi state | Menu: Sao chép link, Mở thư mục, Tải lại, Tạm dừng, Tiếp tục, Huỷ tải, Export metadata |
| ✕ Huỷ | - | Bỏ chọn tất cả, quay về toolbar thường |

### 9.4 Confirm delete dialog

```text
Bạn muốn xoá {n} mục đã chọn?

( ) Chỉ xoá khỏi lịch sử
( ) Xoá cả file khỏi máy

[Huỷ]  [Xoá]
```

### 9.5 Keyboard shortcuts

| Key | Action |
|-----|--------|
| `Cmd/Ctrl + A` | Select all visible |
| `Esc` | Exit selection mode |
| `Shift + Click` | Range select |
| `Delete` / `Backspace` | Trigger bulk delete confirm |
| `Cmd/Ctrl + Click` | Toggle individual selection |

### 9.6 Mixed-state selection

- Action invalid cho 1 item → enable nếu có ≥1 item valid; disabled item bị skip với tooltip "{n} mục bị bỏ qua: lý do"

---

## 10. Playlist của tôi

Playlist nội bộ (khác playlist nguồn từ YouTube/TikTok). User tạo từ download history, phát sequential.

### 10.0 Relationship với features hiện có

App đã có 2 concepts liên quan tới "group of media". PRD §10 thêm concept thứ 3. **Cả 3 cùng tồn tại, không gộp** — mỗi cái phục vụ use case khác.

| Feature | Nature | Storage | Use case | Status |
|---------|--------|---------|----------|--------|
| **Smart Collections** | Dynamic — auto-match by filter (platforms/statuses/tags) | SharedPreferences ([SharedPrefsCollectionRepository](lib/features/downloads/data/repositories/collection_repository.dart)) | "Tất cả 1080p YouTube videos đã tải" | Existing — giữ nguyên |
| **PlaybackQueue** | Session-scoped, in-memory ordered list | None ([playback_queue_service.dart](lib/features/player/domain/services/playback_queue_service.dart)) | "Đang phát sequence này trong session hiện tại" | Existing — giữ nguyên |
| **Playlist của tôi** | User-curated, ordered, persistent | Drift DB (NEW v16 migration) | "Mix tập gym sáng" — fixed list cá nhân | **NEW** (this PRD) |

**UI separation:**
- Smart Collections → Settings hoặc Filter popover trong download manager (existing UI)
- PlaybackQueue → Player UI panel (existing)
- Playlist của tôi → Tab thứ 2 trong download manager (NEW UI)

→ User KHÔNG nhầm lẫn vì 3 entry points hoàn toàn khác nhau. Không refactor Smart Collections.

### 10.1 Database schema (Drift v16)

```dart
class UserPlaylists extends Table {
  TextColumn get id => text()();           // UUID v4 — portable, future export/sync friendly
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get coverPath => text().nullable()();    // auto từ first item
  IntColumn get itemCount => integer().withDefault(const Constant(0))();
  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override Set<Column> get primaryKey => {id};
}

class UserPlaylistItems extends Table {
  TextColumn get playlistId =>
      text().references(UserPlaylists, #id, onDelete: KeyAction.cascade)();
  // NOTE: Downloads.id là IntColumn autoIncrement (existing schema in
  // app_database.dart:13). FK type MUST match — không phải TextColumn.
  IntColumn get downloadId =>
      integer().references(Downloads, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override Set<Column> get primaryKey => {playlistId, downloadId};
}
```

**Type inconsistency note**: `UserPlaylists.id` dùng `TextColumn` (UUID) trong khi `Downloads.id` là `IntColumn autoIncrement`. Quyết định:
- `UserPlaylists.id` = TextColumn UUID → portable cho future export/sync (không bị conflict khi merge từ multiple devices)
- `UserPlaylistItems.downloadId` = IntColumn → match Downloads existing schema (FK strict)
- `UserPlaylistItems.playlistId` = TextColumn → match UserPlaylists.id

Trade-off acceptable: 2 ID strategies trong DB nhưng mỗi cái phục vụ purpose khác (internal autoIncrement vs portable UUID).

### 10.2 Domain layer

| Entity / Service | Responsibility |
|------------------|----------------|
| `UserPlaylist` (freezed) | Domain entity |
| `UserPlaylistItem` (freezed) | Item with reference |
| `UserPlaylistRepository` | Abstract interface |
| `CreatePlaylist` use case | Tạo + validate name unique |
| `RenamePlaylist` use case | Update name |
| `AddToPlaylist` use case | Bulk add items |
| `RemoveFromPlaylist` use case | Soft remove (file remains) |
| `ReorderItems` use case | Update position field |
| `DeletePlaylist` use case | Cascade delete items |

### 10.3 Tab UI

```
[Tab: Lịch sử tải xuống] [Tab: Playlist của tôi]
─────────────────────────────────────────────────
[+ Tạo playlist] [🔍 Search playlists]

┌─ Playlist Card ─────────────────────────────┐
│ [cover 16:9]  Tên playlist                  │
│               12 mục · 1h 23m · cập nhật 2h │
│               [▶️ Phát] [⋮]                 │
└──────────────────────────────────────────────┘
```

### 10.4 Playlist detail screen

```
← Tên playlist                    [▶️ Phát tất cả] [⋮]
  12 mục · 1h 23m

[+ Thêm video]  [↕️ Sort ▼]

Item rows (drag to reorder):
≡  [thumb] Title / Source / Duration  [▶️] [✕ Remove]
≡  [thumb] ...
```

### 10.5 Player integration

Wire vào [`lib/features/player/`](lib/features/player) hiện có:

- `PlayerNotifier` thêm field `playlistContext: UserPlaylist?`
- Khi play playlist → set queue = items theo position order
- Player UI: thêm Next/Previous buttons khi có playlist context
- "Auto next" toggle (mặc định ON)
- Item kết thúc → auto chuyển item kế

### 10.6 Bulk action wiring

[§9](#9-multi-select-và-bulk-actions) "Thêm vào playlist" → mở `AddToPlaylistMenu`:

```
┌─ Thêm 3 mục vào playlist ──────────────────┐
│ 🔍 Tìm playlist...                          │
│ ─────────────────────────────────────────── │
│ ○ Playlist A (12 mục)                       │
│ ○ Playlist B (5 mục)                        │
│ ○ Playlist C (0 mục)                        │
│ ─────────────────────────────────────────── │
│ + Tạo playlist mới...                       │
│                                              │
│            [Huỷ]  [Thêm vào]                │
└──────────────────────────────────────────────┘
```

### 10.7 Rules

- Remove khỏi playlist ≠ xoá file khỏi máy.
- Xoá playlist không xoá file (warning rõ trong confirm dialog).
- Max 1000 items/playlist (UI warn ở 950).
- Cover image = thumbnail của item position=0.

### 10.8 Effort estimate

| Component | Effort |
|-----------|--------|
| DB v16 migration + DAO | 1.5d |
| Domain + Repository + use cases | 1d |
| Tab + list + detail screens | 2d |
| Create/rename/delete dialogs | 1d |
| Player integration (queue, next/prev) | 2d |
| Bulk action wiring | 1d |
| Test coverage | 1.5d |
| **Total** | **~10d** |

---

## 11. Dialogs

| Dialog | Trigger | File |
|--------|---------|------|
| Search video | Text keyword → CTA "Tìm kiếm" | [youtube_search_sheet.dart](lib/features/youtube_search/presentation/screens/youtube_search_sheet.dart) (tồn tại) |
| Playlist | Playlist URL → CTA "Xem playlist" | [youtube_playlist_sheet.dart](lib/features/youtube_playlist/presentation/screens/youtube_playlist_sheet.dart) (tồn tại) |
| Channel | Channel URL → CTA "Xem kênh" | [youtube_channel_sheet.dart](lib/features/youtube_channel/presentation/screens/youtube_channel_sheet.dart) (tồn tại) |
| Batch | Batch icon hoặc multi-URL paste | Cần tạo mới hoặc reuse existing |
| Preset popover | Click preset dropdown | Cần tạo mới (`PresetPopover`) |
| Delete confirm | Bulk delete hoặc row delete | Reuse existing pattern |
| Create playlist | Bulk action + "Tạo playlist mới" | Cần tạo mới |
| Add to playlist menu | Bulk action "Thêm vào playlist" | Cần tạo mới |

**Note**: Dialog là entry point. Channel dialog có thể navigate sang screen full ([subscriptions_screen.dart](lib/features/youtube_channel/presentation/screens/subscriptions_screen.dart), [channel_video_list_screen.dart](lib/features/youtube_channel/presentation/screens/channel_video_list_screen.dart)) qua link "Xem tất cả →".

Mỗi dialog cần:
- Loading state (spinner + skeleton)
- Empty state (no results / private)
- Error state (network / parse fail) + retry
- Pagination cho list dài

---

## 12. Visual rules

### 12.1 Color tokens

| Layer | Light | Dark |
|-------|-------|------|
| App background | `#F6F8FB` | `#0F172A` |
| Card background | `#FFFFFF` | `#1E293B` |
| Card border | `#E5EAF2` | `#334155` |
| Row hover | `#F8FAFF` | `#1E293B` (lighten 5%) |
| Row downloading | `#F4F8FF` | `#1E3A5F` |
| Row paused | `#F3F4F6` | `#374151` |
| Row failed | `#FFF7F7` | `#3F1F1F` |
| Row cancelled | `#F9FAFB` | `#1F2937` (opacity 70%) |
| Row waitingForNetwork | `#FFFBEB` | `#3F3611` |
| Row postProcessing | `#FAF5FF` | `#3B1E5F` |
| Primary blue | `#0B63F6` | `#3B82F6` |
| Success badge | bg `#DCFCE7`, text `#15803D` | bg `#14532D`, text `#86EFAC` |
| Error badge | bg `#FEE2E2`, text `#B91C1C` | bg `#7F1D1D`, text `#FCA5A5` |
| Warning badge | bg `#FEF3C7`, text `#B45309` | bg `#78350F`, text `#FCD34D` |

### 12.2 Components

- **Nút Tải xuống**: height `48-52px`, min-width `140-156px`, font-weight `600`, no dropdown, primary shadow.
- **Icon History/Batch**: `40x40px`, icon `20px`, tooltip on hover.
- **Preset dropdown**: height match input controls (`44px`), label compact "MP4 · 1080p".
- **Row action**: icon-only `36x36px`, no text. Bulk toolbar: icon + text.
- **Thumbnail**: aspect `16:9`, `120x68px` desktop, duration badge bottom-right, platform badge top-left.

### 12.3 Typography

- App font: system sans-serif.
- Heading: `16px/600`
- Body: `14px/400`
- Metadata: `12px/400` opacity `0.7`
- Button: `14px/600`

### 12.4 Spacing

8px base grid: `4, 8, 12, 16, 24, 32, 48, 64`.

### 12.5 Animation

- Layout transitions: `200ms ease-out-cubic`
- Hover: `100ms ease-out`
- Dialog open/close: `250ms cubic-bezier(0.16, 1, 0.3, 1)`
- Respect `prefers-reduced-motion`

---

## 13. Accessibility

- Mọi icon-only button có `aria-label` + tooltip.
- WCAG AA contrast: text ≥4.5:1, large text/UI ≥3:1.
- Focus state rõ: outline 2px primary, offset 2px.
- Tab order: input → history icon → batch icon → customize icon (⚙️) → preset → CTA → toolbar → rows → right column.
- Enter trong smart input: submit theo CTA hiện tại.
- Esc: đóng popover/dialog hoặc thoát selection mode.
- Screen reader announce dynamic state changes (download progress every 10%, status transition).
- Bulk delete: hard requirement có confirm.
- Reduced motion: tắt animation, transitions instant.

---

## 14. Empty / loading / error states

| State | Copy | Visual | Action |
|-------|------|--------|--------|
| Chưa có lịch sử | "Chưa có video nào được tải. Dán link hoặc mở website để bắt đầu." | Icon `📥` lớn, text center | [Mở trình duyệt] CTA |
| No search results | "Không tìm thấy mục phù hợp. Thử từ khoá khác hoặc xoá bộ lọc." | Icon `🔍`, text | [Xoá bộ lọc] CTA |
| Filter empty | "Không có mục nào khớp bộ lọc hiện tại." | Icon `☰`, text | [Xoá bộ lọc] CTA |
| Parsing link | "Đang phân tích liên kết..." | Spinner trong button | (passive) |
| Unsupported URL | "Website chưa hỗ trợ tải. Bạn có thể mở trong trình duyệt." | Toast warning | [Mở trình duyệt] |
| Download failed | "Không thể tải video. Vui lòng thử lại." | Inline trong row | [Thử lại] icon |
| Network offline | "Mất kết nối. Tải sẽ tự tiếp tục khi có mạng." | Banner top | (passive) |
| Storage warning | "Còn <500MB dung lượng. Vui lòng dọn dẹp." | Banner trong list | [Mở thư mục] |
| Empty playlist tab | "Chưa có playlist nào. Chọn các video đã tải và tạo playlist." | Icon, text | [+ Tạo playlist] |

---

## 15. Acceptance checklist

**Smart input + preset:**
- [ ] Top bar không có Premium + Nâng cấp đồng thời.
- [ ] Không có platform shortcut ở left column.
- [ ] Nút Tải xuống không có dropdown.
- [ ] History/Batch là icon-only, có tooltip.
- [ ] Preset dropdown hiển thị spec dạng "MP4 · 1080p".
- [ ] CTA label đổi theo input type (5 cases ở §4.1).
- [ ] Multi-URL parse đúng theo rule §4.1.
- [ ] Debounce 500ms cho extraction.

**Preset 3-layer:**
- [ ] Per-platform pref override active FormatPreset.
- [ ] 6 built-in FormatPresets seed lần đầu run.
- [ ] Tweak field popover update `currentConfig`, KHÔNG save preset.
- [ ] Active preset thay đổi → reflect ngay trên dropdown label.
- [ ] Rule 3 dùng `EffectiveDownloadConfigService`, không pop dialog.

**Customization access (2 tiers):**
- [ ] Icon `⚙️ Tuỳ chỉnh` trên action bar → mở DownloadConfigDialog one-shot.
- [ ] Icon disabled khi URL chưa valid hoặc đang phân tích.
- [ ] Icon hidden cho channel/search keyword input type.
- [ ] Icon KHÔNG bị disable bởi quota=0 (chỉ Tải xuống button bị block).
- [ ] Toggle "Tuỳ chỉnh chuyên sâu trước khi tải" trong preset popover footer.
- [ ] Toggle ON → label preset dropdown có dấu `*` indicator.
- [ ] Toggle ON → click Tải xuống mở dialog (Rule 3').
- [ ] Per-platform pref vẫn ưu tiên cao hơn toggle (Rule 2 thắng).
- [ ] Click ⚙️ icon override mọi cấu hình khác (Rule 4 highest priority).
- [ ] Per-platform pref auto-save chỉ trigger qua Rule 4 / Rule 3' (existing logic, no code change).
- [ ] Active preset bị xoá → fallback `auto` built-in + clear `currentConfig` + toast.

**Batch context (≥2 URLs):**
- [ ] Default flow: 0 dialog (silent với active preset cho tất cả URL).
- [ ] ⚙️ click với batch input → dialog 1 lần với `defaultApplyToAll=ON`.
- [ ] Tier 2 ON với batch input → dialog 1 lần với `applyToAll=ON`.
- [ ] Section trim disabled trong batch context (grey-out + tooltip).
- [ ] Specific quality picker disabled trong batch context (chỉ auto-match).
- [ ] Warn toast khi uncheck "Apply to all" với `remainingCount > 5`.

**Download manager:**
- [ ] 9 row states đầy đủ với metadata + action + visual.
- [ ] Progress bar chỉ ở downloading/postProcessing.
- [ ] Drag handle chỉ ở queued.
- [ ] Tag chip + watch progress overlay nếu có.
- [ ] Sort dropdown 6 options.
- [ ] Filter icon có badge khi active.
- [ ] Search field hoạt động theo §filtered_downloads_provider.

**Bulk + selection:**
- [ ] Checkbox hide default, hiện khi hover/select mode.
- [ ] Selection toolbar 5 actions (Phát/Thêm playlist/Xoá/Khác/Huỷ).
- [ ] Keyboard shortcuts (§9.5) hoạt động.
- [ ] Delete confirm tách "khỏi lịch sử" vs "khỏi máy".

**Playlist của tôi:**
- [ ] DB migration v16 tạo bảng UserPlaylists + UserPlaylistItems.
- [ ] Tab thứ 2 với create/list/detail flow.
- [ ] AddToPlaylistMenu từ bulk action.
- [ ] Player queue hỗ trợ playlist context (next/prev).
- [ ] Remove từ playlist không xoá file.

**Visual + a11y:**
- [ ] Dark mode tokens cover 9 row states.
- [ ] WCAG AA contrast verified.
- [ ] Reduced motion respected.
- [ ] Tab order match §13.

---

## 16. Mockup states needed

1. Default Home (smart input, plan strip, history list, right column).
2. Preset popover open với profile selector.
3. Selection mode (3 mục selected, bulk toolbar).
4. Playlist tab (list playlists).
5. Playlist detail screen.
6. AddToPlaylistMenu modal.
7. Empty states (no history, filter empty, unsupported URL).
8. Error states (download failed, network offline).
9. Dark mode variants cho default + selection.
10. Loading/skeleton states.

---

## 17. Migration plan (legacy v1.x → v2)

User v1.x đã có data:
- `PlatformQualityPreference` cho nhiều platform
- `FormatPreset` cũ (7 fields)
- Download history với status enum cũ
- SettingsState global defaults

### 17.1 Migration steps (chạy 1 lần khi user upgrade lên v2.0)

1. **DB migration v15 → v16**: tạo bảng `UserPlaylists`, `UserPlaylistItems` (không touch bảng cũ).
2. **FormatPreset DTO migration** (chi tiết §17.2 dưới): convert legacy 7-field records → 15-field new schema.
3. **Seed built-in FormatPresets**: nếu missing built-in IDs (auto, 1080p_mp4, 720p_compact, audio_mp3_320, 4k_max, archive) → seed.
4. **Active preset default**: `active_preset_id = 'auto'` nếu chưa có.
5. **CurrentConfig init**:
   - Nếu user có ≥1 `PlatformQualityPreference`: lấy pref mới nhất (`savedAt DESC`) làm starting `currentConfig`.
   - Else: dùng config của preset "auto".
6. **Translation update**: "Đã hoàn thành" → "Đã tải" trong 5 lang files (vi/en/ja/pt/es).
7. **Show "What's new" dialog** (1 lần) giới thiệu Playlist của tôi.

Migration code: `lib/core/migrations/v2_migration.dart` (mới).

### 17.2 FormatPreset DTO migration (legacy → v2 schema)

Existing FormatPreset records trong SharedPreferences key `format_presets` chỉ có 7 fields ([format_presets_service.dart:8-25](lib/features/settings/data/datasources/format_presets_service.dart:8)):

```
{name, maxResolution, videoCodec, audioCodec, containerFormat, fpsPreference, createdAt}
```

PRD v2 cần 15+ fields (xem §5.3). Migration logic:

```dart
// lib/core/migrations/v2_format_preset_migration.dart
Future<void> migrateFormatPresets(SharedPreferences prefs) async {
  final raw = prefs.getString('format_presets');

  if (raw == null) {
    // First run hoặc chưa có data → seed built-in only
    await _seedBuiltins(prefs);
    return;
  }

  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

  // Skip nếu đã migrate (check schemaVersion)
  if (list.isNotEmpty && list.first['schemaVersion'] != null) {
    appLogger.info('FormatPreset migration: already done, skipping');
    return;
  }

  final migrated = list.map((old) {
    return {
      // === Legacy fields (preserve) ===
      'name': old['name'] as String,
      'maxResolution': old['maxResolution'] as int? ?? 0,
      'videoCodec': old['videoCodec'] as String? ?? 'auto',
      'audioCodec': old['audioCodec'] as String? ?? 'auto',
      'containerFormat': old['containerFormat'] as String? ?? 'mp4',
      'fpsPreference': old['fpsPreference'] as String? ?? 'auto',
      'createdAt': old['createdAt'] as String,

      // === NEW fields with defaults ===
      'id': const Uuid().v4(),               // generate UUID for legacy
      'audioOnly': false,
      'audioBitrate': null,
      'fallbackBehavior': 'nearest',
      'saveLocation': null,                  // null = global default
      'isBuiltIn': false,                    // user-created (built-in seeded separately)
      'subtitlesEnabled': null,              // null = inherit global
      'embedThumbnail': null,
      'embedMetadata': null,
      'embedChapters': null,
      'schemaVersion': 1,                    // future-proof migration tracking
    };
  }).toList();

  await prefs.setString('format_presets', jsonEncode(migrated));
  await _seedBuiltinsIfMissing(prefs, migrated);

  appLogger.info('FormatPreset migration: ${migrated.length} legacy records migrated');
}

Future<void> _seedBuiltinsIfMissing(
  SharedPreferences prefs,
  List<Map<String, dynamic>> existing,
) async {
  const builtinIds = ['auto', '1080p_mp4', '720p_compact', 'audio_mp3_320', '4k_max', 'archive'];
  final existingIds = existing.map((p) => p['id'] as String).toSet();
  final missingBuiltins = builtinIds.where((id) => !existingIds.contains(id));

  if (missingBuiltins.isEmpty) return;

  final updated = [
    ...existing,
    ...missingBuiltins.map(_buildBuiltinPreset),
  ];
  await prefs.setString('format_presets', jsonEncode(updated));
}
```

### 17.3 Backward compatibility

Nếu user downgrade v2 → v1 (rollback hoặc bug):
- v1 `FormatPreset.fromJson` ignore field không biết → no crash
- New fields (audioOnly, isBuiltIn, etc.) bị bỏ qua, behavior fallback về defaults
- DB v16 tables (UserPlaylists, UserPlaylistItems) tồn tại nhưng v1 không touch → safe

→ Forward-compat: v1.x users chạy v2.0 được. Backward-compat: v2.0 users rollback v1.x được (mất Playlist của tôi nhưng không crash).

---

## 18. Telemetry

Events to track (Sentry / internal analytics):

| Event | Properties |
|-------|-----------|
| `preset_changed` | from_id, to_id, source (popover / settings) |
| `preset_field_tweaked` | field, from_value, to_value |
| `preset_created` | source_id (cloned từ), name |
| `download_started` | platform, preset_id, has_per_platform_pref |
| `bulk_action_executed` | action, item_count |
| `playlist_created` | initial_item_count |
| `playlist_played` | item_count, total_duration |
| `dialog_opened` | dialog_type (search/playlist/channel/batch/preset) |
| `dialog_dismissed` | dialog_type, action_taken (boolean) |
| `filter_applied` | filter_type, value |

Privacy: KHÔNG track URL content, chỉ platform identifier.

---

## 19. Performance requirements

- Download history list ≥1000 items: dùng `ListView.builder` virtualization. Render <16ms/frame.
- Search debounce 300ms.
- Filter computation cached (memoize trên FilterState).
- Thumbnail lazy load (CachedNetworkImage với fade-in).
- DB queries indexed: `Downloads.addedAt`, `Downloads.status`, `UserPlaylistItems.position`.
- Smart input debounce 500ms (extraction).
- Animation budget: 200ms max transition.

---

## 20. Out of scope (deferred)

- Cloud sync playlist
- Playlist sharing/export (JSON)
- Smart playlists (auto-add by criteria)
- Per-platform preset variants (TikTok preset vs YouTube preset)
- Audio crossfade trong playlist player
- Drag-drop reorder giữa playlists
- Statistics dashboard (downloads/week, top platforms)
- Voice search
- Browser extension integration
