# Svid Home / Download Manager UI Spec

**Version:** Draft v1.0  
**Date:** 2026-05-04  
**Scope:** Home screen / Download Manager screen only  
**Primary flow:** Paste link or enter keyword -> app detects intent -> show results or download using preset  
**Layout shell:** Top bar + left column + right column

---

## 1. Mục tiêu

Mục tiêu của màn hình là biến Home thành một công cụ tải và quản lý media nhanh, rõ, không bị trùng chức năng. User có thể bắt đầu bằng một input duy nhất, cấu hình preset tải mặc định một lần, sau đó quản lý lịch sử tải và playlist nội bộ trong cùng một màn.

- Giữ layout shell: top bar, left column, right column.
- Left column tập trung vào smart input, gói miễn phí, lịch sử tải xuống và Playlist của tôi.
- Right column chỉ giữ các khối phụ trợ: Bắt đầu nhanh và Mở nhanh website.
- Bỏ các thành phần trùng lặp: Premium + Nâng cấp cùng lúc, supported platform ở left column, dropdown trong nút Tải xuống.
- Download history trở thành download manager + media manager, hỗ trợ row states, bulk selection, thêm vào playlist và quản lý playlist.

---

## 2. Layout tổng thể

| Vùng | Vai trò | Thành phần chính |
|---|---|---|
| Top bar | Điều hướng cấp app | Logo, Trang chủ, Đăng ký, Chuyển đổi, Trình duyệt, Nâng cấp/Premium, notification, settings, theme, window controls |
| Left column | Thao tác chính và quản lý nội dung | Smart input, preset tải, plan strip, Lịch sử tải xuống, Playlist của tôi |
| Right column | Hướng dẫn và shortcut phụ trợ | Bắt đầu nhanh, Mở nhanh website |

---

## 3. Top bar

Không hiển thị đồng thời **Premium** và **Nâng cấp**.

| User state | Hiển thị | Không hiển thị |
|---|---|---|
| Free user | Nút Nâng cấp ở góc phải | Menu/badge Premium riêng biệt |
| Premium user | Badge/menu Premium hoặc trạng thái gói | Nút Nâng cấp |

Rules:

- Không đặt YouTube/TikTok/Facebook trên top nav nếu chúng là shortcut mở in-app browser.
- Không dùng top bar để chứa các platform shortcut; platform shortcut nằm ở right column trong box **Mở nhanh website**.
- Settings trên top bar là cài đặt toàn app, không phải tùy chọn tải mặc định.

---

## 4. Smart input

Smart input là entry point chính. User có thể dán link video, playlist, kênh, nhiều link hoặc nhập từ khóa tìm kiếm.

**Cấu trúc control:**

```text
[Input link hoặc từ khóa] [History icon] [Batch icon] [Preset dropdown] [Primary CTA]
```

| Control | Hiển thị | Behavior |
|---|---|---|
| Input | Placeholder: Dán link video, playlist, kênh hoặc nhập từ khóa... | Nhận paste, drag/drop link, gõ text, Enter để submit |
| History icon | Icon-only, không label luôn hiện | Tooltip: Lịch sử tải xuống. Có thể scroll/focus tới lịch sử hoặc mở panel lịch sử tùy code hiện có. |
| Batch icon | Icon-only, không label luôn hiện | Tooltip: Tải hàng loạt. Mở dialog batch download. |
| Preset dropdown | Ví dụ: MP4 - 1080p | Mở popover tùy chọn tải mặc định. |
| Primary CTA | Ví dụ: Tải xuống | Không có dropdown. Label đổi theo loại input. |

### 4.1. Smart detect và CTA động

| Input detected | CTA | Kết quả khi submit |
|---|---|---|
| Trống | Tải xuống disabled | Không submit. Có thể show focus/error nhẹ nếu user click. |
| Video URL | Tải xuống | Tải theo preset mặc định. Nếu thiếu chất lượng đã chọn thì dùng fallback rule. |
| Playlist URL | Xem playlist | Mở dialog playlist; user chọn video cần tải. |
| Channel URL | Xem kênh | Mở dialog kênh; user chọn video/shorts/playlist. |
| Text thường | Tìm kiếm | Mở dialog tìm kiếm video. |
| Nhiều URL | Tải hàng loạt | Mở batch dialog với danh sách link đã parse. |
| Unsupported URL | Mở trình duyệt hoặc Tìm kiếm | Nếu là website có thể browse, mở in-app browser; nếu không rõ thì cảnh báo nhẹ. |

Rules:

- Không tự động tải playlist hoặc channel ngay từ Home vì có thể có rất nhiều item.
- Search, playlist, channel hiển thị nội dung trong dialog, không render sẵn trong Home.
- Nút Primary CTA không có dropdown trong mọi state.

---

## 5. Preset download dropdown

Preset dropdown là control riêng biệt, dùng để cấu hình mặc định cho các lần tải. Đây không phải action menu của nút Tải xuống.

| Field | Default | Option |
|---|---|---|
| Định dạng | MP4 Video | MP4 Video, MP3 Audio, Auto |
| Chất lượng | 1080p | Best available, 1080p, 720p, 480p, audio bitrate nếu MP3 |
| Khi không có chất lượng đã chọn | Chọn gần nhất | Chọn gần nhất, hỏi lại tôi |
| Vị trí lưu | Downloads/Svid | Chọn thư mục khác |
| Advanced | Collapsed link | Mở cài đặt tải nâng cao |

Rules:

- Popover mở khi click vào preset, ví dụ **MP4 - 1080p**.
- Sau khi user đổi preset, label cập nhật ngay trên control.
- Preset được áp dụng khi tải video URL, batch links và khi tải item đã chọn trong dialog playlist/channel/search.
- Nếu user nhập text search, preset chưa dùng ngay nhưng sẽ làm default trong dialog kết quả.

---

## 6. Right column

Right column chỉ giữ hai box mặc định:

1. **Bắt đầu nhanh**
2. **Mở nhanh website**

Không hiển thị mặc định:

- Storage
- Session Pulse
- Download Details
- Shortcuts

### 6.1. Bắt đầu nhanh

1. Dán link hoặc nhập từ khóa.
2. Xem kết quả và chọn định dạng nếu cần.
3. Tải xuống và lưu để xem offline.

### 6.2. Mở nhanh website

Box này là shortcut mở website trong in-app browser, không phải filter và không phải badge supported platform.

- Title: Mở nhanh website.
- Items: YouTube, TikTok, Facebook, Instagram, X, Reddit, Pinterest, Vimeo, Thêm website.
- Click item -> chuyển sang Trình duyệt và mở website tương ứng.
- Tooltip item: Mở [website] trong trình duyệt tích hợp.
- Không lặp lại platform shortcut ở left column.

---

## 7. Plan strip

Ví dụ:

```text
Gói miễn phí - Bạn còn 15 lượt tải hôm nay - Nâng cấp để tải không giới hạn
```

Rules:

- CTA nâng cấp trong plan strip có thể giữ vì nó có ngữ cảnh quota.
- Nếu top bar đã có Nâng cấp, plan strip CTA nên là dạng text link, không phải button lớn thứ hai.
- Nếu user premium, plan strip có thể hiển thị trạng thái Premium hoặc ẩn tùy sản phẩm.

---

## 8. Download manager

Download manager gồm hai tab:

```text
Lịch sử tải xuống | Playlist của tôi
```

Không dùng tab **Hàng đợi tải** nếu code chưa có queue manager hoàn chỉnh.

| Tab | Mục đích | Nội dung |
|---|---|---|
| Lịch sử tải xuống | Quản lý file/job đã tải, đang tải, lỗi hoặc đang chờ | Search, sort, filter icon, view toggle, rows theo trạng thái |
| Playlist của tôi | Quản lý playlist nội bộ do user tạo từ file đã tải | Tạo playlist, phát playlist, đổi tên, xóa, thêm/remove item |

### 8.1. Toolbar lịch sử tải xuống

Normal mode:

```text
[Select all checkbox] [Search history] [Sort dropdown] [Filter icon] [View toggle]
```

Rules:

- Filter chỉ là icon, dùng logic filter đã có sẵn trong code.
- Khi có filter active, icon filter có chấm/badge số lượng filter đang áp dụng.
- Không hiển thị hàng chip filter dài trên màn chính.
- Search placeholder: Tìm trong lịch sử...
- Sort mặc định: Mới nhất.

### 8.2. Row layout

Row bình thường không cần luôn hiển thị checkbox ở mọi row. Checkbox xuất hiện khi hover một row hoặc khi list vào selection mode.

Normal row:

```text
[thumbnail] Title / Source / Metadata [Action icon] [More icon]
```

Hover row:

```text
[checkbox] [thumbnail] Title / Source / Metadata [Action icon] [More icon]
```

Rules:

- Checkbox nằm ở đầu row, trước thumbnail.
- Action cuối row là icon-only: Play, Pause, Retry hoặc More.
- Không dùng icon folder mặc định ở row; Mở thư mục nằm trong menu More.
- Tooltip và aria-label vẫn cần cho icon-only actions.

### 8.3. Row states

| State | Metadata hiển thị | Action icon | Visual treatment |
|---|---|---|---|
| Đã tải | Đã tải - MP4 - 1080p - 224.51 MB - 28/04/2026 14:21 | Play/Open icon | Badge xanh nhẹ, row trắng |
| Đang tải | Đang tải - 43% - 1.02 GB / 2.38 GB - 12.4 MB/s - Còn 1m32s | Pause icon | Row xanh rất nhạt, progress bar rõ dưới metadata |
| Đang chờ | Đang chờ - 0 B / 3.24 GB - Chờ xử lý | More hoặc Start icon nếu có action | Badge xám/xanh nhạt, không progress bar |
| Lỗi | Lỗi - Không thể tải video. Vui lòng thử lại. | Retry icon | Row đỏ rất nhạt, badge đỏ nhẹ |
| Audio đã tải | Đã tải - MP3 - 320kbps - 8.45 MB - 28/04/2026 10:15 | Play icon | Badge xanh nhẹ, icon/type audio ở thumbnail nếu cần |

Rules:

- Progress bar chỉ xuất hiện với Đang tải hoặc Đang chuyển đổi.
- Nếu đã có text Đang tải 43%, progress bar vẫn hữu ích nhưng phải là thanh rõ, full chiều ngang content row, không phải thanh nhỏ rời rạc.
- Đổi nhãn Đã hoàn thành thành Đã tải.
- Với state Đang chờ, không dùng button text Chờ vì Chờ là trạng thái, không phải action.

---

## 9. Multiple selection và bulk actions

Selection mode giúp user thao tác nhiều file cùng lúc. Đây là tính năng chính của download/media manager.

### 9.1. Checkbox behavior

| Trạng thái | Checkbox row | Toolbar |
|---|---|---|
| Normal | Ẩn hoặc rất nhẹ; hiện khi hover row | Search/sort/filter/view hiện bình thường |
| Hover row | Hiện checkbox ở đầu row | Toolbar không đổi |
| Tick một row | Tất cả row hiện checkbox; selected row checked | Chuyển sang selection toolbar |
| Tick Select all | Tất cả row đang hiển thị được chọn | Chuyển sang selection toolbar |

### 9.2. Selection toolbar

Khi có item được chọn, toolbar thay thế tạm search/sort/filter:

```text
[n mục đã chọn] [Phát] [Thêm vào playlist] [Xóa] [Thêm] [Hủy]
```

Rules:

- Bulk toolbar dùng icon + text để giảm thao tác nhầm, đặc biệt với Xóa và Thêm vào playlist.
- Row actions có thể ẩn bớt khi selection mode đang bật để tránh rối.
- Nếu chọn lẫn trạng thái, chỉ enable các action hợp lệ cho ít nhất một item; action không hợp lệ có tooltip giải thích.

### 9.3. Bulk action rules

| Action | Áp dụng cho | Behavior |
|---|---|---|
| Phát | Các item đã tải | Phát các mục đã chọn theo thứ tự hiện tại. Nếu chọn 5 mục nhưng chỉ 3 mục đã tải, thông báo: Chỉ phát 3/5 mục đã tải. |
| Thêm vào playlist | Các item đã tải | Mở menu chọn playlist hoặc tạo mới. Item chưa hoàn tất bị bỏ qua hoặc được báo rõ. |
| Xóa | Mọi item | Mở confirm dialog, tách Xóa khỏi lịch sử và Xóa cả file khỏi máy. |
| Thêm | Mọi item | Menu tùy trạng thái: sao chép link, mở thư mục, tải lại, tạm dừng, tiếp tục, hủy tải. |
| Hủy | Selection mode | Bỏ chọn tất cả và quay về toolbar thường. |

Confirm dialog khi xóa:

```text
Bạn muốn xóa các mục đã chọn?

( ) Chỉ xóa khỏi lịch sử
( ) Xóa cả file khỏi máy

[Hủy] [Xóa]
```

---

## 10. Playlist của tôi

Playlist của tôi là playlist nội bộ trong app, khác với playlist nguồn từ YouTube/TikTok. Tab này dùng để quản lý nhóm media đã tải.

Rules:

- Entry từ bulk action: Thêm vào playlist -> chọn playlist có sẵn hoặc + Tạo playlist mới.
- Tab Playlist của tôi hiển thị danh sách playlist: tên, số mục, tổng thời lượng, thời gian cập nhật, action phát, menu more.
- Click playlist -> mở detail: danh sách item, phát tất cả, thêm item, sắp xếp, đổi tên, xóa playlist.
- Remove khỏi playlist không đồng nghĩa xóa file khỏi máy.
- Xóa playlist không xóa file khỏi máy, trừ khi user chọn rõ một option nâng cao.

| Màn/State | Thành phần |
|---|---|
| Playlist list | + Tạo playlist, list playlist cards/rows, search playlist nếu cần |
| Playlist detail | Tên playlist, số mục, Phát tất cả, Thêm video, Sort, item rows, remove item |
| Create playlist dialog | Tên playlist, số item sẽ thêm, Hủy, Tạo playlist |

---

## 11. Dialogs cần có

| Dialog | Trigger | Mục đích |
|---|---|---|
| Search video dialog | Input text thường -> CTA Tìm kiếm | Hiển thị kết quả tìm kiếm; user chọn item để tải hoặc thêm batch/playlist. |
| Playlist dialog | Playlist URL -> CTA Xem playlist | Hiển thị video trong playlist nguồn; user chọn item để tải. |
| Channel dialog | Channel URL -> CTA Xem kênh | Hiển thị Videos/Shorts/Playlists của kênh; user chọn item để tải. |
| Batch dialog | Batch icon hoặc nhiều URL | Parse nhiều link, validate, chọn preset, bắt đầu tải hàng loạt. |
| Preset popover | Click preset dropdown | Chỉnh cấu hình tải mặc định. |
| Delete confirm | Bulk delete hoặc row delete | Chọn xóa khỏi lịch sử hoặc xóa cả file khỏi máy. |
| Create playlist dialog | Bulk action + Tạo playlist mới | Tạo playlist nội bộ từ item đã chọn. |

---

## 12. Visual rules

| Token/Layer | Gợi ý |
|---|---|
| App background | #F6F8FB hoặc xám xanh rất nhạt |
| Card background | #FFFFFF |
| Card border | #E5EAF2 |
| Row hover | #F8FAFF |
| Row đang tải | #F4F8FF |
| Row lỗi | #FFF7F7 |
| Primary blue | #0B63F6 hoặc tương đương |
| Success badge | Xanh lá nhạt, text xanh đậm |
| Error badge | Đỏ nhạt, text đỏ đậm |

Rules:

- Nút Tải xuống: height 48-52px, min-width 140-156px, font-weight 600, không dropdown.
- Icon Lịch sử và Batch: icon-only, kích thước nhỏ hơn primary button, tooltip on hover.
- Preset dropdown: cùng height với input controls, label compact như MP4 - 1080p.
- Row action: icon-only, không text. Bulk toolbar: icon + text.
- Thumbnail: aspect ratio 16:9, duration badge ở góc phải dưới, platform badge nếu cần ở góc trái trên.

---

## 13. Accessibility và keyboard

- Mọi icon-only button phải có aria-label và tooltip.
- Focus state rõ cho input, icon buttons, preset dropdown, primary CTA, row actions.
- Enter trong smart input submit theo CTA hiện tại.
- Esc đóng popover/dialog hoặc thoát selection mode nếu đang chọn nhiều item.
- Tab order: input -> history icon -> batch icon -> preset -> CTA -> download manager toolbar -> rows -> right column.
- Checkbox select row phải có label ẩn theo tên item.
- Bulk delete cần confirm, không xóa file khỏi máy mà không hỏi rõ.

---

## 14. Empty, loading, error states

| State | Copy/Behavior |
|---|---|
| Chưa có lịch sử | Chưa có video nào được tải. Dán link hoặc mở website để bắt đầu. |
| Không có kết quả search history | Không tìm thấy mục phù hợp. Thử từ khóa khác hoặc xóa bộ lọc. |
| Filter active nhưng không có item | Không có mục nào khớp bộ lọc hiện tại. Xóa bộ lọc. |
| Parsing link | Đang phân tích liên kết... |
| Unsupported URL | Website này chưa được hỗ trợ tải trực tiếp. Bạn có thể mở trong trình duyệt tích hợp. |
| Download failed | Không thể tải video. Vui lòng thử lại. |
| Storage warning | Không hiện mặc định trong right column. Chỉ hiện warning nhẹ khi dung lượng gần đầy. |

---

## 15. Acceptance checklist cho dev/design

- Không có Premium và Nâng cấp cùng lúc trong top bar.
- Không có platform shortcut ở left column; chỉ có ở right column trong box Mở nhanh website.
- Nút Tải xuống không có dropdown.
- History và Batch là icon-only; không có label luôn hiện dưới icon.
- Preset dropdown riêng hiển thị dạng MP4 - 1080p và mở popover cấu hình tải.
- Smart input đổi CTA theo video URL, playlist URL, channel URL, text keyword, nhiều URL.
- Playlist/channel/search mở dialog, không render sẵn nội dung trong Home.
- Download manager có tab Lịch sử tải xuống và Playlist của tôi.
- Không có tab Hàng đợi tải nếu code chưa có queue manager.
- Filter trong history là icon, có active state/badge nếu đang áp dụng filter.
- Checkbox row nằm ở đầu row, trước thumbnail; chỉ rõ khi hover hoặc selection mode.
- Bulk toolbar xuất hiện khi có item được chọn và có Phát, Thêm vào playlist, Xóa, Thêm, Hủy.
- Row action là icon-only: Play, Pause, Retry, More.
- Không có icon folder mặc định ở row; Mở thư mục nằm trong menu More.
- Row demo đủ trạng thái: Đã tải, Đang tải, Đang chờ, Lỗi, Audio đã tải.
- Progress bar chỉ hiện ở item đang tải/đang chuyển đổi.
- Delete confirm tách rõ xóa khỏi lịch sử và xóa cả file khỏi máy.
- Playlist của tôi cho phép tạo playlist, thêm item, phát, rename/remove/delete.

---

## 16. Mockup states cần vẽ ở bước tiếp theo

1. Default Home: smart input, plan strip, history list, right quick start + quick websites.
2. Preset dropdown open: MP4 - 1080p popover đang mở.
3. Selection mode: 3 mục đã chọn, bulk toolbar hiển thị.
4. Playlist của tôi tab: danh sách playlist nội bộ.
5. Dialog mẫu: Search video hoặc Playlist URL nếu cần làm flow chi tiết.
