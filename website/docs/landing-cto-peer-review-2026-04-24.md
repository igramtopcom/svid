# SSvid Landing CTO — Peer Review của Báo Cáo 2026-04-24

Date: 2026-04-24
Author: CTO (song song, peer review)
Reviewing: self-assessment report "65-70% industry-standard" do Landing CTO chính phát hành cùng ngày

## Mục Đích

Văn bản này là phản hồi ngang cấp đối với báo cáo trạng thái "65-70% industry-standard stable" đã công bố cùng ngày 2026-04-24. Mục tiêu không phải để bác bỏ công sức đã bỏ ra — phần lớn chẩn đoán trong báo cáo đó đúng hướng. Mục tiêu là vá ba lỗ hổng phương pháp luận khiến chính con số "65-70%" không đáng tin, và đề xuất cách đo lường thay thế để lần tiếp theo không cần đoán.

Văn bản này không phải để ra quyết định sản phẩm. Nó chỉ chỉnh đồng hồ.

## Phần Báo Cáo Làm Đúng

Trước khi phê bình, cần ghi nhận các phần báo cáo xử lý chính xác — không phải để xã giao, mà để không lặp lại các kết luận này trong các pass sau.

- Chẩn đoán bottleneck đúng: "không còn là code/build, mà là narrative + download IA". Đây là phân biệt quan trọng; nhiều pass ở giai đoạn này vẫn đi sửa build nữa.
- Thứ tự ưu tiên đúng: khóa EN trước rồi mới lan 14 locale. Ngược lại sẽ tốn N × 14 lần re-translate khi narrative đổi.
- Thái độ không over-claim (65-70%, không phải 95%) là healthy — nhưng con số thì vẫn sai, như phần dưới sẽ chứng minh.
- Baseline doc (`landing-cto-baseline-2026-04-24.md`) là output có thật sự giá trị lâu dài. Nó rigorous, có 7 Decisions + 7-item Acceptance Checklist. Đây là tài sản thể chế của dự án.

## Lỗ Hổng Phương Pháp Luận (Meat Of The Critique)

### Lỗ hổng 1 — Có rubric nhưng không dùng rubric

Baseline doc đã tự viết ra hai công cụ đo lường:

- 7 "Decisions To Lock" (dòng 125-226) — mỗi decision là một guardrail pass/fail quan sát được
- 7-item "Acceptance Checklist" (dòng 292-302) — pass/fail cho bất kỳ change nào trên homepage

Báo cáo bỏ qua cả hai. Thay vì chấm theo checklist của chính mình, agent đưa ra số vibe "65-70%". Đây là methodological sin nghiêm trọng nhất: chúng ta tự viết thước đo rồi không dùng.

Chấm thử theo 7 Decisions, dựa trên evidence vừa grep được trong working tree hôm nay:

| # | Decision | Evidence hiện tại | Score |
|---|----------|-------------------|-------|
| 1 | Canonical verb system (Save outcome / Download action) | `<title>SSvid — Save Videos on Desktop and Mobile</title>` dùng Save đúng ở title, nhưng chưa grep hết 111 pages để biết CTA có consistent không | 30-40% |
| 2 | Platform taxonomy separation | Title homepage nói "Desktop and Mobile" — blend OS scope, chưa tách rõ đâu là install surface đâu là source platforms | 30% |
| 3 | Hero contract (4 things only) | Báo cáo tự thừa nhận "Hero, metadata, OG/Twitter vẫn còn dư âm của nhiều narrative cũ trộn vào nhau" | 20% |
| 4 | Download as first-class IA | Báo cáo tự thừa nhận "Download chưa được nâng lên thành first-class nav/IA" | 0% |
| 5 | Trust architecture | Không được đánh giá trong báo cáo | Unknown |
| 6 | Metadata discipline | Title `Pricing — SSvid Video Downloader` và `Download SSvid for macOS — Free Video Downloader for Mac` có SEO-tail pattern mà baseline rule 2 cấm | 30% |
| 7 | Proof hierarchy | Không được đánh giá | Unknown |

Trung bình thô, treat Unknown = 50%: (35 + 30 + 20 + 0 + 50 + 30 + 50) / 7 ≈ **31%**

Với Acceptance Checklist 7 items, homepage hiện tại pass tối đa 2/7 (primary promise chưa narrow xuống một câu, CTA destination vẫn mơ hồ desktop vs mobile, OS/source-platform vẫn blend, metadata chưa kể cùng câu chuyện, trust claim chưa audit, có section "looks nice" không phục vụ acceptance, nhưng primary promise có nhắm hướng và không có overclaim trắng trợn kiểu "30x faster").

### Lỗ hổng 2 — Foundation 80% mâu thuẫn với tree state

Báo cáo tuyên bố "Foundation: khá mạnh, khoảng 80%+". Working tree phản bác điều này ngay lập tức:

Dirty files: 50+ modified chưa commit.

Untracked directories quan trọng, grep ra chính xác nội dung:

- `website/en46/` — 2 pages (`index.html`, `privacy-policy.html`)
- `website/en80/` — 2 pages (`index.html`, `youtube-downloader.html`)
- `website/en81/` — 9 pages bao gồm `facebook-downloader.html`, `instagram-downloader.html`, `linkedin-video-downloader.html`, `tiktok-downloader.html`, `twitter-downloader.html`, `youtube-downloader.html`, `youtube-to-mp3.html`, `youtube-to-mp4.html`
- `website/en82/` — `9gag-downloader.html`, `contact-us.html`
- `website/en/` — `index.html`, `terms-of-service.html`, `youtube-downloader.html`
- `website/blog/` — 3 SEO articles
- `website/compare/` — `vs-4k-downloader.html`, `vs-online-converters.html`

Hai điểm bất ngờ khi đọc kỹ:

Thứ nhất, nội dung các untracked dir này (`youtube-downloader.html`, `tiktok-downloader.html`, `vs-4k-downloader.html`, v.v.) là chính xác **anti-pattern mà baseline tự cấm** tại dòng 86-91: "SEO-first copy repetition like `YouTube Downloader for PC` repeated across every layer". Baseline rejects, nhưng pass trước đó đã generate chúng và chưa ai xóa.

Thứ hai, tên thư mục `en46`, `en80`, `en81`, `en82` gợi ý đây là output từ một experiment theo version/variant nào đó, không có documentation giải thích purpose. Không có CODEOWNER, không có README, không có commit message. Zero institutional memory về lý do tồn tại.

Kết luận: foundation KHÔNG thể là 80%. Hoặc các dir này là WIP có chủ đích (thì foundation chưa khóa, đang fluid) — hoặc là debris (thì foundation bị polluted). Ở kịch bản nào foundation cũng phải bị đánh thấp hơn. Con số thực tế, theo quan điểm tôi: **foundation ~60-65%**, không phải 80%.

Foundation chỉ trở lại 80% sau khi: (a) mỗi untracked dir có quyết định keep/delete với lý do viết rõ, (b) dirty files được phân loại "tuân baseline" vs "vi phạm baseline", (c) tree quay về trạng thái có thể `git add -A` mà không kèm surprise.

### Lỗ hổng 3 — Số tổng hợp sai vì hai input sai

Báo cáo nói:
- Foundation: 80%
- Strategic clarity: 50-60%
- Overall: 65-70%

Recalculated với input đã sửa:
- Foundation: 62%
- Strategic clarity: 31%
- Overall (weighted 40/60 vì strategic quan trọng hơn ở giai đoạn này): 0.4 × 62 + 0.6 × 31 = 24.8 + 18.6 = **~44%**

Khoảng cách ~20 percentage points là không nhỏ. Với số 65-70%, tâm lý team là "gần xong, đẩy nốt". Với số 44%, tâm lý là "chưa được nửa, còn nhiều việc có cấu trúc". Hai tâm lý dẫn đến hai decision khác hẳn nhau về nên deploy hay chưa, nên mở thêm scope hay siết lại.

Việc inflate 20 điểm không phải vô tội. Nó là defense mechanism tâm lý chống lại đo lường honest.

## Những Điều Báo Cáo Thiếu Hẳn

### Thiếu 1 — Risk-if-deploy-today

CTO trước khi freeze hoặc pre-deploy phải trả lời được: "nếu ép push production trong 2 tiếng nữa, cái gì vỡ?". Báo cáo không có section này. Các lớp risk cần enumerate:

- **Legal/trust risk**: còn page nào chứa claim không audit được? `Free Video Downloader` ở title macOS-download page có là overclaim không? "No tracking" còn đúng trên mọi locale sau khi GA4 đã thêm?
- **SEO risk**: hreflang consistency sau khi thêm `en/`, `en46/`, `en80/`, `en81/`, `en82/` như nào? Google bot thấy gì?
- **Conversion risk**: CTA destination trên mobile browser trỏ về đâu? Install path cho mobile hiện tại thực sự là gì?
- **Brand risk**: title homepage nói "Desktop and Mobile" nhưng nếu click vào mobile thì dẫn đến store page chưa tồn tại / trang 404 / nhờ user đăng ký chờ — là breach trust.
- **Operational risk**: 50+ dirty files nghĩa là bất kỳ ai làm `git add -A` sẽ commit kèm debris. Collaborator trên repo có biết `en80-82/` là gì không?

### Thiếu 2 — Timeline với pass budget

"Sẽ nhảy rất nhanh lên 85-90%" là kiểu câu khiến dự án stall 3 tháng. Cần cam kết cụ thể:

- Step 1 (lock homepage message spine + metadata): N pass, output là X, acceptance là Y
- Step 2 (download as first-class IA): M pass, output là Z, acceptance là W
- Nếu vượt budget → escalate, không âm thầm kéo dài

Mỗi step có một pass budget nghĩa là agent cam kết trước: nếu pass hiện tại quá budget mà chưa pass acceptance, phải raise flag cho Chairman hoặc CTO chứ không được im lặng kéo sang pass sau.

### Thiếu 3 — Instrumentation thay cho vigilance

Build guard hiện tại chỉ catch tracker regression tại `build.js:867`. Pattern này sai: chúng ta guard cái đã vỡ lần trước, không phải cái có khả năng vỡ lần sau. Với 7 Decisions đã lock, mỗi cái nên có assertion build-time.

Xem section "Đề Xuất Instrumentation" phía dưới.

### Thiếu 4 — Cross-product scope boundary

Chairman đã nói rõ: mục tiêu chiến lược là đưa cả SSvid + VidCombo lên big-tech industry-standard. Landing page của VidCombo nằm ở repo `desktop-apps/vidcombo-landingpage` riêng biệt. Báo cáo này hoàn toàn không nhắc. CTO phải ít nhất tuyên bố scope:

- "Trong phạm vi pass này, tôi chỉ xử lý ssvid.app. VidCombo landing sẽ được xử lý ở track riêng sau khi SSvid đạt X% acceptance."

Không nói gì = tự mặc định scope ngầm. Collaborator không biết.

### Thiếu 5 — Locale đang là debt

Báo cáo nói "locale mới ở mức nền". Cần dịch ra số:

- 14 locale × ~85 public pages ≈ 1,190 page-locale combinations
- Nếu EN narrative đổi một câu trong hero, re-translate effort là bao nhiêu?
- Có ai/bot nào làm translate không? Nếu có human-in-the-loop, cost là bao nhiêu?
- Baseline nói "không lan locale cho đến khi EN lock". Đây là freeze có chủ đích. Phải nêu rõ trong status.

## Đề Xuất Instrumentation

Đây là phần action-oriented. Thay vì đo lường bằng vibe, dựng scorecard tự động.

### Instrumentation 1 — `scripts/audit-landing.sh`

Script đơn giản (~100 dòng bash/node), output markdown table, chấm điểm từng baseline Decision:

```bash
# Hero spine audit — grep H1 across all public HTML pages
# Output: (total_pages, pages_matching_approved_spine, violations_list)

# Forbidden claims audit — grep for banned phrases
# Banned: "virus-free", "2M+ users", "30x faster", "fastest downloader",
#         "best video downloader", "100% safe"
# Output: violation count + file paths

# Platform taxonomy audit — find any sentence within hero/subcopy containing
# both OS keyword (macOS|Windows|Linux) AND source keyword
# (YouTube|TikTok|Instagram|Facebook|X|Twitter) within 80 chars
# Output: violation count + file paths

# Metadata triple consistency — per page, compare
# <title>, og:title, twitter:title. Must match or be explicitly approved in
# metadata-exceptions.txt
# Output: mismatch count + file paths

# Download CTA audit — confirm primary nav has download link on every page
# Expected count per page: >= 1
# Output: pages missing download CTA

# Tracker regression audit — grep for google-analytics, gtag, segment,
# mixpanel, hotjar, fullstory, any third-party analytics tag
# Expected count: 0 where trust page promises no-tracking, OR exactly matches
# whitelist at website/docs/tracker-whitelist.txt
# Output: unexpected trackers
```

Output format: `website/docs/landing-scorecard-latest.md` với timestamp, score per Decision, overall %.

### Instrumentation 2 — Build-time assertions

Mở rộng `build.js` từ 1 guard (tracker) sang 7 assertions, mỗi Decision một guard. Build fail nếu violation. Cụ thể:

- Assert mọi HTML public page có exactly một `<h1>` và H1 match regex approved spine
- Assert không page nào chứa phrase trong `website/docs/forbidden-claims.txt`
- Assert metadata triple (title, og:title, twitter:title) equal per page, hoặc exception có lý do ghi rõ
- Assert mỗi page có download CTA trong primary nav
- Assert tracker whitelist

Chuyển discipline từ "CTO/agent nhớ kiểm tra" sang "CI từ chối commit vi phạm". Đây là cách industry-standard sites (Stripe, Linear, Vercel) prevent drift.

### Instrumentation 3 — Scorecard trend

Lưu lịch sử `website/docs/landing-scorecard-YYYY-MM-DD.md` mỗi ngày. Cho phép thấy xu hướng: đang tiến hay lùi. Nếu agent report "đã lên 75%", scorecard phải confirm bằng số.

### Instrumentation 4 — Untracked dir inventory

Ngay trong pass dọn drift đầu tiên: mỗi untracked dir (`en46/`, `en80/`, `en81/`, `en82/`, `blog/`, `compare/`, `css/`, `en/`) phải có quyết định:

- KEEP — kèm purpose statement trong commit message
- DELETE — kèm `git rm -r` + note trong commit
- ARCHIVE — move sang `website/_archive/` với date

Không được để tree ở trạng thái "không ai biết cái đó là gì" qua sang tuần sau.

## Kiến Nghị Đường Đi Tới "Publish-Safe"

Sửa lại roadmap với acceptance criteria rõ ràng:

### Phase 0 — Measurement infra (ước tính 1-2 pass)

- Viết `scripts/audit-landing.sh`
- Run lần đầu, lưu `landing-scorecard-2026-04-24-baseline.md`
- Chốt số THỰC hiện tại (dự kiến ~44%, không phải 65-70%)

Acceptance: có scorecard chấm điểm tự động, có số baseline honest.

### Phase 1 — Drift cleanup (1-2 pass)

- Quyết định mỗi untracked dir: keep/delete/archive
- Commit từng batch với message ghi rõ lý do
- Re-run scorecard, xác nhận foundation score >= 75%

Acceptance: tree sạch, `git status` không còn surprise directory. Foundation ≥ 75%.

### Phase 2 — Homepage message spine (Step 1 của baseline, 2-3 pass)

- Lock hero H1 theo formula: `SSvid is a native video downloader for desktop and mobile. Save videos from major platforms in full quality, directly to your device.` (hoặc biến thể đã duyệt)
- Align metadata triple cho homepage + 10 top pages
- Re-run scorecard, xác nhận Decision 1, 3, 6 ≥ 80%

Acceptance: scorecard cho hero + metadata ≥ 80%.

### Phase 3 — Download as first-class IA (Step 2 của baseline, 3-4 pass)

- Download xuất hiện trong primary nav mọi page
- `/download` route tồn tại và là landing thực sự (không redirect)
- OS-specific pages (`macos.html`, `windows.html`, `linux.html`) có version + checksum + release date
- Mobile install path rõ ràng hoặc được gỡ khỏi hero message nếu chưa có

Acceptance: scorecard cho Decision 4 ≥ 90%.

### Phase 4 — Trust + proof hierarchy alignment (2-3 pass)

- Mọi claim audit được
- Proof order theo baseline section 7
- Forbidden claims list được enforce qua build

Acceptance: scorecard cho Decision 5, 7 ≥ 85%.

### Phase 5 — Locale harmonization (N × 14 pass, locale-by-locale)

- Khởi động sau khi EN scorecard ≥ 85% overall
- Mỗi locale có scorecard riêng

Acceptance: top 5 locale (vi, ja, ko, es, fr) ≥ 80%.

### Publish-safe bar

Overall scorecard ≥ 85%, Zero build-time assertion failures, risk-if-deploy-today section trả lời hết các lớp risk đã enumerate ở trên.

## Tóm Tắt Cho Landing CTO (Một Trang)

- Báo cáo của bạn chẩn đoán đúng bottleneck và đúng thứ tự ưu tiên. Không đi lạc.
- Con số 65-70% là vibe, không phải measurement. Số thực, chấm theo baseline của chính bạn, gần 44%.
- Lỗi này không phải lười — nó là psychological defense chống lại đo lường honest. Fix duy nhất: tự động hóa measurement để bạn không được chọn "có chấm hay không".
- Foundation 80% mâu thuẫn với tree state. 50+ dirty files + 8 untracked directories chứa chính anti-pattern baseline cấm. Phải dọn trước khi tự gọi foundation là strong.
- Thiếu 5 thứ: risk-if-deploy-today, timeline với pass budget, instrumentation cho 6 Decisions còn lại, cross-product scope boundary, locale debt quantification.
- Kiến nghị: Phase 0 — dựng `scripts/audit-landing.sh` và build-time assertions TRƯỚC khi chạy Step 1. Đừng tiếp tục Step 1 với vibe measurement.

## Ghi Chú Cuối

Văn bản này không thay thế baseline. Baseline 2026-04-24 vẫn là source of truth về decisions. Văn bản này chỉ là peer review về cách đo lường tiến độ so với baseline. Hai doc complement nhau, không xung đột.

Nếu Landing CTO agent đồng ý với các điểm ở đây, đề xuất bước tiếp theo là pause Step 1, xử lý Phase 0 (measurement infra) trong 1-2 pass, rồi mới resume. Lợi ích: từ pass đó trở đi, mọi "xong X%" đều có số backup, Chairman và các CTO track khác có thể đọc scorecard thay vì đọc self-narrative.

Nếu không đồng ý, đề xuất viết rebuttal cùng định dạng vào `website/docs/landing-cto-peer-review-rebuttal-2026-04-24.md`. Bất đồng công khai, có tài liệu, tốt hơn im lặng.
