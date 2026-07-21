# Pass 03B — TERMINOLOGY Dictionary

**Vai trò file này**: Canonical từ điển concept của app. Mỗi concept có **đúng 1 nhãn** mỗi locale. Reviewer dùng file này để reject string phát minh synonym mới.
**Quan hệ với VOICE.md**:
- VOICE.md = HOW we speak (tone, structure, register).
- TERMINOLOGY.md = WHAT we call things (vocab, canonical labels).
- Cả 2 đều phải pass khi viết string mới (xem VOICE.md §15.1 decision tree).

**Brand policy**: 100% concept dưới đây dùng **cùng 1 vocabulary** cho cả SSvid + VidCombo (theo VOICE 70/30 rule §5 — concept-level vocab nằm trong 70% shared). Brand differentiation xảy ra ở **sentence structure + diction** (xem VOICE §3-§4), KHÔNG ở word choice.

---

## 0. Tại sao file này tồn tại

Pass 02 §5.1 đo: 14 concept top trong app hiện có ~250 label variant. "Download" có **48 nhãn VI**, "Delete" có **51**, "Audio" có **17**. User cùng 1 phiên dùng app gặp 4 nhãn cho 1 thứ — phải decode lại mỗi screen.

Khi không có TERMINOLOGY.md, mỗi developer viết string mới sẽ phát minh nhãn mới on-the-fly. Sau 30 PR, namespace lại đầy biến thể.

File này đóng cọc tiêu — biết khi nào "đã có nhãn dùng" và khi nào "thực sự là concept mới".

---

## 1. Cách dùng dict này

### Khi viết string mới
1. Concept của string là gì? (download, audio, cancel, …)
2. Tra §3 dưới đây — có rồi → dùng ĐÚNG nhãn đó.
3. Không có → §6 process — request thêm vào dict trước, không phát minh inline.

### Khi review PR
1. Mọi label "verb / noun / status" mới trong i18n value phải match dict.
2. Nếu PR thêm synonym của concept đã có → **reject**, gợi ý dùng nhãn canonical.
3. Nếu PR thực sự cần concept mới → request author add vào dict cùng PR.

### Cách lookup nhanh
- Concept verb (action) → §3.1
- Concept content noun → §3.2
- Concept UI noun → §3.3
- Status badge → §3.4
- Banned synonym list → §4

---

## 2. Scope

**Trong scope**: concept user-facing, xuất hiện ≥3 lần trong app, hoặc concept high-impact (xuất hiện ở button/title/banner).

**Ngoài scope** (KHÔNG cần canonical, đã chuẩn từ nguồn khác):
- Tên brand (SSvid, VidCombo) → resolve qua `{appName}`
- Tên platform (YouTube, TikTok, Instagram, X, Reddit, …) → proper noun, giữ nguyên
- Tên format (MP4, MP3, MKV, WebM, FLAC, M4A) → acronym standard
- Tên resolution (4K, 1080p, 720p, HD, FHD, QHD, UHD) → acronym standard
- Tên codec (H.264, H.265, AV1, AAC, Opus) → acronym standard
- Số (1, 2, 3, …) — không phải concept
- Tên tool nội bộ (yt-dlp, FFmpeg, gallery-dl) → giữ nguyên ở settings advanced (per VOICE P1)

**v2.1 expansion**: Khi unlock 13 locale, file này thêm column cho mỗi locale. Phần "decision" (§5) vẫn EN+VI chốt từ Pass 03B này.

---

## 3. The Dictionary

### 3.1 Action verbs (hành động)

Đây là set **cao tần** nhất — mỗi từ xuất hiện ở button + tooltip + snackbar + context menu.

| Concept | EN canonical | VI canonical | Banned (cấm dùng) | Note |
|---|---|---|---|---|
| download (verb) | Download | **Tải** | Tải xuống, Tải về, Khởi động tải, INITIALIZE DOWNLOAD | "Tải" 2 âm > "Tải xuống" 3 âm. Native VI nói "tải video" |
| upload (verb) | Upload | Tải lên | Đăng lên, Up | App hiện không upload — dự phòng tương lai |
| cancel | Cancel | **Hủy** | Hủy bỏ, Bỏ qua, ABORT, Dừng lại | "Hủy" 1 âm. Industry standard |
| delete (file/record) | Delete | **Xóa** | Xoá (chính tả), Xóa bỏ, Loại bỏ, Hủy bỏ | "Xóa" — UNICODE ó (`ó`), không "Xoá" (`ô`) |
| remove (from list) | Remove | **Xóa khỏi danh sách** (long) / **Bỏ** (short) | Xóa (gây nhầm với delete vĩnh viễn), Loại bỏ | Phân biệt: delete = mất file; remove = chỉ ẩn khỏi UI |
| clear (sweep) | Clear | **Dọn** (verb) / **Xóa hết** (button) | Làm sạch, Xóa tất cả | Clear ≠ Delete — clear là sweep nhiều, không phá hủy file |
| pause | Pause | **Tạm dừng** | Tạm ngừng, Tạm hoãn, Dừng | |
| resume | Resume | **Tiếp tục** | Tiếp, Khôi phục, Tiếp tục lại | |
| stop | Stop | **Dừng** | Ngừng, Hủy | Stop = full stop, not pause. Hiếm dùng — usually "Hủy" hoặc "Tạm dừng" |
| retry | Retry | **Thử lại** | Làm lại, Lặp lại, Retry | |
| save | Save | **Lưu** | Lưu trữ (= archive), Giữ | "Lưu trữ" reserved cho "archive" |
| save as default | Save as Default | **Lưu làm mặc định** | Đặt làm mặc định, Lưu mặc định | |
| open | Open | **Mở** | Khởi chạy, Bật | "Bật" reserved cho toggle on/off |
| close | Close | **Đóng** | Tắt, Thoát | "Tắt" reserved cho toggle off; "Thoát" reserved cho exit app |
| edit | Edit | **Sửa** | Chỉnh sửa, Chỉnh, Đổi | "Đổi" reserved cho rename/swap |
| rename | Rename | **Đổi tên** | Sửa tên, Đặt lại tên | |
| search | Search | **Tìm kiếm** (verb) / **Tìm** (label) | Tra cứu | "Tìm" cho button label ngắn; "Tìm kiếm" cho placeholder |
| share | Share | **Chia sẻ** | Gửi, Chia | |
| copy | Copy | **Sao chép** | Chép, Copy | |
| paste | Paste | **Dán** | Paste | |
| move | Move | **Di chuyển** | Chuyển | |
| select all | Select All | **Chọn tất cả** | Chọn hết | |
| deselect all | Deselect All | **Bỏ chọn** | Hủy chọn, Bỏ chọn tất cả | "Bỏ chọn" gọn — context multi-select rõ |
| login | Log In | **Đăng nhập** | Sign in, Login | |
| logout | Log Out | **Đăng xuất** | Thoát, Sign out | |
| sign up | Sign Up | **Đăng ký** | Register, Tạo tài khoản | |
| upgrade | Upgrade | **Nâng cấp** | Mua, Mua premium | "Nâng cấp" = upgrade tier; "Mua" = generic purchase |

### 3.2 Content nouns (đối tượng)

| Concept | EN canonical | VI canonical | Banned | Note |
|---|---|---|---|---|
| video | Video | **video** | clip, đoạn phim, phim | Sentence case in VI by default |
| audio (noun) | Audio | **âm thanh** | nhạc, sound, luồng âm thanh | "Nhạc" = music specifically |
| image | Image | **ảnh** | hình, hình ảnh, picture | "Ảnh" gọn nhất, native VI |
| subtitle | Subtitle | **phụ đề** | sub, caption | |
| chapter | Chapter | **chương** | đoạn, phần | |
| playlist | Playlist | **playlist** | Danh sách phát, danh sách | Loanword native cho VN tech audience |
| channel | Channel | **kênh** | Kênh youtube, channel | |
| URL / link | Link | **link** | URL (cho user-facing), Đường dẫn | URL OK ở placeholder technical ("Dán URL"), nhưng "link" canonical |
| file | File | **file** | Tệp, tệp tin, document | Industry consumer tech: "file". "Tệp" reserved cho legal/formal |
| folder | Folder | **thư mục** | Folder, directory | |
| download (noun, item) | Download | **lượt tải** | Bản tải, mục tải, item tải | "Lượt" = countable instance |
| download (collection) | Downloads | **danh sách tải** | Lịch sử tải, các tải xuống | When referring to UI list |
| collection | Collection | **bộ sưu tập** | Bộ, sưu tập | |
| favorite | Favorite | **yêu thích** | Ưa thích, đã thích | |
| watched / unwatched | Watched / Unwatched | **đã xem / chưa xem** | (status, not action) | |
| keyword | Keyword | **từ khóa** | Tag, key | "Tag" reserved cho user-applied tag |

### 3.3 UI nouns (interface)

| Concept | EN canonical | VI canonical | Banned | Note |
|---|---|---|---|---|
| settings | Settings | **cài đặt** | Tùy chỉnh, thiết lập, cấu hình | |
| options (download dialog) | Options | **tùy chọn** | Cấu hình, Tham số | Used for dialog title (vs "Mission Briefing") |
| preferences | Preferences | **tùy chọn** | Sở thích, ưa thích | Cùng nhãn với options. Phân biệt qua context. |
| default (noun) | Default | **mặc định** | Ngầm định, mặc nhiên | |
| history | History | **lịch sử** | Quá khứ, Past | |
| queue | Queue | **hàng đợi** | Hàng chờ, Danh sách chờ | Industry standard |
| filter | Filter | **bộ lọc** | Lọc, filter | |
| sort | Sort | **sắp xếp** | Phân loại, sort | |
| search bar | Search Bar | **thanh tìm kiếm** | Ô tìm kiếm | |
| URL input | URL Input | **ô nhập link** | Ô URL, ô địa chỉ | |
| dialog | Dialog | **hộp thoại** | Cửa sổ, popup | |
| menu | Menu | **menu** | Trình đơn (formal too), thực đơn | "Menu" loanword industry standard |
| button | Button | **nút** | Button, ô bấm | |
| tab | Tab | **tab** | Thẻ, ngăn | "Tab" loanword industry standard |
| section | Section | **mục** | Phần, đoạn, khu vực | "Mục" gọn |
| panel | Panel | **bảng** | Khung, panel | |
| sidebar | (not applicable — VOICE banned: NO sidebar in app) | — | — | App không có sidebar (DESIGN.md) |
| top bar / nav | Top Bar | **thanh trên** | Header, top nav | |
| toolbar | Toolbar | **thanh công cụ** | Bar | |
| tooltip | Tooltip | **chú thích** | Hint, tooltip | (i18n key tên giữ nguyên "tooltip", display label = "chú thích") |
| notification | Notification | **thông báo** | Notify | |
| badge | Badge | **huy hiệu** | Tag, nhãn (= label) | Phân biệt: badge = state indicator nhỏ; label = text descriptor |
| label | Label | **nhãn** | Tag | |
| tag (user-applied) | Tag | **tag** | Nhãn (= label), thẻ | Loanword for user feature |
| empty state | Empty State | **trạng thái trống** | (UI dev term, ít user-facing) | |
| toggle | Toggle | **bật/tắt** | Toggle, switch | "Bật/tắt" pair, không single |
| dropdown | Dropdown | **menu xổ xuống** | Dropdown, danh sách thả | |
| keyboard shortcut | Keyboard Shortcut | **phím tắt** | Tổ hợp phím | |

### 3.4 Status badges (state)

Status thường xuất hiện ở badge/chip + filter chip + list item right-side. ≤2 từ. Sentence case.

| Concept | EN | VI | Banned | Note |
|---|---|---|---|---|
| pending | Pending | **Đang chờ** | Chờ xử lý, queued (different) | |
| queued | Queued | **Trong hàng đợi** / **Đang chờ** | Pending (different) | "Queued" hiếm, có thể merge với pending |
| extracting / scanning URL | Scanning | **Đang quét** | Đang trích xuất, Đang phân tích, Trích xuất | "Quét" gần user mental model nhất |
| downloading | Downloading | **Đang tải** | Đang tải xuống, Tải | |
| paused | Paused | **Đã tạm dừng** / **Tạm dừng** | Pause, Đang tạm dừng | Status vs action verb — same word |
| resumed | (action complete event, không phải status persistent) | — | — | Use snackbar message, not badge |
| completed | Completed | **Đã xong** | Đã hoàn thành (ổn nhưng dài), Hoàn tất, Done | "Đã xong" 2 âm, gọn nhất, native VI |
| failed | Failed | **Thất bại** | Lỗi, Không thành công | |
| cancelled | Cancelled | **Đã hủy** | Hủy, Đã hủy bỏ | |
| converting | Converting | **Đang chuyển đổi** | Convert, Đang convert | |
| post-processing | Post-processing | **Đang xử lý cuối** | Post-process, Đang xử lý | |
| waiting for network | Waiting for Network | **Chờ mạng** | Đợi mạng, Chờ kết nối | |
| not on Wi-Fi | Not on Wi-Fi | **Chưa có Wi-Fi** | Không có Wi-Fi (= "no Wi-Fi" stronger) | |
| live | LIVE | **TRỰC TIẾP** | Live, Đang live | ALL CAPS legitimate cho status badge ≤4 ký tự (VOICE §7.1 §8.1) |

### 3.5 Quantity / number contexts

| Concept | Pattern EN | Pattern VI |
|---|---|---|
| count of items (1) | "{count} download" or "1 download" | "{count} lượt tải" hoặc "1 lượt tải" |
| count of items (count) | "{count} downloads" / "{count} download(s)" | "{count} lượt tải" (count-neutral, không pluralize) |
| count selected | "{count} selected" | "Đã chọn {count}" hoặc "{count} đã chọn" |
| count remaining | "{count} left" / "{count} remaining" | "Còn {count}" / "Còn lại {count}" |
| quota remaining | "{count} downloads left today" | "Còn {count} lượt tải hôm nay" |
| time remaining | "{time} remaining" | "Còn {time}" |
| size | "{size}" (e.g., "120 MB") | "{size}" (cùng) |
| speed | "{speed}/s" | "{speed}/s" |
| views | "{count} views" (1k pluralize OK) | "{count} lượt xem" |
| views thousands | "{count}K views" | "{count}K lượt xem" |
| views millions | "{count}M views" | "{count}M lượt xem" |

→ Notice: VI count pattern = neutral (không pluralize). Nhất quán với VOICE §10 plural mechanic Option A.

---

## 4. Banned synonyms — explicit reject list

Khi reviewer thấy các nhãn dưới đây trong PR mới → **reject + gợi ý canonical**.

### 4.1 VI banned synonyms

| Banned | Canonical thay thế | Lý do |
|---|---|---|
| Tải xuống (verb in button) | Tải | 2 âm vs 3, native shorter |
| Tải về | Tải | Same |
| Khởi động tải / Khởi tạo tải | Tải | VOICE P1 banned engineer verb |
| Hủy bỏ | Hủy | 1 âm vs 2, no need formality |
| Bỏ qua (cho cancel) | Hủy | "Bỏ qua" = skip, different concept |
| Loại bỏ | Xóa hoặc Bỏ | Heavy, formal |
| Xoá (with `á`) | Xóa (with `ó`) | Spelling — Unicode `ó`. Audit: hiện tại có 2 mix, sweep tất cả về "Xóa" |
| Tạm ngừng | Tạm dừng | Industry consumer standard |
| Tạm hoãn | Tạm dừng | Formal/legal feel |
| Khôi phục (cho resume) | Tiếp tục | "Khôi phục" = restore, different |
| Lưu trữ (cho save) | Lưu | "Lưu trữ" reserved cho archive |
| Lưu lại | Lưu | Redundant "lại" |
| Bật (cho open) | Mở | "Bật" reserved cho toggle on |
| Tắt (cho close window) | Đóng | "Tắt" reserved cho toggle off |
| Khởi chạy | Mở | Engineer verb |
| Chỉnh sửa | Sửa | Redundant compound |
| Tệp / Tệp tin (consumer surface) | file | Formal/government feel — keep "tệp" only ở legal |
| Hình ảnh | ảnh | 2 âm vs 1, native shorter |
| Đường dẫn | link | Engineer translate of URL |
| Cấu hình | tùy chọn / cài đặt | Heavy enterprise jargon |
| Tham số | (rephrase entirely) | Engineer term |
| Thiết lập | cài đặt | Synonym, less common |
| Trình đơn | menu | Formal/dated |
| Thực đơn | menu | Formal/dated |
| Cửa sổ | hộp thoại / dialog | Old Windows-translation |
| Trình duyệt internet | trình duyệt | Redundant |
| Đã hoàn thành (status badge) | Đã xong | "Đã xong" 2 âm gọn hơn cho badge |
| Đã hoàn tất | Đã xong | Same |
| Hoàn tất | Đã xong | Same |
| Đang trích xuất | Đang quét | Engineer verb |
| Đang phân tích (cho extract) | Đang quét | Closer to user mental model |
| Trích xuất thông tin | Đang quét link | Engineer phrase |
| Luồng (cho stream) | (rephrase via concept) | VOICE banned per §13.1 |
| Nhị phân / Thành phần nhị phân | công cụ | VOICE banned |
| Bảng điều khiển | tùy chọn / cài đặt | VOICE banned |
| Báo cáo nhiệm vụ / Nhiệm vụ / Tác vụ | tùy chọn tải / lượt tải | VOICE banned |
| Mục tiêu / Target | (rephrase) | VOICE banned (military) |
| Kho / Arsenal | (rephrase) | VOICE banned (military) |

### 4.2 EN banned synonyms

| Banned | Canonical | Lý do |
|---|---|---|
| Initialize Download | Download (or Save) | VOICE P1 |
| Abort | Cancel | VOICE P1 |
| Mission Briefing | Download Options | VOICE §13.1 |
| Target Intel | (rephrase) | VOICE §13.1 |
| Quality Arsenal | Quality (section title) | VOICE §13.1 |
| Configuration Console | Settings | VOICE §13.1 |
| Click here | (action verb directly) | Generic CTA, lazy writing |
| Are you sure? | Specific question ("Delete this?") | Lazy confirm body |
| Submit (for download) | Download | "Submit" enterprise feel |
| Execute | Run / Start | Engineer verb |

---

## 5. Decision notes — debate per concept (only non-obvious)

Concept obvious (download = tải, audio = âm thanh) skip. Concept dưới đây em đã debate — record để tương lai khỏi reopen.

### 5.1 file vs tệp

**Choice: `file`.**

Evidence:
- Zalo: "tệp" (corporate VN messaging)
- Tiki: "file" (consumer e-commerce)
- Apple VN: "tệp" (formal Apple translate convention)
- Google Drive VN: "tệp"
- Notion VN: "file"
- Industry tech consumer (Spotify, Discord, Telegram VN): "file"

Trade-off:
- `tệp` = native VN, formal, government-doc feel.
- `file` = loanword, informal, gọn, hằng ngày tech user.

Decision rationale: SSvid + VidCombo target consumer tech audience (younger, mobile-first, English-comfortable). "File" gần user mental model hơn "tệp". Reserve "tệp" cho legal/ToS context.

### 5.2 link vs URL vs đường dẫn

**Choice: `link` canonical, `URL` allowed in technical placeholder context, `đường dẫn` banned.**

Evidence:
- "Dán đường dẫn" sounds engineer-ese (translate of "paste URL").
- "Dán link" = how Vietnamese actually say in everyday speech.
- "URL" OK trong technical microcopy ("URL không hợp lệ" — terse error). Nhưng button/empty state CTA dùng "link" mượt hơn ("Dán link đầu tiên").

Pattern application:
- ✅ "Dán link video" (action prompt)
- ✅ "URL không hợp lệ" (error — terse)
- ❌ "Dán đường dẫn" (engineer)
- ❌ "Sao chép đường dẫn" → "Sao chép link" hoặc "Sao chép URL"

### 5.3 Đã xong vs Đã hoàn thành vs Hoàn tất

**Choice: `Đã xong`.**

Evidence:
- Status badge phải ≤2 từ (VOICE §9.1). 2 âm vs 4 âm: "Đã xong" win.
- Native VI: "Xong rồi", "Đã xong" — hằng ngày.
- "Đã hoàn thành" = formal, doc-feel.
- "Hoàn tất" = báo chí, formal.

Application:
- ✅ Badge: "Đã xong"
- ✅ Snackbar: "Đã tải xong" (verb form)
- ❌ Snackbar: "Đã hoàn thành tải xuống" (formal + dài)

### 5.4 Đang quét vs Đang trích xuất vs Đang phân tích

**Choice: `Đang quét` cho status, `Đang quét link` cho long form.**

User mental model: paste link → app "scans" the link → returns video info.
- "Trích xuất" = engineer term ("extract metadata") — không tự nhiên VI.
- "Phân tích" = analyze — too abstract.
- "Quét" = scan — native VI verb, dễ hiểu, user nói "quét mã QR" / "quét virus".

Application:
- ✅ Status badge: "Đang quét"
- ✅ Long form: "Đang quét link..." / "Đã quét xong"
- ❌ "Đang trích xuất thông tin..." (engineer)

### 5.5 lượt tải vs bản tải vs mục tải

**Choice: `lượt tải`.**

"Lượt" = countable instance ("lượt xem", "lượt thích", "lượt tải") — match how user counts mental model.
- "Bản tải" = copy — confusing với version copy.
- "Mục tải" = item — UI dev term, abstract.
- "Lượt tải" = native countable.

Application:
- ✅ "Bạn còn 5 lượt tải hôm nay"
- ✅ "Đã tải xong 5 lượt"
- ⚠ "Đã tải xong 5 file" cũng OK — phụ thuộc context (file vs lượt tải).

### 5.6 hàng đợi vs danh sách chờ

**Choice: `hàng đợi`.**

- VN tech industry: "hàng đợi" (Zalo download queue, Spotify "hàng đợi", iTunes "hàng đợi"). Established standard.
- "Danh sách chờ" = waitlist, different concept.

### 5.7 Đang tải vs Tải xuống (status badge)

**Choice: `Đang tải`.**

Status badge = present continuous. "Đang" = `-ing` marker.
- ✅ "Đang tải" (active state)
- ❌ "Tải xuống" (verb infinitive, không phải state)

### 5.8 Tạm dừng (status) vs Tạm dừng (action verb)

**Same word, different placement.**

VI tense system không phân biệt verb/state form rõ như EN.
- Action button: "Tạm dừng" (verb)
- Status badge: "Đã tạm dừng" (state — "đã" prefix marks completed action turning into state)

→ Khác nhau ở "Đã" prefix. Status có "Đã", action không.

### 5.9 ảnh vs hình vs hình ảnh

**Choice: `ảnh`.**

3 lựa chọn đều dùng được trong VI everyday.
- "ảnh" 1 âm — gọn nhất, fit length VOICE §9.
- "hình" 1 âm — nhưng ambiguous (= shape).
- "hình ảnh" 2 âm — formal + redundant compound.

Application:
- ✅ "Tải ảnh" / "Tải xong ảnh" / "Ảnh từ Instagram"
- ❌ "Tải hình ảnh từ Instagram"

### 5.10 settings vs preferences vs options vs configuration

**Choice: `cài đặt` cho settings (top-level menu), `tùy chọn` cho options/preferences (in-flow dialog).**

Mapping:
- `settings` (app-level menu, `/settings`) → "Cài đặt"
- `preferences` (user prefs in settings) → "Tùy chọn của bạn" hoặc gộp luôn vào "Cài đặt"
- `options` (download dialog title, missionBriefing replacement) → "Tùy chọn tải"
- `configuration` → BANNED (VOICE §13.1)

Difference between "cài đặt" và "tùy chọn":
- "Cài đặt" = global app settings
- "Tùy chọn" = local choice in flow (download options, format options)

### 5.11 menu vs trình đơn vs thực đơn

**Choice: `menu`.**

VN industry consumer apps đều dùng "menu" (loanword). "Trình đơn" / "Thực đơn" = dated 2000s VN translation, không còn dùng.

### 5.12 deselect vs uncheck

**Choice: `Bỏ chọn`.**

"Hủy chọn" = engineer-flavored. "Bỏ chọn" = native VI, parallel với "Chọn".

---

## 6. Adding a new concept — process

### 6.1 Khi nào "thực sự là concept mới" vs "nhãn đã có"

Trước khi propose concept mới:
1. Tra §3 — concept đã có trong list?
2. Concept có rồi nhưng surface khác? → vẫn dùng nhãn cũ. Pattern variation ở structure (VOICE §12), KHÔNG phát minh nhãn.
3. Concept thực sự khác semantically (e.g., "archive" vs "delete" vs "remove")? → mới có thể là concept mới.

### 6.2 PR template thêm concept mới

```markdown
## Concept new: <name>

**EN canonical**: <label>
**VI canonical**: <label>

**Surface usage**: where will this appear (button/dialog/error/...)?
**Why not existing concept**: how does this differ from <existing>?
**Banned synonyms**: list synonyms reviewers should reject.
**Sample usage**:
- EN: "<example sentence>"
- VI: "<example sentence>"
```

→ Add row vào §3 section tương ứng + add banned synonyms vào §4.

### 6.3 Khi nào DEPRECATE 1 nhãn

Nếu sau audit định kỳ phát hiện 1 nhãn canonical không còn hợp:
1. Open PR thay nhãn cũ → nhãn mới.
2. Update §3 + §4 + §5 (decision note tại sao đổi).
3. Sweep i18n + dart code thay tất cả case.
4. Migrate trong 1 PR atomic — không split.

---

## 7. Brand-shared vs brand-specific decision

### Recap (đã chốt VOICE §5)

**100% concept dictionary §3 = brand-shared.** Vocabulary cùng. Brand differentiation ở **sentence structure + diction at sentence level** (xem VOICE §3.5 + §4.5).

### Tại sao không brand-specific vocab?

Em cân nhắc 1 vài case:
- "lượt tải" (warm) vs "lượt" (utility) — drop noun?
- "đã xong" vs "xong"

Verdict: **không brand split vocab.**
- Lý do 1: Maintainability — split vocab = double the dictionary, gấp đôi reviewer load.
- Lý do 2: User cross-brand familiarity — power user dùng cả SSvid + VidCombo (free + premium scenario) sẽ confused nếu vocab khác.
- Lý do 3: Brand voice differentiation hiệu quả qua sentence form (xem VOICE Do/Don't tables) — không cần qua vocab.

### Brand differentiation thực sự xảy ra ở đâu

Không trong dict. Trong:
- Tagline (VOICE §3.4 + §4.4)
- Empty state hero (SSvid emotional / VidCombo factual)
- Onboarding tone (SSvid evocative / VidCombo direct)
- Snackbar emoji presence (SSvid selective / VidCombo none)
- Pronoun retention (SSvid keep / VidCombo selective drop)

Tất cả với cùng vocab. → Brand voice = "khẩu khí" mà không phải "từ vựng".

---

## 8. Coverage stats

### 8.1 Concept coverage

- §3.1 actions: **27 verb concepts**
- §3.2 content nouns: **15 concepts**
- §3.3 UI nouns: **22 concepts**
- §3.4 status badges: **13 status concepts**
- §3.5 quantity patterns: **10 patterns**

**Total: ~87 concept entries**.

### 8.2 Banned synonym coverage

- §4.1 VI banned: **30 entries**
- §4.2 EN banned: **10 entries**

**Total: 40 banned synonyms documented**.

### 8.3 Audit signal — concept coverage vs codebase

Pass 02 §5.1 đo "delete" có 51 label variant trong codebase. Sau khi áp dict này:
- Delete (file) → "Xóa" (1 label)
- Remove (from list) → "Xóa khỏi danh sách" / "Bỏ" (2 label, semantically different)
- Clear (sweep) → "Dọn" / "Xóa hết" (1 concept, 2 surface form)
- Deselect → "Bỏ chọn" (1 label)

→ 51 label biến thể → ~5 label thực sự cần. **Rút ~90% redundancy** chỉ riêng "delete-class".

Ước lượng tương tự cho 14 concept top: 250 → ~50 label thực. **Áp dict này = giảm ~80% terminology debt.**

---

## 9. Khi nào dict này KHÔNG dùng

3 trường hợp:
1. **Settings advanced page** — cho phép technical term per VOICE P1 ngoại lệ. "Dự phòng API" / "Codec H.264" / "Cache CDN" hợp pháp ở settings advanced.
2. **Legal / Terms of Service / Privacy Policy** — register pháp lý riêng. "Tệp" / "Đường dẫn" / "Chấm dứt" có thể dùng.
3. **Developer-facing strings** (debug log, error trace, telemetry) — không user-facing, không pass dict.

---

## 10. Trạng thái + bước tiếp

- ✅ Pass 03A VOICE.md — chốt
- ✅ Pass 03B TERMINOLOGY.md — file này, chốt
- ⏳ Pass 03C — apply (rewrite home keys + fix bugs + kill hardcoded). Em đi tiếp.

**KHÔNG có open question cho Chairman ở Pass 03B** — tất cả debate đã argue + chốt trong §5. Chairman chỉ ack-by-default nếu không phản đối.

**Pass 03C sẽ deliver**:
1. Rewrite 382 home-related i18n keys (vi + en) — apply VOICE.md + TERMINOLOGY.md.
2. Rewrite 25 missionBriefing keys → đổi tên namespace `missionBriefing` → `downloadOptions`, áp voice mới.
3. Migrate 47 hardcoded strings → i18n.
4. Fix plural bug — bỏ `{plural}` literal append, dùng pattern Option A.
5. Fix `downloads.emptySubtitle` semantic mismatch.
6. Fix `'Downloads/SSvid'` brand leak ở `preset_popover.dart`.
7. Sweep 229 Title Case → sentence case.
8. Replace tagline "powered by Rust + Flutter" → SSvid "Tải video. Đơn giản. Đẹp." / VidCombo "Tải nhanh. Lưu sạch."
9. Verify build SSvid + VidCombo, mac + win, en + vi.

---

**Reminder**: Khi áp dict này (Pass 03C), nếu phát hiện concept code-side mà §3 chưa cover → STOP, add vào §3 trước, KHÔNG tự đặt nhãn inline trong PR rewrite.
