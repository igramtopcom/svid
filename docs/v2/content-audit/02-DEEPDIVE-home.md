# Pass 02 — Home Content DEEP DIVE

**Triggered by**: Chairman yêu cầu nghiên cứu sâu hơn trước khi rewrite. Pass 01 phơi triệu chứng — Pass 02 đào root cause + tầng vô hình.
**Scope**: Home + cross-namespace evidence (vẫn home-centric, nhưng có dữ liệu hệ thống để hiểu pattern). VI + EN duy nhất.
**Đọc kèm**: `01-SCAN-home.md` (sự thật bề mặt), `_raw_home_strings.md` (raw data), DESIGN.md (visual spec).

---

## 0. Cập nhật mental model

Pass 01 nói: "App đang nói chuyện bằng giọng kỹ sư." → đúng nhưng nông.
Pass 02 phát hiện: **App có 4-5 giọng khác nhau, không nhất quán, không có spec để align** + **có bug active làm vỡ VI**.

Cụ thể tầng vô hình em đào ra ở Pass 02:

1. 🔴 **Voice schizophrenia** — cùng 1 app dùng 4 voice khác nhau, tùy lập trình viên/dialog ai viết khi nào.
2. 🔴 **Plural bug đang hoạt động** trong production — VI user thấy text broken khi count > 1.
3. 🔴 **DESIGN.md không có voice spec** — visual có 304 dòng, voice = 0 dòng. Nguồn gốc voice schizophrenia.
4. 🟠 **211 keys VI = EN** (chưa dịch) — bulk ở `converter` (145), `settingsBinaryComponents` (17), `platforms` (14 — proper noun, OK).
5. 🟠 **229 keys VI dùng Title Case** — pattern lan rộng, không chỉ home.
6. 🟠 **88 keys leak tên tool kỹ thuật** (yt-dlp, ffmpeg, cookie, API) cho user.
7. 🟢 **Pronoun pattern OK** — "bạn" + "Bạn" + "của bạn" = ~67 use, nhất quán. Không có honorific (anh/chị/quý khách). Đây là điểm sáng để giữ.
8. 🟢 **Brand-aware pattern OK** — không có hardcode "SSvid" hay "VidCombo" trong vi.json, dùng `{appName}` 16 chỗ. Code-side mới có 1 leak (`Downloads/SSvid` ở preset_popover) — fix trong Pass 03.

---

## 1. Voice Schizophrenia — chẩn đoán gốc

App hiện đang xài 4-5 voice khác nhau, không có ai chốt voice nào là chính. Em phân loại theo evidence từ string thật:

### Voice A — "Friendly Conversational" (đúng tone cho consumer app)

Xuất hiện ở: onboarding, snackbar success, quota banner, search hint.

| key | text | đặc điểm |
|---|---|---|
| `onboarding.step1Desc` | Dán bất kỳ URL video hoặc âm thanh từ YouTube, TikTok, Instagram, và hơn 1000 trang khác vào thanh tìm kiếm. | Câu hoàn chỉnh, ví dụ cụ thể, chủ động |
| `onboarding.step3Desc` | Theo dõi tiến trình, tạm dừng/tiếp tục, phát file trực tiếp — tất cả ở một nơi. | Liệt kê benefit, gọn |
| `home.urlHint` | Dán link video, playlist, kênh hoặc nhập từ khóa... | Action-first, đời thường ("link" thay vì "URL") |
| `home.quota.remaining` | Bạn còn {count} lượt tải hôm nay | "Bạn" + "lượt tải" — đời thường nhất trong cả namespace |
| `home.urlAutoPasted` | ✨ URL đã được dán tự động từ clipboard | Pattern snackbar "✨/✅ + đã + verb" |

→ **Đây là voice chuẩn**. Nếu áp toàn app sẽ giải quyết 80% vấn đề.

### Voice B — "Engineering Spec" (phổ biến nhất trong app)

Xuất hiện ở: settings, download list labels, format/quality dialog, error messages technical.

| key | text | sai ở đâu |
|---|---|---|
| `app.subtitle` | Trình quản lý tải xuống hiệu suất cao được xây dựng bằng Rust + Flutter | Tagline marketing nói chuyện kiểu kỹ sư khoe stack |
| `streamSelection.audioTracks` | Luồng Âm Thanh | "Luồng" = engineer-speak |
| `streamSelection.comboHint` | yt-dlp sẽ ghép luồng video và âm thanh đã chọn bằng ffmpeg. | Lộ tool name + jargon "luồng" |
| `configDialog.sectionRequiresFFmpeg` | Cần FFmpeg để tải đoạn video. Cài đặt trong Cài đặt → Thành phần nhị phân. | "Thành phần nhị phân" = "Binary Component" dịch literal — user không hiểu |
| `home.preferenceSaveFailed` | Không thể lưu tùy chọn nền tảng | "Tùy chọn nền tảng" abstract |
| `downloads.cdnRefreshSuccess` | Link tải đã được làm mới — đang thử lại | OK ngôn ngữ nhưng concept "CDN refresh" technical |

→ Lý do tồn tại: Người viết string là dev, dịch tên biến/concept code thẳng ra UI mà không reframe.

### Voice C — "Military RPG" (Mission Briefing namespace)

Đã liệt kê đầy đủ ở Pass 01 §2. 25 keys riêng cho download config dialog. Voice này hoàn toàn out of place.

### Voice D — "Title Case English-style" (capitalization mode)

Xuất hiện ở: hầu hết label section/button trong home + downloads + youtubeSearch + binaryUpdate.

229 keys VI Title Case toàn app. Top 25 ở home:

| key | text |
|---|---|
| `home.popularSites` | Trang Phổ Biến |
| `home.openBrowser` | Mở Trình Duyệt |
| `home.recentDownloads` | Tải Xuống Gần Đây |
| `home.clearCompleted` | Xóa Đã Hoàn Thành |
| `home.moreSettings` | Cài Đặt Thêm |
| `home.bestQuality` | Chất Lượng Tốt Nhất |
| `home.audioOnly` | Chỉ Âm Thanh |
| `home.pauseAll` | Tạm Dừng Tất Cả |
| `home.resumeAll` | Tiếp Tục Tất Cả |
| `home.loginRequired` | Yêu Cầu Đăng Nhập |
| `home.extractionHistoryTooltip` | Lịch Sử Phân Tích |
| `home.quickStart` | Bắt Đầu Nhanh |
| `home.keyboardShortcuts` | Phím Tắt |
| `home.recentActivity` | Hoạt Động Gần Đây |
| `home.downloadDetails` | Chi Tiết Tải Xuống |

→ Đây không phải "voice" theo nghĩa từ vựng, mà là **typographic-voice** = cách viết hoa làm chuỗi nặng, formal, không tự nhiên. VI đời thường viết hoa chữ đầu câu/danh từ riêng. Title Case = dịch máy không reformat.

### Voice E — "ALL CAPS DRAMATIC" (Mission Briefing + UI thiểu số)

| key | text |
|---|---|
| `missionBriefing.title` | BÁO CÁO NHIỆM VỤ |
| `missionBriefing.arsenal` | KHO CHẤT LƯỢNG |
| `missionBriefing.targetIntel` | MỤC TIÊU |
| `configDialog.live` | TRỰC TIẾP |

→ ALL CAPS đi kèm vibe quân sự/cinematic. Khi không có spec, ai cũng có thể thêm — và đã thêm.

### Bảng tổng hợp voice schizophrenia

| Voice | Số keys ước lượng | Nên giữ? | Lý do |
|---|---:|---|---|
| A — Friendly Conversational | ~50 (onboarding + snackbar) | ✅ Mở rộng làm voice chuẩn | Đúng persona consumer |
| B — Engineering Spec | ~300+ | 🟡 Reframe sang voice A | Phải, nhưng giữ technical terms ở settings advanced |
| C — Military RPG (missionBriefing) | 25 | ❌ Xóa hoàn toàn | Phi lý cho video downloader |
| D — Title Case | 229 | ❌ Sweep về sentence case | Sai quy tắc tiếng Việt |
| E — ALL CAPS | ~30 | 🟡 Giữ ở banner alert (LIVE, 4K) — bỏ ở title dialog | Có lúc đúng, có lúc sai |

---

## 2. Plural bug — đang hoạt động trong production

### Phát hiện

```dart
// downloads_history_screen.dart:278
final plural = completedCount > 1 ? 's' : '';
// then passed to:
AppLocalizations.homeClearCompletedMessage(completedCount, plural)
// which resolves:
'home.clearCompletedMessage'.tr(namedArgs: {'count': '...', 'plural': plural})
```

### EN behavior

```
EN template: "Delete {count} completed download{plural}?"
count=1, plural=""  → "Delete 1 completed download?"  ✅
count=5, plural="s" → "Delete 5 completed downloads?" ✅
```

### VI behavior 🔴

```
VI template: "Xóa {count} tải xuống đã hoàn thành{plural}?"
count=1, plural=""  → "Xóa 1 tải xuống đã hoàn thành?"  ✅
count=5, plural="s" → "Xóa 5 tải xuống đã hoàn thànhs?" 💀  ← active production bug
```

VI không pluralize bằng "-s" — append "s" vào "thành" cho ra "thànhs" = nonsense. Tương tự cho `cleared`, `deleted`, `clearFailedMessage`.

### Tần suất

Bug trigger ở **mọi thao tác Clear Completed / Clear Failed / Delete batch** khi count > 1. Mỗi lần user dọn list → thấy "thànhs" / "thất bạis" / "tải xuốngs" / "tệps và bản ghis".

### Root cause

`{plural}` placeholder design dựa trên giả định EN. Easy_localization có cơ chế plural built-in (`.plural()` method) nhưng project KHÔNG dùng — tự cobble bằng append "s".

### Fix proposal (Pass 03)

Hai option:
- **Option A (đơn giản)**: Bỏ `{plural}` khỏi VI template, viết câu không phụ thuộc số: `"Xóa {count} mục đã hoàn thành?"` (mục = đếm được, không cần plural)
- **Option B (chuẩn)**: Migrate sang easy_localization plural API:
  ```json
  "clearCompletedMessage": {
    "one": "Delete 1 completed download?",
    "other": "Delete {count} completed downloads?"
  }
  ```
  VI: cùng template — easy_localization sẽ chỉ dùng `other`.

→ Em recommend **Option A** — đơn giản, không phải refactor i18n loader, không animal cho 13 locale tương lai (mỗi locale có rule plural khác).

---

## 3. Vacancy: DESIGN.md không có voice spec

### Phát hiện

DESIGN.md (304 dòng) chứa:
- ✅ Color tokens (5-tier surface ladder, semantic)
- ✅ Typography (Inter vs DM Sans, sizes, weights)
- ✅ Shape (radius per brand)
- ✅ Spacing
- ✅ Elevation strategy
- ✅ Component patterns (TopNav, DownloadItem, URLInput, EmptyState — but only **layout**, không có **copy**)
- ✅ Stitch prompt template (4 brand × theme)
- ✅ Stitch prompting philosophy (creative director, not engineer)
- ❌ **Voice / tone**: 0 dòng
- ❌ **Microcopy guideline**: 0 dòng
- ❌ **Vocabulary**: 0 dòng
- ❌ **Capitalization rule (per locale)**: 0 dòng
- ❌ **Pronoun policy**: 0 dòng

### Hệ quả

- "Nocturne Cinematic" được hiểu thành "military jargon" (missionBriefing) — không có guard rail.
- Mỗi developer viết string theo cảm tính, dẫn đến 5 voice cùng tồn tại.
- Stitch generates UI mockup không có copy spec → AI tự bịa text → developer copy-paste nguyên text Stitch (English title case) sang code.

### Fill the void (Pass 02 deliverable)

Pass 02 chốt 1 phần: extend DESIGN.md với section **"Voice & Microcopy"** — hoặc tách file `VOICE.md` riêng. Em recommend tách file:
- `DESIGN.md` = visual spec (như hiện tại)
- `VOICE.md` = voice/tone/microcopy spec (mới — Pass 03 sẽ tạo)

`VOICE.md` cần chứa:
1. Voice principles per brand (3-5 rule)
2. Tone matrix per surface (button/dialog/error/snackbar/empty/onboarding)
3. Vocabulary canonical list (30 concept × 2 locale × 2 brand = 120 cells)
4. Capitalization rule (VI sentence case, EN sentence case for body / title case for nav/button)
5. Pronoun rule (VI: "bạn"/"Bạn", EN: "you" / no royal "we")
6. Emoji policy (per surface)
7. Plural mechanic (Option A từ §2)
8. Brand-aware mechanic (`{appName}` use rules)
9. Anti-patterns list (cấm "Mission Briefing", "Arsenal", "Initialize", "Abort", …)
10. Stitch prompt addendum (gắn voice spec vào prompt template)

---

## 4. UX absurdity tiers — không chỉ vocabulary

Pass 01 đã list 7 lớp issue. Pass 02 thêm 3 lớp UX deeper:

### Tier U1 — Content nói sai surface

`downloads.emptySubtitle`:
- EN: "Paste a URL above to start downloading"
- VI: "Bắt đầu tải xuống từ màn hình Trang chủ"

→ EN nói "dán link ở trên" (đúng — input bar ngay phía trên empty state). VI nói "đi sang Trang chủ" — **trong khi đây CHÍNH LÀ Home screen**. User VI đọc xong sẽ confused: "Tôi đang ở Trang chủ rồi mà?". Đây là **UX content bug đang sống trong production**.

Có thể có thêm cases tương tự ở các empty state khác — Pass 03 sẽ sweep toàn bộ empty + onboarding khi rewrite.

### Tier U2 — Action message không có hành động

Many error messages chỉ mô tả lỗi, không nói next step:

| key | VI | thiếu gì |
|---|---|---|
| `home.preferenceSaveFailed` | Không thể lưu tùy chọn nền tảng | Làm gì tiếp? Thử lại? Báo lỗi? |
| `home.insufficientSpace` | Không đủ dung lượng đĩa để bắt đầu tải xuống | Cần dọn ổ cứng? Đổi thư mục lưu? |
| `errorFeedback.title.unknown` | Tải xuống thất bại | Thử lại? Báo lỗi? |
| `errorFeedback.hint.networkOffline` | Kiểm tra kết nối mạng và thử lại | OK — có verb "thử lại". Đây là good case. |

→ Pattern fix: error message phải có cấu trúc `[Diagnosis]. [Action verb].`

### Tier U3 — Concept tên đổi giữa các surface (cùng 1 thứ, 4 nhãn)

Thí dụ "Audio" trong home + downloads + missionBriefing + streamSelection:

| Surface | Label VI |
|---|---|
| Quick preset chip | `home.audioOnly` = "Chỉ Âm Thanh" |
| List filter | `downloads.audioDownloads` = "Tải Xuống Âm Thanh" |
| Config dialog section | `missionBriefing.audioQuality` = "LUỒNG ÂM THANH" |
| Advanced stream picker | `streamSelection.audioTracks` = "Luồng Âm Thanh" |

→ User cùng 1 phiên dùng app gặp 4 nhãn khác nhau cho cùng concept. Mental model bị cắt vụn. Fix bằng terminology dictionary canonical (Pass 03).

---

## 5. Cross-namespace evidence — pattern systemwide

### 5.1 Concept name explosion (cross-namespace)

Em scan toàn bộ vi.json:

| Concept | Số label VI khác nhau | Tệ ở đâu |
|---|---:|---|
| download (verb/noun) | 48 | "Tải xuống" / "Tải" / "KHỞI ĐỘNG TẢI" / "Tải hàng loạt" / "Tải Xuống Gần Đây" / … |
| remove/delete | 51 | "Xóa" / "Xoá" / "Bỏ" / "Loại bỏ" / "Dọn dẹp" |
| open | 26 | "Mở" / "Hiện" / "Hiển thị" / "Bật" |
| search | 17 | "Tìm" / "Tìm kiếm" / "Tìm Kiếm" |
| audio | 17 | "Âm thanh" / "Luồng Âm Thanh" / "LUỒNG ÂM THANH" / "Âm thanh nền" / "Âm thanh phổ biến" |
| video | 16 | "Video" / "Đường dẫn Video" / "Chất lượng Video" / "Tải Xuống Video" |
| quality | 15 | "Chất lượng" / "Độ phân giải" / "ARSENAL" / "Tốt nhất có sẵn" |
| cancel/abort | 13 | "Hủy" / "HỦY BỎ" / "Bỏ chọn" / "Bỏ qua" / "Bỏ" |
| save | 9 | "Lưu" / "Lưu trữ" / "Giữ" / "Lưu thành" |
| edit | 6 | "Sửa" / "Chỉnh sửa" / "Đổi" / "Đổi tên" |
| resume | 6 | "Tiếp tục" / "Tiếp" |
| history | 5 | "Lịch sử" / "History" |
| close | 4 | "Đóng" / "Tắt" / "Phím Tắt" (false hit nhưng cho thấy tag matching) |
| retry | 4 | "Thử lại" / "Retry" |
| pause | 2 | "Tạm dừng" |

→ 14 concept top → ~250 label variants. Đây là **terminology debt** lớn nhất của app.

### 5.2 Hệ quả: ngôn ngữ user phải học lại mỗi screen

Mỗi screen user vào, họ phải decode lại "Audio thì lần này gọi là gì?". Đây là chi phí cognitive ẩn — không ai phàn nàn vì nó không phải bug rõ ràng, nhưng mọi người đều cảm thấy app "khó dùng" mà không lý giải được.

### 5.3 Fix qua terminology dictionary (Pass 03)

Output Pass 03 sẽ chốt **30 concept canonical** × 2 locale × 2 brand = 120 cell. Áp lên mọi i18n key, một concept một nhãn (trừ trường hợp legitimate khác nhau context).

Sample (preview, sẽ chốt ở Pass 03):

| Concept | EN canonical | VI canonical (SSvid) | VI canonical (VidCombo) |
|---|---|---|---|
| download (action) | Download | Tải | Tải |
| download (noun) | Download | Lượt tải | Lượt tải |
| audio | Audio | Âm thanh | Âm thanh |
| video | Video | Video | Video |
| quality | Quality | Chất lượng | Chất lượng |
| cancel | Cancel | Hủy | Hủy |
| pause | Pause | Tạm dừng | Tạm dừng |
| resume | Resume | Tiếp tục | Tiếp tục |
| retry | Retry | Thử lại | Thử lại |
| delete | Delete | Xóa | Xóa |
| save | Save | Lưu | Lưu |
| open | Open | Mở | Mở |
| close | Close | Đóng | Đóng |
| search | Search | Tìm kiếm | Tìm kiếm |
| (… 16 more …) |

→ Bỏ "tải xuống" làm gốc — thay bằng "tải" (action) + "lượt tải" (noun đếm được). Lý do: "tải xuống" 3 âm tiết, đời thường người Việt nói "tải video", "tải bài hát". App nên theo.

### 5.4 Engineer/tool leak (88 keys)

Hợp lý ở settings advanced (user pro mới đụng) — nhưng KHÔNG hợp lý ở:
- `configDialog.sectionRequiresFFmpeg` — user thường vào dialog tải video không biết FFmpeg là gì
- `streamSelection.comboHint` — phơi yt-dlp + ffmpeg
- `app.subtitle` — marketing tagline khoe Rust + Flutter
- `home.preferenceSaveFailed` — "tùy chọn nền tảng" mơ hồ
- `home.subtitle` — như app.subtitle

Còn lại 80+ keys ở settings page (apiFallback, autoUpdateBinaries, updateYtdlp, …) là **legitimate** — settings advanced cho power user.

→ Rule cần chốt: **In-flow strings (dialog/snackbar/error/empty mà user thường gặp)** = không bao giờ leak tool name. **Settings strings** = OK nếu user chủ động vào setting đó.

---

## 6. Consumer mental model — khoảng cách app ↔ user

### 6.1 User là ai?

Kiểm tra evidence từ store/marketing/onboarding của các brand này:
- SSvid (ssvid.app) + VidCombo (vidcombo.com): consumer-grade landing, chữ to, CTA "Tải xuống ngay".
- Onboarding step: "Dán URL → chọn chất lượng → tải" — người dùng phổ thông, không phải dev.
- Anti-evidence: missionBriefing voice + Rust+Flutter tagline.

→ **User mental model**: "Tôi muốn lưu cái video này / bài nhạc này về máy. Tôi paste link. App tải về. Xong."

App hiện tại lệch khỏi mental model này ở 3 chỗ:
1. **Download dialog** (missionBriefing) — biến hành động "tải" thành "khởi động nhiệm vụ".
2. **Stream selection advanced** — phơi raw video stream + audio stream + ffmpeg merging.
3. **Settings page** — đầy thuật ngữ kỹ sư (binary component, API fallback, auto throttle, circuit breaker).

Ở 3 chỗ này có 2 hướng:
- **Hide complexity** — gói lại, giữ default thông minh, chỉ expose qua "advanced toggle".
- **Translate jargon** — nếu phải show, dùng ngôn ngữ user hiểu.

→ Pass 03 sẽ áp cả 2: download dialog rewrite + settings page tiered (basic/advanced toggle).

### 6.2 Pronoun consistency — điểm sáng cần giữ

VI app dùng "bạn"/"Bạn"/"của bạn" toàn bộ:
- 30 occurrences "bạn"
- 16 "Bạn" 
- 21 "của bạn"
- 0 occurrences "anh/chị/quý khách/em/mình"
- 5 "tôi" (trong assistant chat — user nói với AI)

→ Pattern: app gọi user là **"bạn"** — neutral, modern, không trang trọng quá. Đây là choice tốt cho consumer app. **Cần giữ**.

→ EN: dùng "you" mặc định (hiện tại OK). Không royal "we" trong UI thường. Trong marketing/onboarding, có thể dùng "we" (we'll remember your preferences, …).

### 6.3 SSvid voice ≠ VidCombo voice — but how different?

Em recommend **70/30 split**:
- 70% strings dùng chung — concept-driven (button labels, error messages, settings, status). Một voice "Friendly Conversational" duy nhất.
- 30% strings có voice riêng:
  - **Onboarding** — SSvid có thể cinematic-warm ("Thư viện video của bạn, ở mọi nơi"); VidCombo gọn-utility ("Tải video nhanh, lưu sạch").
  - **Marketing copy / app subtitle** — SSvid premium-warm; VidCombo direct-clean.
  - **Empty state hero text** — SSvid có thể có dramatic line; VidCombo plain.
  - **Premium upsell** — SSvid emotional appeal; VidCombo feature list.

→ Trong VOICE.md (Pass 03), em sẽ chốt cụ thể list 30% surface nào có brand voice riêng.

---

## 7. Pass 02 → Pass 03 hand-off

Bây giờ em đã có đủ data để vào Pass 03. Pass 03 sẽ deliver:

### 7.1 `VOICE.md` (mới) — voice/microcopy spec
- Voice principles per brand (3-5 rule each)
- Tone matrix per surface
- Pronoun policy
- Capitalization rule
- Emoji policy
- Plural mechanic (Option A)
- Anti-pattern list (no missionBriefing voice, no engineer leak in flow, …)
- Stitch prompt addendum

### 7.2 Terminology dictionary
- 30 concept × 2 locale × 2 brand
- Format: TSV/markdown table — easy to extend

### 7.3 Home content rewrite
- Toàn bộ 382 home-related keys (vi + en)
- Plus 25 missionBriefing keys (sẽ rewrite hoàn toàn — đổi tên namespace từ `missionBriefing` → `downloadOptions`)
- Plus migrate 47 hardcoded strings sang i18n

### 7.4 Phá active bug
- Plural bug ({plural} → câu không phụ thuộc số)
- emptySubtitle out-of-sync (EN/VI rewrite cùng nói "Dán link phía trên...")
- `Downloads/SSvid` brand leak ở preset_popover.dart

---

## 8. Câu hỏi mới phát sinh từ Pass 02

Bổ sung cho 6 câu hỏi Pass 01. Em đã tự trả lời, Chairman confirm:

| # | Câu hỏi | Em recommend |
|---|---|---|
| Q7 | Voice "Friendly Conversational" làm voice chuẩn? | ✅ Yes — extend từ onboarding ra cả app |
| Q8 | Tách `VOICE.md` riêng hay nhét vào DESIGN.md? | Tách riêng — DESIGN visual, VOICE language |
| Q9 | Plural mechanic Option A (câu không phụ thuộc số) hay Option B (easy_localization plural API)? | **Option A** — đơn giản, scale 13 locale tương lai |
| Q10 | Đổi tên namespace `missionBriefing` → `downloadOptions`? | Yes — namespace name cũng nên dễ hiểu cho dev tương lai |
| Q11 | Bỏ tagline "powered by Rust + Flutter"? | Yes — thay bằng tagline brand |
| Q12 | Concept "tải xuống" → "tải" (action) + "lượt tải" (noun)? | Yes — đời thường hơn |
| Q13 | "bạn" pronoun giữ nguyên cho cả 2 brand? | Yes — không cần khác nhau |
| Q14 | 70/30 split common/brand-specific strings? | Yes — em sẽ list 30% surface ở Pass 03 |

---

## 9. Trạng thái

- Pass 01 SCAN: ✅ done (`01-SCAN-home.md`)
- Pass 02 DEEP DIVE: ✅ done (file này)
- Pass 03 VOICE + TERMINOLOGY + REWRITE: ⏳ ready to start sau khi Chairman confirm Q7-Q14

**Em chờ ack** — confirm Q7-Q14 (hoặc veto từng câu) → vào Pass 03 luôn.
