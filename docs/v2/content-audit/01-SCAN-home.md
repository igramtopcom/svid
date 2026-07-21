# Pass 01 — Home Content SCAN

**Scope**: Toàn bộ text/string user-facing trong feature `lib/features/home/` (30 file Dart) + i18n keys home đang dùng từ `assets/translations/{en,vi}.json`. Svid + VidCombo, macOS + Windows.
**Mục tiêu vòng này**: Phơi bày sự thật content hiện tại — KHÔNG rewrite. Rewrite ở pass sau.
**Pre-condition**: V2 redesign đang chạy (`v2/home-redesign-foundation`). Hyperplan 2F đã chốt 9 phase, Polish phase mới đụng i18n nhưng chỉ ở mức "vi/en 2-lang ship" — KHÔNG audit chất lượng content.

---

## 0. Executive verdict

| Câu hỏi | Trả lời |
|---|---|
| App có content guideline? | ❌ Không |
| Có voice/tone definition per brand? | ❌ Không (dùng chung 1 string cho Svid + VidCombo) |
| Content có được audit? | ❌ Chưa từng |
| Hardcoded strings (bypass i18n)? | ✅ 47 chỗ trong home — bao gồm cả file v2 mới |
| Strings phi lý / sai persona? | ✅ Cả namespace `missionBriefing` (25 keys) — đây là "báo cáo nhiệm vụ" Chairman flag |
| EN ↔ VI parity? | ⚠️ Có gap: 4 chỗ VI = EN (chưa dịch), nhiều chỗ dịch literal làm tệ thêm |
| V2 redesign có lo content? | ⚠️ Chỉ lo "hardcoded leak" + "vi/en overflow" — KHÔNG lo voice/persona/UX |

**Kết luận**: Sự cố "BÁO CÁO NHIỆM VỤ" KHÔNG phải tai nạn lẻ — nó là **biểu hiện của một vibe sai có chủ đích** ("Nocturne Cinematic" → military jargon). Toàn bộ content layer chưa từng được lead bởi tư duy UX writing. Đây là vacancy phải lấp ở V2.

---

## 1. Tổng quan inventory

### 1.1 Home feature — code scope
- **30 file Dart** trong `lib/features/home/` (1 screen + 28 widgets + 1 service stack)
- **195 unique** `AppLocalizations.X` getter được home gọi
- **47 hardcoded strings** bypass i18n (bypass cả EN lẫn VI)

### 1.2 Home content — i18n scope
- **15 locales** trong `assets/translations/` (en, vi, + 13 khác) — mỗi file ~2462 dòng, 2168 keys
- V2 hyperplan chốt **chỉ ship vi+en cho V2**, 13 locales kia parked đến v2.1
- **382 keys** thuộc 16 namespace home-related (home, downloads, batchOps, configDialog, qualityDialog, errorFeedback, contextMenu, common, …)

### 1.3 Source-of-truth pattern
```
assets/translations/{en,vi,…}.json   ← raw key/value (easy_localization)
        ↓ wrapped by
lib/core/l10n/app_localizations.dart  ← static getter façade (3216 dòng)
        ↓ called as
AppLocalizations.someKey              ← in widgets
```

> ⚠ **Anomaly**: vi.json + en.json đều **2462 dòng**, **2168 keys** — bằng nhau exact. Tốt cho parity về structure. Nhưng quality parity = thấp (xem §3).

---

## 2. Critical finding: namespace `missionBriefing` = nguồn gốc "báo cáo nhiệm vụ"

### 2.1 Vị trí

Render bởi **download config dialog** — popup user thấy mỗi lần bấm Download:
- `lib/features/downloads/presentation/widgets/download_config_dialog.dart:511` (title)
- `lib/features/downloads/presentation/widgets/config_quality_panel.dart:308`
- `lib/features/downloads/presentation/widgets/config_preferences_panel.dart:280`

### 2.2 Toàn bộ vocabulary trong namespace này (25 keys)

| key | EN (gốc) | VI (Chairman flag) | UX verdict |
|---|---|---|---|
| `title` | **MISSION BRIEFING** | **BÁO CÁO NHIỆM VỤ** | 💀 Phi lý. User tải video, không phải đặc nhiệm. |
| `targetIntel` | TARGET INTEL | MỤC TIÊU | 💀 "Intel" = jargon quân sự, không liên quan video. |
| `arsenal` | QUALITY ARSENAL | KHO CHẤT LƯỢNG | 💀 "Arsenal" = kho vũ khí. App tải video. |
| `console` | CONFIGURATION CONSOLE | BẢNG ĐIỀU KHIỂN | 🟠 "Console" tone enterprise/IT pro, lạc với user phổ thông. |
| `abort` | ABORT | HỦY BỎ | 🟠 "Abort" = từ NASA/Star Trek. "Cancel" là chuẩn. |
| `initialize` | INITIALIZE DOWNLOAD | KHỞI ĐỘNG TẢI | 🟠 "Initialize" = từ kỹ sư. Người thường nói "Tải". |
| `audioQuality` | AUDIO STREAM | LUỒNG ÂM THANH | 🟠 "Stream" → "Luồng" — user không hiểu "luồng" là gì. |
| `desc4K` | Ultra HD • Cinematic Grade | Siêu nét • Cấp điện ảnh | 🟡 Ổn (so với phần còn lại). |
| `desc...` (FHD/HD/QHD/SD) | … • Standard Pro / Archive Grade / High Frame Rate / Low Bandwidth | … • Tiêu chuẩn / Lưu trữ / Tốc độ cao / Băng thông thấp | 🟡 Đa số kỹ thuật, nhưng ít gây sốc. |
| `extras` | ENHANCEMENTS | NÂNG CAO | 🟢 OK. |
| `format`, `platform`, `chapters`, `subtitles`, `videoQuality`, `videoOnly`, `timeRange`, `sponsorBlock` | … | … | 🟢 Trung tính. |
| `rememberChoice` / `rememberChoiceFor` | Save as default / Save as default for {platform} | Lưu làm mặc định / Lưu làm mặc định cho {platform} | 🟢 OK — đúng tone "save as default". Không khớp với phần còn lại. |

### 2.3 Chẩn đoán

- **Dialog này được "theme-hóa"** theo direction "Nocturne Cinematic" → ai đó cố tạo cảm giác premium-cinematic bằng vocabulary chiến thuật/quân sự.
- **Dịch literal sang VI làm tệ thêm**: EN "Mission Briefing" còn có thể đọc là metaphor; VI "Báo cáo nhiệm vụ" = từ ngữ quân đội nguyên si, **mất hoàn toàn metaphor cinematic**, chỉ còn lại sự khó hiểu.
- **Mâu thuẫn nội bộ namespace**: `missionBriefing.rememberChoice = "Save as default"` đứng cạnh `missionBriefing.title = "MISSION BRIEFING"` → 2 voice khác nhau trong cùng dialog. Người viết không nhất quán.
- **Mâu thuẫn cross-namespace**: Cùng concept "audio stream" được gọi 2 cách:
  - `missionBriefing.audioQuality = "AUDIO STREAM" / "LUỒNG ÂM THANH"` (ở config dialog)
  - `streamSelection.audioTracks = "Audio Streams" / "Luồng Âm Thanh"` (ở advanced stream picker)
  - Nhưng `home.audioOnly = "Audio Only" / "Chỉ Âm Thanh"` (ở quick preset)
  → Cùng 1 thứ, 3 nhãn khác nhau ở 3 nơi, user không biết có liên quan với nhau không.

### 2.4 Đề xuất hướng (chưa rewrite, mới hint)

Dialog này nên đổi voice từ **military RPG** sang **personal media tool**:
- Title: "Tải xuống" hoặc "Tùy chọn tải" (giản dị) — KHÔNG "MISSION BRIEFING".
- Action: "Tải" hoặc "Bắt đầu tải" — KHÔNG "INITIALIZE DOWNLOAD".
- Section: "Chất lượng", "Phụ đề", "Cắt đoạn" — KHÔNG "QUALITY ARSENAL" / "TARGET INTEL".
- Cancel: "Hủy" — KHÔNG "ABORT".

→ Đề xuất chi tiết để pass Rewrite (sẽ làm sau).

---

## 3. Hardcoded strings trong home (47 chỗ) — leak khỏi i18n

### 3.1 Phân loại theo file

| File | Số chỗ | Ngôn ngữ | Loại sai |
|---|---:|---|---|
| `right_panel_item_view.dart` | **18** | VI hardcode | 💀 File V2 mới — toàn bộ panel state chưa qua i18n |
| `download_list_helpers.dart` | 4 | EN hardcode | Snackbar messages |
| `preset_popover.dart` | 6 | VI mix EN | Labels + values trộn |
| `smart_input_bar.dart` | 4 | VI hardcode | Tooltips + hint |
| `home_batch_download_mixin.dart` | 3 | EN hardcode | Status messages khi batch |
| `command_bar_preset_chip.dart` | 4 | EN hardcode (literal "WebM"/"MKV"/…) | Format labels — có thể chấp nhận |
| `download_grouped_image_card.dart` | 3 | EN+VI mix | Tooltip + snackbar |
| `glassmorphism_header.dart` | 1 | EN hardcode | Tooltip "Batch Download (multiple URLs)" |
| `customize_icon_button.dart` | 1 | VI hardcode | Tooltip |
| `home_download_mixin.dart` | 1 | EN hardcode | "Checking premium license. Please try again in a moment." |
| `download_grouped_image_card.dart` | 1 | EN hardcode | "View Images" |
| `preset_popover.dart` | 1 | VI hardcode value | "Downloads/Svid" — leak Svid brand vào VidCombo |

### 3.2 Highlight nguy hiểm

**1. `right_panel_item_view.dart` — V2 component mới, 18 hardcoded VI strings**
```dart
title: 'Đang chờ tải',
title: 'Đang tải xuống · $percent%',
title: 'Đã tạm dừng · $percent%',
subtitle: 'Tiếp tục để tải nốt phần còn lại.',
title: 'Tải xuống thất bại',
title: 'Đã hủy',
subtitle: 'Bạn có thể tải lại từ đầu nếu cần.',
title: 'Tệp không tìm thấy',
title: 'Loại tệp không hỗ trợ phát',
label: 'Hủy', / 'Tạm dừng', / 'Tiếp tục', / 'Thử lại', / 'Xóa', / 'Tải lại', / 'Xóa khỏi danh sách',
```
→ V2 đang dựng mà bypass i18n từ đầu. EN user mở app sẽ thấy text VI nguyên. **Phải fix trước khi V2 ship.**

**2. `preset_popover.dart` — leak Svid brand vào string mặc định**
```dart
const _QuickCustomizeRow(label: 'Vị trí lưu', value: 'Downloads/Svid'),
```
→ Trên build VidCombo, user thấy "Downloads/Svid". Vi phạm `R8 — Hardcoded copy leak Svid context` mà hyperplan 2F đã flag.

**3. `home_download_mixin.dart:1713`**
```dart
message: 'Checking premium license. Please try again in a moment.',
```
→ EN-only string sẽ hiển thị nguyên với user VI. Premium licensing là moment user nhạy cảm — fail i18n ở đây = trust đi xuống.

**4. `home_batch_download_mixin.dart` — 3 EN-only progress messages**
```dart
'Preparing ${urls.length} selected videos...'
'Starting downloads: 0/${extractionResults.length}'
'Starting downloads: $processed/${extractionResults.length}'
```
→ Batch flow user thấy text Anh. Không có VI counterpart.

---

## 4. Patterns of failure — không chỉ "báo cáo nhiệm vụ"

### 4.1 Pattern A: Engineer-vocab leak

VI kỹ thuật / không tự nhiên xuất hiện ở nhiều namespace ngoài missionBriefing:

| key | EN | VI hiện tại | Vấn đề |
|---|---|---|---|
| `streamSelection.audioTracks` | Audio Streams | Luồng Âm Thanh | "Luồng" = engineering. User: "Bài hát" hoặc "Âm thanh". |
| `streamSelection.videoTracks` | Video Streams | Luồng Video | Tương tự. |
| `streamSelection.advancedTitle` | Advanced Stream Selection | Chọn Luồng Nâng Cao | "Chọn luồng" = developer-speak. |
| `streamSelection.comboHint` | yt-dlp will merge the selected video and audio streams using ffmpeg. | yt-dlp sẽ ghép luồng video và âm thanh đã chọn bằng ffmpeg. | Lộ tên tool nội bộ (yt-dlp + ffmpeg) cho user thường. Phi lý cho consumer app. |
| `home.subtitle` | High-performance download manager powered by Rust + Flutter | Trình quản lý tải xuống hiệu suất cao được xây dựng bằng Rust + Flutter | Marketing kỹ thuật. User không quan tâm Rust/Flutter. |
| `home.preferenceSaveFailed` | Failed to save platform preference | Không thể lưu tùy chọn nền tảng | "Tùy chọn nền tảng" → "Lưu chỗ tải mặc định cho YouTube" sẽ thân thiện hơn. |
| `downloads.cdnRefreshSuccess` | Download link refreshed — retrying | Link tải đã được làm mới — đang thử lại | "CDN refresh" trong key, "link tải đã được làm mới" — khá ổn EN/VI nhưng vẫn hơi technical. |
| `downloads.circuitBreakerOpen` | Too many failures for {platform}. Retry in {seconds}s. | Quá nhiều lỗi cho {platform}. Thử lại sau {seconds}s. | Key tên "circuitBreaker" rò vào logic (key OK, value OK). User-facing OK. |

### 4.2 Pattern B: Title Case dại

VI dùng Title Case từng từ — KHÔNG đúng quy tắc tiếng Việt (TV chỉ viết hoa chữ đầu câu/danh từ riêng).

| key | VI hiện tại | Sai ở đâu |
|---|---|---|
| `home.audioOnly` | Chỉ Âm Thanh | Phải là "Chỉ âm thanh" |
| `home.bestQuality` | Chất Lượng Tốt Nhất | Phải là "Chất lượng tốt nhất" |
| `home.browser` | Trình Duyệt | Phải là "Trình duyệt" |
| `home.clearCompleted` | Xóa Đã Hoàn Thành | Phải là "Xóa đã hoàn thành" (vốn cũng vụng câu) |
| `home.clearCompletedTitle` | Xóa Tải Xuống Đã Hoàn Thành | "Xóa các lượt tải đã xong" thân thiện hơn |
| `home.downloadDetails` | Chi Tiết Tải Xuống | "Chi tiết tải xuống" |
| `home.extractionHistoryTooltip` | Lịch Sử Phân Tích | "Lịch sử phân tích URL" hoặc đơn giản "Đã quét" |
| `home.keyboardShortcuts` | Phím Tắt | Phải là "Phím tắt" |
| `home.loginRequired` | Yêu Cầu Đăng Nhập | "Cần đăng nhập" |
| `home.moreSettings` | Cài Đặt Thêm | "Cài đặt khác" |
| `home.popularSites` | Trang Phổ Biến | "Trang phổ biến" |
| `home.quickStart` | Bắt Đầu Nhanh | "Bắt đầu nhanh" |
| `home.recentActivity` | Hoạt Động Gần Đây | "Hoạt động gần đây" |
| `home.recentDownloads` | Tải Xuống Gần Đây | "Tải gần đây" |
| `home.resumeAll` | Tiếp Tục Tất Cả | "Tiếp tục tất cả" |
| `homeBatchDownload.title` | Tải Hàng Loạt | "Tải hàng loạt" |
| `downloads.allDownloads` | Tất Cả Tải Xuống | "Tất cả" |
| `downloads.audioDownloads` | Tải Xuống Âm Thanh | "Âm thanh" hoặc "Audio" |

→ Đây là pattern **lan rộng**. Có hàng chục case như vậy ngoài 19 ví dụ trên. Nguyên nhân: dịch từ EN giữ nguyên capitalization rule.

### 4.3 Pattern C: Inconsistent terminology cho cùng 1 concept

Cùng 1 thứ, app gọi nhiều tên khác nhau:

| Concept | Các nhãn đang dùng | Vấn đề |
|---|---|---|
| Cancel/Abort | `common.cancel = "Hủy"`, `missionBriefing.abort = "HỦY BỎ"`, `qualityDialog.cancel = "Hủy"`, `duplicateDownload.cancel = "Hủy"` | "Hủy" và "HỦY BỎ" là 2 từ — ít nhất phải nhất quán. |
| Download (verb) | `home.startDownload = "Tải xuống"`, `home.download = "Tải xuống"`, `qualityDialog.download = "Tải xuống"`, `missionBriefing.initialize = "KHỞI ĐỘNG TẢI"` | KHỞI ĐỘNG TẢI lệch hẳn. |
| Audio (concept) | `home.audioOnly = "Chỉ Âm Thanh"`, `streamSelection.audioTracks = "Luồng Âm Thanh"`, `missionBriefing.audioQuality = "LUỒNG ÂM THANH"`, `downloads.audioDownloads = "Tải Xuống Âm Thanh"` | 4 cách gọi cho 1 thứ. |
| Quality | `home.bestQuality = "Chất Lượng Tốt Nhất"`, `home.preset.qualityBestAvailable = "Tốt nhất có sẵn"`, `qualityDialog.title = "Chọn Chất Lượng"`, `missionBriefing.arsenal = "KHO CHẤT LƯỢNG"` | "Kho chất lượng" + "Tốt nhất có sẵn" cùng app, user không biết là cùng feature. |
| Pause | `common.cancel`, `home.pauseAll = "Tạm Dừng Tất Cả"`, `downloads.pause = "Tạm dừng"`, `contextMenu.pause = "Tạm dừng"` | OK, nhưng Title Case không đồng bộ. |
| Empty / "no X" | `home.noResultsTitle = "Không tìm thấy tải xuống"`, `home.noCompletedDownloads = "Không có tải xuống đã hoàn thành để xóa"`, `downloads.emptyTitle = "Chưa có tải xuống nào"`, `home.downloads.queueEmpty = "Không có lượt tải đang chạy"` | "Tải xuống" lặp 4 lần khác cấu trúc. |

### 4.4 Pattern D: Emoji trong VI — chưa có policy

Nhiều VI có emoji ngay đầu chuỗi:
- `home.cleared = "✅ Đã xóa {count} tải xuống{plural}"`
- `home.deleted = "✅ Đã xóa {count} tệp{plural} và bản ghi{plural}"`
- `home.downloadStarted = "✅ Đã bắt đầu tải: {title}"`
- `home.pausedAll = "⏸ Đã tạm dừng tất cả tải xuống"`
- `home.resumedAll = "▶ Đã tiếp tục tất cả tải xuống"`
- `home.downloadFailed = "❌ Thất bại: {error}"`
- `home.urlAutoPasted = "✨ URL đã được dán tự động từ clipboard"`
- `home.preferenceSaved = "💾 Đã lưu {quality} làm mặc định cho {platform}"`
- `home.autoDownloading = "⚡ Tự động tải {title} với tùy chọn {platform} đã lưu"`

→ **Có lúc có, có lúc không** — không có rule nào. Nếu giữ emoji thì phải thống nhất per surface (snackbar success luôn ✅, snackbar fail luôn ❌, …) và per brand (Svid OK với emoji ấm; VidCombo Arctic Command có thể không hợp). V2 phải quyết: **all-in** hoặc **all-out**, không nửa vời.

### 4.5 Pattern E: VI = EN (chưa dịch)

| key | VI = EN |
|---|---|
| `contextMenu.markUnwatched` | "Mark as Unwatched" |
| `contextMenu.markWatched` | "Mark as Watched" |
| `contextMenu.redownload` | "Redownload" |
| `converter.activeConversions` | "Active Conversions" |

→ 4 chỗ trong namespace home-related. Toàn bộ vi.json có thể có thêm — chưa scan đủ. Pass sau.

### 4.6 Pattern F: Dịch literal mất nghĩa

| key | EN | VI hiện tại | Vấn đề |
|---|---|---|---|
| `home.subtitle` | High-performance download manager powered by Rust + Flutter | Trình quản lý tải xuống hiệu suất cao được xây dựng bằng Rust + Flutter | Direct word-for-word. |
| `downloads.emptySubtitle` | Paste a URL above to start downloading | Bắt đầu tải xuống từ màn hình Trang chủ | **Hoàn toàn khác nghĩa** — EN nói "paste link ở trên", VI nói "bắt đầu từ Trang chủ". Out of sync với code. |
| `home.downloads.queueEmptySubtitle` | New pending, paused, and in-progress downloads will appear here. | Các lượt đang chờ, tạm dừng hoặc đang tải sẽ xuất hiện tại đây. | OK nhưng nặng nề. |
| `loginRequiredMessage` | Please login to access premium content and private videos. | Vui lòng đăng nhập để truy cập nội dung cao cấp và video riêng tư. | "Cao cấp" có thể cũ; "video riêng tư" nghe lén lút. |

---

## 5. Mapping content → component flow (home only)

| Surface | Component | Content namespace chính | Hiện trạng |
|---|---|---|---|
| App bar / header | `glassmorphism_header.dart` | `home.*` (history, batch, quota), 1 hardcoded EN tooltip | 🟠 1 hardcode + Title Case dại |
| Smart input bar | `smart_input_bar.dart` | `home.urlHint`, `home.pasteTooltip`, … | 💀 4 hardcoded VI tooltips, không dùng i18n |
| URL section header | `home_screen.dart` | `home.sectionLinkOrKeyword` | 🟢 |
| Smart CTA button | `smart_cta_button.dart` | `home.cta.{batchDownload,openBrowser,search,viewChannel,viewPlaylist}` | 🟢 OK |
| Customize icon | `customize_icon_button.dart` | (none — hardcoded 'Tuỳ chỉnh trước khi tải') | 💀 Hardcode VI |
| Preset popover | `preset_popover.dart` | `home.preset.*` | 💀 6 hardcoded VI + leak `Downloads/Svid` |
| Preset chip dropdown | `command_bar_preset_chip.dart` + `preset_dropdown_button.dart` | `home.preset.*` | 🟠 4 format-name hardcodes (chấp nhận được) |
| Quota banner | `home_screen_banners.dart` | `home.quota.*`, `home.requiredUpdate`, `home.updateAvailable`, `home.insufficientSpace` | 🟢 |
| Filter chips | `filter_chips.dart` | `downloadFilter.*`, `downloadStatus.*` | 🟢 |
| Batch ops bar | `batch_operations_bar.dart` | `batchOps.*` | 🟢 OK |
| Downloads list (list/grid/grouped) | `downloads_list.dart`, `download_list_item.dart`, `download_grid_card.dart`, `download_grouped_image_card.dart` | `downloads.*`, `downloadStatus.*`, `contextMenu.*` | 🟠 Mix hardcode EN/VI |
| Right panel state cards (V2 NEW) | `right_panel_item_view.dart` | (none — toàn bộ hardcode VI) | 💀 18 hardcode, file V2 mới |
| Video details modal | `video_details_modal.dart` | TBD (chưa scan sâu) | ⚠️ Chưa kiểm tra |
| Batch URL import dialog | `batch_url_import_dialog.dart` | `homeBatchDownload.*` | 🟢 |
| Search bar | `home_screen.dart` | `home.searchPlaceholder`, `home.clearSearch` | 🟢 |
| Snackbars (success/error) | `home_download_mixin.dart`, `home_batch_download_mixin.dart`, `download_list_helpers.dart`, `download_grouped_image_card.dart` | mix `home.*`, `downloads.*`, `errorFeedback.*` + 11 hardcode EN | 💀 Hardcode + mix EN/VI |
| Empty states | `downloads_list.dart` | `downloads.empty*`, `home.noResults*` | 🟠 emptySubtitle out of sync với code |
| Download config dialog (KHÔNG ở home, nhưng triggered TỪ home) | `downloads/.../download_config_dialog.dart` + `config_quality_panel.dart` + `config_preferences_panel.dart` | **`missionBriefing.*` (25 keys)** | 💀💀 NGUỒN GỐC "BÁO CÁO NHIỆM VỤ" |

---

## 6. Cross-link với V2 redesign hyperplan

| 2F mention | Status | Gap |
|---|---|---|
| Q8: i18n cut 5 lang → 2 lang (vi/en) for V2 | Decided | Quality vẫn chưa audit |
| R4: vi/en overflow risk | Tracked | Cần measure thực tế khi rewrite |
| R8: hardcoded copy leak Svid context | Tracked | **Đã confirm leak: `'Downloads/Svid'` ở `preset_popover.dart`** |
| P1: "Đã hoàn thành" → "Đã tải" | Phase 1B | OK — chỉ là 1 cập nhật. Chưa giải quyết được pattern lớn. |
| Polish §I i18n | 0.5d budget | **0.5d KHÔNG đủ** để rewrite ~382 keys home + audit 2168 keys total. Cần phase riêng. |
| Voice / brand persona / UX writing | **Không tồn tại trong 2F** | ⛔ Vacancy — content session này lấp |

---

## 7. Severity ranking — 7 lớp issue

| Lớp | Mô tả | Ví dụ | Action level |
|---|---|---|---|
| **L1 — Phi lý / sai persona** | Vocabulary lệch hẳn user mental model | "BÁO CÁO NHIỆM VỤ", "KHỞI ĐỘNG TẢI", "MỤC TIÊU INTEL" | 🔴 P0 — phải rewrite trước V2 |
| **L2 — Hardcoded i18n bypass** | String chưa qua localization, bao gồm V2 component mới | 47 chỗ trong home, 18 trong `right_panel_item_view.dart` | 🔴 P0 — phải fix trước V2 |
| **L3 — Brand leak** | "Svid" hardcode rò vào VidCombo build | `'Downloads/Svid'` value | 🔴 P0 — vi phạm R8 |
| **L4 — Inconsistent terminology** | Cùng concept nhiều nhãn | "Cancel/Hủy/HỦY BỎ/Abort" | 🟠 P1 — terminology dictionary giải quyết |
| **L5 — Title Case dại trong VI** | Viết hoa từng từ kiểu Anh | "Chất Lượng Tốt Nhất" | 🟠 P1 — sweep đại trà |
| **L6 — Engineer/marketing leak** | Tên tool, slogan kỹ thuật xuất hiện trong UI | "powered by Rust + Flutter", "yt-dlp will merge … using ffmpeg" | 🟡 P2 — voice rewrite |
| **L7 — VI = EN (chưa dịch)** | Bỏ sót dịch | "Mark as Watched", "Redownload" | 🟡 P2 — sweep dễ |

---

## 8. Đề xuất bước tiếp (vẫn chưa rewrite)

Em đề xuất 5 pass tiếp theo, theo thứ tự:

1. **Pass 02 — VOICE & TERMINOLOGY** (~1d)
   Định nghĩa voice guide + terminology dictionary cho **2 brand × VI/EN = 4 mặt**:
   - Svid voice: thân thiện-cinematic-lite, **không** military jargon. Mượt, ấm, đời thường.
   - VidCombo voice: gọn-utility-clean, không drama, không emoji.
   - Terminology dictionary cho 30 concept phổ biến (download, audio, quality, chapter, …) — chốt 1 nhãn/concept/locale.
   - Capitalization rule: VI = sentence case.
   - Emoji policy: per surface + per brand.
   - Output: `docs/v2/content-audit/02-VOICE.md`

2. **Pass 03 — REWRITE Home content** (~2d)
   Áp voice guide để rewrite toàn bộ 382 keys home + 25 keys missionBriefing. Side-by-side EN/VI per brand.
   - Output: `docs/v2/content-audit/03-REWRITE-home.md`

3. **Pass 04 — KILL hardcoded strings** (~1d)
   Migrate 47 hardcoded strings sang i18n. Gộp với rewrite.
   - Code change: 11 file Dart
   - i18n change: thêm ~50 key mới

4. **Pass 05 — ROLL OUT** (~0.5d)
   - Build + smoke test Svid (mac+win) + VidCombo (mac+win)
   - Soak test EN locale (đảm bảo không VI rò vào)
   - Verify analyze + tests still green

5. **Pass 06 — EXPAND** (sau V2 ship)
   Replicate quy trình cho 14 namespace còn lại của app (settings, browser, player, premium, support, …) → ~1786 keys còn lại.

---

## 9. Open questions cần Chairman quyết

1. **Mission Briefing namespace có giữ vibe military không?**
   Em recommend: **Không** — đổi voice hoàn toàn theo §2.4. Nhưng nếu Chairman muốn giữ "Nocturne Cinematic" tone gắt cho dialog đó, em sẽ giảm cường độ thay vì xóa.

2. **2 brand cùng 1 string vs 2 brand 2 voice?**
   Em recommend: **2 voice riêng** cho user-facing surfaces có brand impact (welcome, premium, marketing copy, missionBriefing equivalent). Common surfaces (button, error, dialog cơ bản) dùng chung. Ratio ~70 chung / 30 brand-specific.

3. **Emoji policy?**
   Em recommend: **all-out cho VidCombo** (Arctic Command — clean utility), **selective cho Svid** (chỉ ở snackbar + onboarding, KHÔNG ở dialog/error/setting).

4. **Title Case sweep (VI)?**
   Em recommend: **Sweep toàn bộ về sentence case**, sửa 1 lần. Chairman OK?

5. **Marketing copy "powered by Rust + Flutter"?**
   Em recommend: **Bỏ** — user thường không quan tâm. Thay bằng tagline ngắn theo brand.

6. **Locale scope cho V2 ship?**
   Hyperplan đã chốt vi+en. Em confirm cũng không cần bung 13 lang còn lại — chúng sẽ tệ hơn nếu rewrite EN+VI mà không sync 13 file kia. Park 13 lang đến v2.1.

---

## 10. Phạm vi mở rộng nếu tiếp tục

Sau khi xong Home (382 keys), 14 namespace còn lại theo độ ưu tiên:

| Namespace | Keys | User-facing impact | Ưu tiên |
|---|---:|---|---|
| `settings*` (~40 sub-namespace) | ~700 | High (user vào nhiều) | P1 |
| `player`, `qualityDialog`, `streamSelection` | ~150 | High (mỗi lần tải đụng) | P0 (gộp với home V2) |
| `premium` | ~50 | High (revenue moment) | P0 |
| `errors`, `errorFeedback`, `notifications` | ~80 | High (trust moment) | P0 |
| `browser` | ~70 | Med | P1 |
| `support`, `bugReport`, `featureRequests`, `rating`, `assistant` | ~80 | Med | P2 |
| `youtube*`, `playbackQueue`, `playlist`, `tags`, `collections` | ~150 | Med | P2 |
| `onboarding`, `csvExport`, `extractionHistory` | ~60 | Low | P3 |
| Còn lại | ~300 | Low | P3 |

---

## Phụ lục A — file dump dữ liệu raw

Side-by-side EN/VI cho 382 home-related keys: `docs/v2/content-audit/_raw_home_strings.md` (tự sinh).

## Phụ lục B — file Dart trong home

30 file (1 screen + 28 widget + 1 service stack), liệt kê đầy đủ ở §5.

---

**Trạng thái pass này**: SCAN xong. KHÔNG rewrite gì hết — chỉ phơi sự thật để Chairman quyết §9.
**Bước tiếp**: Chờ Chairman trả lời 6 open question § 9 → em sẽ vào Pass 02 (Voice & Terminology).
