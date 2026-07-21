# Pass 03A — VOICE Specification

**Vai trò file này**: Là **firmware ngôn ngữ** của app — cọc tiêu cho mọi string user thấy. Tách khỏi `DESIGN.md` (visual) vì 2 lớp này có decision authority + change cadence khác nhau.
**Scope**: Áp dụng toàn app Svid + VidCombo, locale VI + EN. Khi mở rộng thêm 13 locale ở v2.1, file này vẫn là gốc — mỗi locale chỉ adapt rule (capitalization, pronoun) tương ứng, không tạo voice mới.
**Quan hệ**: VOICE.md = HOW we speak. TERMINOLOGY.md (Pass 03B) = WHAT we call things. Khi viết string mới → đọc cả 2.

---

## 0. Tại sao file này tồn tại

### 0.1 Vacancy

`DESIGN.md` (304 dòng) đã đặc tả visual: color tokens, typography, shape, elevation. Nhưng **không có 1 dòng nào về voice**. Hệ quả: 5 voice cùng tồn tại trong app (Friendly Conversational / Engineering Spec / Military RPG / Title Case / ALL CAPS Dramatic — xem `02-DEEPDIVE-home.md` §1). "BÁO CÁO NHIỆM VỤ" là biểu hiện của vacancy này — một dev/designer extend "Nocturne Cinematic" từ visual sang language **không có guard rail**.

### 0.2 Decision authority

Visual decisions (DESIGN.md): designer + brand owner. Đổi cần A/B mockup.
Voice decisions (VOICE.md này): UX writer + brand owner + product leadership. Đổi cần evidence từ user research hoặc voice consistency audit.
→ Tách file để phân quyền rõ.

### 0.3 Khi nào update file này

- ✅ Khi audit định kỳ phát hiện voice drift (ví dụ: 1 PR thêm string lệch voice → cần update rule hoặc reject).
- ✅ Khi launch surface mới (ví dụ: Activity Center, Playlist của tôi) → bổ sung tone cho surface đó vào §12.
- ✅ Khi mở rộng locale → thêm pronoun/capitalization rule cho locale mới.
- ❌ KHÔNG đổi voice principles (§2-§4) sau khi đã ship — voice phải stable. Đổi voice = re-train user mental model = chi phí cao.

---

## 1. Hierarchy — voice cascade

```
Product Mission                            ← "Save any video, simply"
    ↓
Voice Invariant Principles (§2)            ← cả 2 brand đều theo
    ↓
Brand Voice — Svid (§3)                   ← warm-confident
Brand Voice — VidCombo (§4)                ← clean-utility
    ↓
Surface Tone (§12)                         ← per UI surface (button/dialog/error/...)
    ↓
String (concrete text)
```

Mỗi tầng KHÔNG override tầng trên — chỉ refine. Một button Svid trong dialog warning vẫn:
- Phải thỏa Invariant (không leak engineer jargon)
- Phải fit Brand Voice (warm-confident)
- Phải fit Surface Tone (button = action verb, ≤2 từ)
- → ra string cụ thể: "Hủy" / "Xóa"

---

## 2. Voice Invariant Principles — applies to BOTH brands

7 principles. Đây là **firmware** — bất kỳ string nào trong app phải thỏa cả 7. Brand voice (§3-§4) chỉ thêm flavor, không relax 7 principle này.

### P1. Speak human, not engineer

**Rule**: Không leak tên tool nội bộ (yt-dlp, ffmpeg, gallery-dl, cookie, API, throttle, circuit breaker, binary, …) ở **in-flow surface**. In-flow = user thấy mà không chủ động vào.

**Lý do**: User app này là consumer, không phải developer. 88 keys hiện tại leak tool name (xem `02-DEEPDIVE` §5.4). Phần lớn ở settings advanced (hợp lý — user chủ động vào). Phần ở in-flow (download dialog, snackbar, error) = **bug voice**.

**Phép kiểm nhanh**: Người mẹ 50 tuổi của bạn đọc string này có hiểu không? Nếu không → dịch lại bằng từ đời thường.

| ❌ Sai | ✅ Đúng |
|---|---|
| `Cần FFmpeg để tải đoạn video. Cài đặt trong Cài đặt → Thành phần nhị phân.` | `Cần thêm công cụ xử lý video. Mở cài đặt để cài.` |
| `yt-dlp sẽ ghép luồng video và âm thanh đã chọn bằng ffmpeg.` | `App sẽ ghép video và âm thanh bạn chọn.` |
| `Trình quản lý tải xuống hiệu suất cao được xây dựng bằng Rust + Flutter` | (xem brand tagline §3.4 / §4.4) |

**Ngoại lệ duy nhất**: settings page "Advanced" hoặc menu "Developer" — user chủ động vào, expectation được tăng technical level.

### P2. Action over description

**Rule**: Khi state có hành động khả dĩ, message phải gợi ý hoặc trigger được hành động đó. Không chỉ mô tả lỗi.

**Cấu trúc**: `[Diagnosis ngắn]. [Action verb hoặc hint hành động].`

**Lý do**: Error/empty/warning message mà chỉ mô tả tình trạng = bỏ user lại với câu hỏi "rồi tôi làm gì bây giờ?". Pass 02 đã list 4 case home vi phạm.

| ❌ Sai (chỉ mô tả) | ✅ Đúng (mô tả + action) |
|---|---|
| `Không thể lưu tùy chọn nền tảng` | `Không lưu được. Thử lại.` |
| `Không đủ dung lượng đĩa để bắt đầu tải xuống` | `Đĩa đầy. Dọn bớt hoặc đổi thư mục lưu.` |
| `Tải xuống thất bại` | `Tải thất bại. Thử lại hoặc báo lỗi.` |

**Ngoại lệ**: status passive (Pending, Downloading, Completed) — đây là state, không cần action verb.

### P3. Concrete over abstract

**Rule**: Dùng từ chỉ thứ user nhìn thấy được, không từ trừu tượng.

**Lý do**: Từ trừu tượng buộc user dịch trong đầu. Mỗi micro-translation tốn cognitive cost.

| ❌ Trừu tượng | ✅ Cụ thể |
|---|---|
| Tùy chọn nền tảng | Chỗ tải mặc định cho YouTube |
| Cấu hình Tải xuống | Tùy chọn tải |
| Tham số đầu vào | Link bạn dán |
| Trình quản lý tải xuống | Lịch sử tải |
| Phương thức tải | Cách tải |
| Bộ chọn luồng nâng cao | Chọn video + audio thủ công |

### P4. Câu ngắn, một ý

**Rule**: Một string = một intent. Quá 12 từ VI hoặc 10 từ EN trong button/tooltip/title → tách hoặc cắt.

**Lý do**: App là power-user desktop, user scan nhanh, không đọc kỹ. Câu dài = bị skip.

**Trace**: Ngoại trừ onboarding (§12.7) và confirmation dialog body (§12.4), 90% string nên ≤12 từ VI / 10 từ EN.

### P5. Statement-based, không question khi không cần

**Rule**: Title dialog/section/banner = statement (noun phrase hoặc declarative). Không hỏi "Bạn có muốn..." trừ khi đó là yes/no thật sự.

**Lý do**: Question form làm string dài hơn, mềm hơn, mất authority. App là tool, không phải bartender.

| ❌ Question form | ✅ Statement form |
|---|---|
| Bạn có muốn xóa? (title) | Xóa? (title) hoặc "Xóa lượt tải này?" (title + body) |
| Bạn có muốn cập nhật? | Bản mới {version} |

**Ngoại lệ**: Confirm body khi user sắp làm thao tác phá hủy → câu hỏi đầy đủ ("Xóa vĩnh viễn 5 file?"). Xem §12.4.

### P6. Không drama không cần

**Rule**: Không exclamation `!`, không ALL CAPS (trừ acronym + status badge LIVE/4K), không emoji ngoại trừ snackbar (§8).

**Lý do**: Drama nhân tạo phá trust. Tool tốt nói chuyện ngang hàng, không hét vào mặt user.

| ❌ Drama | ✅ Bình tĩnh |
|---|---|
| INITIALIZE DOWNLOAD! | Tải |
| BÁO CÁO NHIỆM VỤ | Tùy chọn tải |
| Wow! Your download is ready! | Đã xong |
| ⚠️ CẢNH BÁO! Đã hết lượt tải hôm nay! | Đã hết lượt hôm nay. Nâng cấp để tải tiếp. |

### P7. Consistent terminology — một concept một nhãn

**Rule**: Mỗi concept canonical (xem TERMINOLOGY.md Pass 03B) có **đúng 1 nhãn** mỗi locale × brand. Không tự phát minh synonym mới.

**Lý do**: 14 concept top hiện có ~250 label variant trong app. User phải decode lại "Audio thì lần này gọi là gì?" mỗi screen. Pattern này phá mental model.

**Phép kiểm nhanh**: Trước khi viết string mới → tra TERMINOLOGY.md. Nếu concept đã có nhãn → dùng. Nếu không → request thêm vào TERMINOLOGY.md (PR), không tự phát minh inline.

### P8. Native first, not translated

**Rule**: Mỗi locale string đọc lên phải có cảm giác là **viết gốc trong locale đó**, không phải dịch từ EN. VI string không được nghe như EN-bằng-từ-Việt.

**Lý do**: Đây là meta principle bao trùm Title Case 229 keys, "Báo cáo nhiệm vụ", "Luồng âm thanh", "Thành phần nhị phân", "Tùy chọn nền tảng" — toàn bộ pattern dịch literal mà chưa được tên hóa rõ ràng trước đây. Khi không có P8, dịch viên (kể cả AI) mặc định mirror cấu trúc EN.

**Phép kiểm nhanh duy nhất** cho reviewer:
> "Người Việt bản xứ đọc string này, có cảm giác là VI gốc hay EN-dịch?"

Nếu trả lời "EN-dịch" → reject, viết lại từ intent ("user cần biết gì ở đây?") thay vì từ template EN.

| ❌ EN-dịch | ✅ Native VI |
|---|---|
| Trình quản lý tải xuống hiệu suất cao | (xem tagline brand §3.4 / §4.4) |
| Cài đặt → Thành phần nhị phân | Cài đặt → Công cụ |
| Tùy chọn nền tảng | Mặc định cho YouTube |
| Bộ chọn luồng nâng cao | Chọn video + audio thủ công |
| Lịch Sử Phân Tích | Lịch sử quét link |

**Reverse rule cho EN**: EN string không được nghe như VI dịch ra (ít gặp hơn, nhưng nếu có là red flag — UX writer sai chiều). Native EN check: "Would this sound like a copy from a US-based product?"

---

## 3. Svid Voice — "Warm-Confident"

### 3.1 One-liner

> Svid sounds like a confident host who happens to love cinema — warm, present, never showy.

### 3.2 Anchor — diễn dịch "Nocturne Cinematic" từ visual sang language

`DESIGN.md` chốt Svid là "Obsidian Wine Cellar / Nocturne Cinematic" — wine red `#8D021F`, Inter sharp 3px, tonal layering. Đó là **visual mood**, không phải language mood.

Khi dịch sang voice:
- **Cinematic** trong ngôn ngữ KHÔNG = dramatic narration. Cinematic ngôn ngữ = **chính xác, gọn, có không gian**. Như credit phim Coen Brothers — không thừa chữ nào.
- **Warm** = personal touch nhỏ, không phải emoji rải khắp. "Bộ sưu tập của bạn" thay vì "Danh sách lưu trữ".
- **Confident** = câu xác định, không hedge ("có thể", "có lẽ", "hi vọng"). Đã làm thì nói đã làm. Lỗi thì nói lỗi, kèm action.

### 3.3 3 nguyên tắc Svid

**S1. Personal but not chatty** — Dùng "bạn" (§6) + "của bạn" khi ngữ cảnh có sense ownership ("bộ sưu tập của bạn", "tùy chọn của bạn"). KHÔNG over-personalize ("Chào Sarah!" / "Hôm nay bạn thế nào?").

**S2. Cinematic concision** — Empty state, marketing tagline, premium hero — có thể có 1 câu evocative ngắn (8-12 từ). KHÔNG run-on, KHÔNG poetry.
- ✅ "Thư viện video của bạn, ở mọi nơi."
- ❌ "Hành trình khám phá thế giới video bắt đầu từ đây với Svid — người bạn đồng hành đáng tin cậy."

**S3. Confident clarity** — Không hedge. Không "thử" / "có thể" trừ khi thật sự uncertain.
- ✅ "Đã lưu mặc định cho YouTube." (xác định)
- ❌ "Hi vọng đã lưu được tùy chọn của bạn." (hedge)

### 3.4 Svid tagline (replace "powered by Rust + Flutter")

**Chốt**: **"Tải video. Đơn giản. Đẹp." / "Save video. Simple. Beautiful."**

Reasoning từ 3 option đã cân:
- ❌ A "Thư viện video, ở mọi nơi" — "ở mọi nơi" implicit cross-device sync, app desktop-only → misleading.
- ✅ B "Tải video. Đơn giản. Đẹp." — parallel triple (Apple/Spotify pattern). Verb-first match P2. "Đẹp" capture Nocturne Cinematic mà không drama. ≤5 từ VI / 4 từ EN — fit length §9.
- ❌ C "Mọi video bạn yêu, một nơi" — "một nơi" yếu trong VI, nghe như fragment.

### 3.5 Do / Don't — Svid

| Do | Don't |
|---|---|
| "Đã tải xong • {filename}" | "✓ MISSION COMPLETE: {filename}" |
| "Tùy chọn tải" | "BÁO CÁO NHIỆM VỤ" |
| "Tải" | "INITIALIZE DOWNLOAD" |
| "Hủy" | "ABORT" |
| "Bạn còn 5 lượt tải hôm nay" | "🔥 5 lượt tải miễn phí còn lại hôm nay! Đừng bỏ lỡ!" |
| "Bộ sưu tập của bạn đang chờ. Dán link đầu tiên ở trên." | "Welcome to Svid! Your journey begins here..." |

---

## 4. VidCombo Voice — "Clean-Utility"

### 4.1 One-liner

> VidCombo sounds like a fast utility that respects your time — direct, factual, never decorative.

### 4.2 Anchor — diễn dịch "Arctic Command" từ visual sang language

DESIGN.md chốt VidCombo là "Arctic Obsidian Command" — blue `#0066CC`, DM Sans rounded 12px, floating cards, soft elevation. Visual mood = approachable utility, không cinematic.

Khi dịch sang voice:
- **Arctic** = không ấm, không lạnh. **Trung tính**. Không emotional appeal.
- **Command** = direct. Verb đầu, object sau. Không quanh co.
- **Approachable** (từ visual rounded shape) = không robotic. Có "bạn" pronoun, có câu dễ chịu, nhưng không personal touch như Svid.

### 4.3 3 nguyên tắc VidCombo

**V1. Direct over decorative** — Verb-first. Cấu trúc "[Verb] [object]" cho mọi action surface.
- ✅ "Tải" / "Hủy" / "Mở thư mục"
- ❌ "Bắt đầu tải" / "Hủy bỏ thao tác này" / "Mở thư mục chứa file đã tải"

**V2. Factual over emotional** — Empty state, marketing, snackbar — nói thẳng tình trạng. KHÔNG cinematic line, KHÔNG aspirational.
- ✅ "Chưa có lượt tải. Dán link để bắt đầu."
- ❌ "Bộ sưu tập của bạn đang chờ. Dán link đầu tiên ở trên." (đây là Svid)

**V3. Speed signals** — VidCombo dùng nhiều ở user pro / batch. Voice phải hint speed: từ ngắn, không adverb thừa, không filler.
- ✅ "Đã tải 12 file."
- ❌ "Đã hoàn tất tải xuống thành công 12 tệp tin."

### 4.4 VidCombo tagline

**Chốt**: **"Tải nhanh. Lưu sạch." / "Download fast. Save clean."**

Reasoning từ 3 option:
- ❌ A "Tải video, nhanh và sạch" — comma + conjunction = less punchy, không match V1 verb-first.
- ❌ B "Công cụ tải video nhanh" — descriptive generic, no personality.
- ✅ C — verb-first parallel imperative 2x. ≤4 từ VI / 4 từ EN. Match V1 Direct + V3 Speed signals.

### 4.5 Do / Don't — VidCombo

| Do | Don't |
|---|---|
| "Tải" | "Bắt đầu tải xuống" |
| "Đã tải 5 file." | "✨ Tuyệt vời! Đã tải xong 5 file của bạn!" |
| "Chưa có lượt tải. Dán link để bắt đầu." | "Bộ sưu tập của bạn đang chờ. Dán link đầu tiên..." |
| "Đĩa đầy. Đổi thư mục." | "Hi vọng bạn có thể giải phóng dung lượng để tiếp tục." |
| "Còn 5 lượt tải hôm nay." | "Bạn còn 5 lượt tải miễn phí trong ngày hôm nay 🎉" |

### 4.6 Svid vs VidCombo — bảng so sánh đặt cạnh nhau

| Surface | Svid | VidCombo |
|---|---|---|
| Empty state title | Bộ sưu tập của bạn đang chờ | Chưa có lượt tải |
| Empty state CTA hint | Dán link đầu tiên ở trên | Dán link để bắt đầu |
| Snackbar success (count > 1) | Đã tải xong 5 file | Đã tải 5 file |
| Snackbar error | Tải thất bại — thử lại hoặc báo lỗi | Tải thất bại. Thử lại. |
| Quota banner | Bạn còn 5 lượt tải hôm nay | Còn 5 lượt hôm nay |
| Premium upsell title | Mở khóa toàn bộ thư viện | Bỏ giới hạn lượt tải |
| Onboarding step 1 | Bắt đầu từ một liên kết bạn yêu thích | Dán link video |
| Marketing tagline | Thư viện video, ở mọi nơi | Tải nhanh. Lưu sạch. |

→ **Cùng concept, khác diction**. Vocabulary chung (Pass 03B), structure sentence khác.

---

## 5. 70/30 split — what's brand-shared, what's brand-specific

### 5.1 Rule

**70% strings dùng chung** cho cả 2 brand. Đây là core utility surface — button label, common dialog, common error, common settings.

**30% strings có brand voice riêng** — surface có brand impact: marketing, onboarding, empty hero text, premium upsell, app subtitle, app menu about/credit.

### 5.2 Concrete list — brand-specific surfaces

| Surface | Cần brand-specific? | Lý do |
|---|---|---|
| `app.subtitle` | ✅ Yes | Tagline = brand identity statement |
| `home.subtitle` | ✅ Yes | Marketing tier |
| `onboarding.*` (10 keys) | ✅ Yes | First impression, voice differentiator |
| Empty state hero (title + subtitle) | ✅ Yes | Mood-setting moment |
| Premium upsell hero text + CTA | ✅ Yes | Emotional vs functional sales |
| Quota banner phrasing | ✅ Yes | Personal vs neutral |
| About / credit screen | ✅ Yes | Brand voice fingerprint |
| What's New release notes (intro line) | ✅ Yes | Brand-flavored release |
| Snackbar success (default count = 1) | 🟡 Partial | Svid có thể "✅ Đã tải xong"; VidCombo "Đã tải" |
| Snackbar success (count > 1) | 🟡 Partial | Tương tự |
| **Buttons / actions** | ❌ No | "Tải" / "Hủy" — chung |
| **Common dialog title (Confirm Delete, …)** | ❌ No | "Xóa?" — chung |
| **Error messages diagnostic** | ❌ No | "Đĩa đầy" — chung |
| **Settings labels** | ❌ No | "Chất lượng video", "Codec âm thanh" — chung |
| **Status badge** (Downloading, Completed, Failed) | ❌ No | "Đang tải" / "Đã xong" / "Thất bại" — chung |
| **Tooltips** | ❌ No | Functional explanation — chung |
| **Context menu** | ❌ No | "Mở", "Xóa", "Sao chép URL" — chung |
| **Search placeholder** | ❌ No | Functional — chung |

### 5.2.1 Surfaces resolve via `{appName}` — KHÔNG phải brand-voice riêng

Một số surface có "brand impact" về mặt nội dung nhưng KHÔNG cần 2 voice riêng — chỉ cần resolve tên brand:

| Surface | Mechanic |
|---|---|
| Login dialog title "Login to {appName}" | `{appName}` placeholder |
| Update available "{appName} có bản mới" | `{appName}` placeholder |
| Rating prompt "Bạn thích {appName}?" | `{appName}` placeholder |
| App about credit | `{appName}` placeholder |
| Notification title (system-level OS push) | `{appName}` placeholder |

→ Một string i18n duy nhất, render ra 2 brand bằng `{appName}`. KHÔNG đếm vào 30% brand-specific.

### 5.3 Implementation

i18n key naming convention:
- Common surface: `home.foo`, `downloads.bar` — single key, both brand đọc cùng giá trị
- Brand-specific: `home.subtitle.svid`, `home.subtitle.vidcombo` — code resolve via `BrandConfig.current.brand` để pick suffix

Hoặc đơn giản hơn: dùng `BrandConfig` getter cho 30% string, không qua i18n. Pattern này đã có trong code (`BrandConfig.current.appName`).

→ Em propose **BrandConfig getter cho strings high-stakes brand-specific** (10-15 strings tổng). Lý do: đảm bảo dev không nhầm key. Còn 13 locale tương lai vẫn dùng key approach.

→ Concrete implementation chi tiết hơn ở Pass 03C khi rewrite.

---

## 6. Pronoun policy

### 6.1 VI

**Default**: `bạn` / `Bạn` / `của bạn`.
- "bạn" lowercase trong câu thường: "Bạn còn 5 lượt tải hôm nay" — đầu câu cap, nội câu lowercase.
- "của bạn" cho ownership: "tùy chọn của bạn", "lịch sử của bạn".

**Cấm**:
- ❌ `anh / chị / quý khách / em / mình` — presume hierarchy/age/gender, không hợp consumer tool.
- ❌ `tôi` (đại từ user) — không tự nhiên trong UI VI tools. (Ngoại lệ: assistant chat bot user nói với AI — `assistant.*` namespace giữ nguyên "tôi" hiện có.)
- ❌ Drop pronoun + dùng formal khác: "Quý khách vui lòng..." → KHÔNG.
- ❌ Mix "bạn" với "anh/chị" cùng app — KHÔNG. Cố định "bạn".

**Khi nào skip pronoun**:
- Button/short label: "Tải", "Hủy" — không cần "Bạn tải", "Bạn hủy".
- Settings label: "Chất lượng video" — không cần "Chất lượng video của bạn".
- Status: "Đang tải" — không cần "Bạn đang tải".

**Khi nào dùng pronoun**:
- Long-form prose: onboarding, error message diagnostic, quota banner, confirmation body.
- Personalization moment: "Đã lưu mặc định cho bạn" (vs "Đã lưu mặc định" — cả 2 OK, dùng pronoun khi muốn warmer).

### 6.1.1 Svid vs VidCombo — sub-rule pronoun

| Surface | Svid | VidCombo |
|---|---|---|
| Quota banner | "Bạn còn 5 lượt tải hôm nay" (giữ pronoun, ấm hơn) | "Còn 5 lượt hôm nay" (drop pronoun, gọn hơn) |
| Snackbar info | "Đã lưu mặc định cho bạn" | "Đã lưu mặc định" |
| Confirmation body | "File và bản ghi của bạn sẽ bị xóa khỏi máy." | "File và bản ghi sẽ bị xóa khỏi máy." |

**Rule cụ thể**: 
- VidCombo **được phép drop pronoun** ở concise surface (banner, status, single-line snackbar) khi câu vẫn rõ nghĩa không pronoun.
- Svid **prefer giữ pronoun** ở những chỗ tương đương để duy trì tone warm.
- Cả 2 brand vẫn KHÔNG dùng "anh/chị/quý khách" — drop pronoun ≠ thay pronoun.

Đây là 1 trong các cách brand differentiate ở sub-tier mà không phá pronoun system-level rule.

### 6.2 EN

**Default**: `you` / `your`.
- Direct address. Standard.

**Cấm**:
- ❌ Royal `we` trong UI thường ("We saved your preference") — sound distant. Dùng passive hoặc "you" form.
- ❌ Third-person `the user` — UI text không phải doc.

**Ngoại lệ**: Marketing copy + onboarding có thể dùng `we` cho brand voice ("We'll remember your preferences" — vibe ấm hơn "Your preferences are saved").

### 6.3 Voice Q: Mỗi brand có pronoun khác không?

**Không**. Cả Svid và VidCombo dùng cùng "bạn" / "you". Brand voice khác nhau ở **diction + sentence structure**, không ở pronoun. Pronoun = system-level rule.

---

## 7. Capitalization rule

### 7.1 VI — sentence case strict

**Rule**: Chỉ viết hoa:
1. Chữ đầu câu / đầu fragment.
2. Danh từ riêng (YouTube, TikTok, Svid, VidCombo, Cài đặt khi là menu name riêng — debatable).
3. Acronym (URL, FFmpeg ở settings — nhưng hạn chế per P1).
4. Status badge ALL CAPS (LIVE, 4K, NEW) — dùng tiết kiệm.

**Cấm**: Title Case Each Word (đang lan rộng 229 keys).

| ❌ Title Case | ✅ Sentence case |
|---|---|
| Trang Phổ Biến | Trang phổ biến |
| Mở Trình Duyệt | Mở trình duyệt |
| Tải Xuống Gần Đây | Lượt tải gần đây |
| Chất Lượng Tốt Nhất | Chất lượng tốt nhất |
| Phím Tắt | Phím tắt |
| Tải Xuống Video | Tải video |
| Chỉ Âm Thanh | Chỉ âm thanh |
| Cài Đặt Thêm | Cài đặt khác |

**Lý do**: VI grammar không có Title Case rule. Title Case là calque từ EN. Đọc nặng, kém tự nhiên. Industry: Zalo, Tiki, Shopee, Momo, MoMo, VinID — tất cả sentence case.

### 7.2 EN — selective

**Rule**:
- **Sentence case**: body text, error messages, dialog body, snackbar message, descriptions, tooltips, hint text.
- **Title Case**: tab name, navigation item, menu item, button label (nhiều từ), section title, dialog title (nhiều từ), brand-named entities ("Mission Briefing" — KHÔNG dùng nữa, but "Quality Settings" OK).
- **ALL CAPS**: status badge LIVE / 4K / NEW. Cấm cho title/heading bình thường.

| Surface | Style EN |
|---|---|
| Button "Cancel" / "Download" | Title Case (1 từ → cap) |
| Button "Save as Default" | Title Case |
| Tooltip "Open download folder" | Sentence case |
| Error "Disk full. Free up space and try again." | Sentence case |
| Section title "Download Options" | Title Case |
| Status badge "LIVE" | ALL CAPS |
| Snackbar "Downloaded 5 files" | Sentence case |
| Empty subtitle "Paste a link above to start" | Sentence case |

### 7.3 Anti-pattern: ALL CAPS title sweeping

`missionBriefing.*` ALL CAPS title (BÁO CÁO NHIỆM VỤ, TARGET INTEL, …) → **xóa**. ALL CAPS chỉ dùng cho status badge ngắn ≤4 ký tự (LIVE, 4K, HD, NEW, BETA). Title của dialog/section = sentence/title case.

---

## 8. Emoji policy

### 8.1 Per-surface allow-list

| Surface | Cho phép emoji? | Cụ thể |
|---|---|---|
| Snackbar success | ✅ Yes | `✅` đầu chuỗi (1 emoji duy nhất) |
| Snackbar info | 🟡 Selective | `✨` paste auto, `💾` save preference. Tránh spread |
| Snackbar warning | 🟡 Selective | `⚠️` hoặc bỏ |
| Snackbar error | 🟡 Selective | `❌` hoặc bỏ — nếu màu UI đã đỏ thì không cần |
| Snackbar pause/resume | ✅ Yes | `⏸` `▶` (đã có pattern) |
| Button label | ❌ No | Icon component riêng, không mix emoji vào text |
| Dialog title | ❌ No | |
| Dialog body | ❌ No | |
| Section title | ❌ No | |
| Tooltip | ❌ No | |
| Empty state | ❌ No | Icon component, không emoji |
| Error message body | ❌ No | |
| Quota banner | ❌ No | (Ngoại lệ Premium upsell Svid có thể `✨` đầu — debatable, em recommend bỏ) |
| Onboarding | ❌ No | Visual mood do illustration, không emoji |
| Settings | ❌ No | |
| Status badge | ❌ No | (Dùng dot color thay) |

### 8.2 Per-brand difference

| | Svid | VidCombo |
|---|---|---|
| Snackbar success | `✅ Đã tải xong` | `Đã tải` (no emoji, chỉ icon UI bên cạnh) |
| Snackbar success count | `✅ Đã tải xong 5 file` | `Đã tải 5 file` |
| Paste auto-detected | `✨ Đã dán link` | `Đã dán link` |
| Save preference | `💾 Đã lưu mặc định cho YouTube` | `Đã lưu mặc định` |

**Lý do**: Svid voice = warm, emoji 1-icon đầu chuỗi acceptable. VidCombo voice = utility-clean, không emoji. → emoji là 1 trong những cách 2 brand differentiate.

### 8.3 Cấm

- ❌ Multiple emoji per string (`🎉🎊✨ Đã tải xong! 🎁`).
- ❌ Emoji ở vị trí không phải đầu chuỗi.
- ❌ Emoji thay verb ("⏸ all" thay "Tạm dừng tất cả").
- ❌ Decorative emoji ở title/heading.

---

## 9. Length / density rules

### 9.1 Hard limits

| Surface | VI từ tối đa | EN từ tối đa | Note |
|---|---:|---:|---|
| Button label | 3 | 3 | "Tải", "Hủy", "Lưu mặc định" |
| Tab name | 2 | 2 | "Lịch sử", "Hàng đợi" |
| Tooltip | 6 | 5 | "Mở thư mục chứa file" |
| Section title | 4 | 4 | "Tùy chọn tải", "Chất lượng video" |
| Dialog title | 5 | 5 | "Xóa lượt tải này?" |
| Status badge | 2 | 2 | "Đang tải", "Đã tạm dừng" |
| Snackbar message | 12 | 10 | "Đã tải xong 5 file vào thư mục Downloads" |
| Error message body | 14 | 12 | "Đĩa đầy. Dọn bớt hoặc đổi thư mục lưu." |
| Empty state title | 6 | 5 | "Chưa có lượt tải" |
| Empty state subtitle | 12 | 10 | "Dán link để bắt đầu" |
| Onboarding step body | 25 | 20 | Section duy nhất cho phép dài |
| Marketing tagline | 6 | 5 | "Thư viện video, ở mọi nơi" |
| Confirmation body | 18 | 15 | Phá hủy → cần body đủ rõ |

### 9.2 Soft constraints

- Tránh stop word VI thừa: "của", "thì", "để", "rằng" cắt được thì cắt.
- Cấu trúc song song: list items cùng một grammar shape ("Tải", "Hủy", "Lưu" — không "Tải", "Hủy bỏ", "Lưu lại").
- Title không kết bằng dấu câu (period, ?, !) trừ confirmation question body.

### 9.3 Vì sao cứng vậy

Desktop power-user app, density over whitespace (`DESIGN.md` Principle 3). Mỗi pixel/từ phải earn vị trí. Câu dài = waste space + waste user attention.

---

## 10. Plural mechanic — Option A specification

### 10.1 Vấn đề (recap từ Pass 02 §2)

```dart
final plural = completedCount > 1 ? 's' : '';  // EN-only assumption
```
- EN: "Delete 5 downloads?" ✅
- VI: "Xóa 5 tải xuống đã hoàn thànhs?" 💀

### 10.2 Rule

**Không dựa vào `{plural}` placeholder**. Viết câu sao cho ngữ pháp đúng cho mọi giá trị `count`, kể cả 0 và 1.

VI có lợi thế: không pluralize bằng suffix → câu thường tự đúng nếu chọn từ count-neutral (mục, tệp, file, lượt, video, …).

### 10.3 Pattern recommendations

| Tình huống | Pattern VI | Pattern EN |
|---|---|---|
| Confirm delete count | "Xóa {count} mục?" | "Delete {count} item(s)?" hoặc "Delete {count} downloads?" (EN: dùng plural form mặc định, count=1 vẫn OK) |
| Snackbar success count | "Đã xóa {count} mục" | "Deleted {count} item(s)" |
| Status count | "{count} lượt đang tải" | "{count} downloading" |
| Selected count | "Đã chọn {count}" | "{count} selected" |

**EN strategy**: Dùng plural form mặc định ("downloads", "items", "files"). count=1 → "1 downloads" — slightly off nhưng readable. Trade-off chấp nhận.

**EN strategy alternate (better)**: Dùng "(s)" suffix ngay trong template: "Delete {count} download(s)?" — explicit, hơi formal, nhưng đúng cho mọi count.

→ Em recommend "(s)" cho EN, tránh sai 100% case.

### 10.4 Migration cho 4 plural keys hiện có

| Key | Trước | Sau (EN) | Sau (VI) |
|---|---|---|---|
| `home.clearCompletedMessage` | "Delete {count} completed download{plural}?" | "Delete {count} completed download(s)?" | "Xóa {count} mục đã hoàn thành?" |
| `home.cleared` | "✅ Cleared {count} download{plural}" | "✅ Cleared {count} download(s)" | "✅ Đã xóa {count} mục" |
| `home.deleted` | "✅ Deleted {count} file{plural} and record{plural}" | "✅ Deleted {count} file(s) and record(s)" | "✅ Đã xóa {count} tệp và bản ghi" |
| `home.clearFailedMessage` | "Delete {count} failed download{plural}?" | "Delete {count} failed download(s)?" | "Xóa {count} mục thất bại?" |

→ Code change: bỏ tham số `String plural` khỏi getter + bỏ `final plural = …` line. Pass 03C.

### 10.5 Future-proof cho 13 locale khác

Locale có nhiều plural form (Russian, Polish, Arabic) sẽ phá Option A. Khi unlock 13 locale ở v2.1:
- Option A vẫn work với locale Asian (vi, ja, ko, zh, th, id) — cùng count-neutral pattern.
- Locale slavic (ru, uk, pl, …) → cần migrate sang easy_localization plural API hoặc dùng count phrase neutral ("downloads to delete: {count}").

→ Defer decision đến v2.1. Pass 03 chỉ ship vi+en.

---

## 11. Brand-aware mechanic — `{appName}` usage

### 11.1 Rule

**Dùng `{appName}` khi**:
- String mention tên app explicit (welcome, about, marketing tagline, premium upsell mention brand).
- Setting describer mention tool API gắn với brand ("Use {appName} API only").
- Assistant chat hint ("Ask me anything about {appName}").

**KHÔNG dùng `{appName}` khi**:
- String generic không liên quan tên app.
- String functional (button, error, dialog body chung).

### 11.2 Audit kết quả 16 keys hiện có

| Key | Hiện tại | Nên giữ `{appName}`? |
|---|---|---|
| `app.name` / `app.title` | `{appName}` | ✅ Yes |
| `home.title` | `{appName}` | ✅ Yes |
| `settings.cookieImportDescription` | uses `{appName}` | ✅ Yes |
| `settingsEngine.apiOnlyDesc` | "Use {appName} API only" | ✅ Yes |
| `support.rateAppDesc` | "Share your experience with {appName}" | ✅ Yes |
| `assistant.firstMessageHint` | "Ask me anything about {appName}..." | ✅ Yes |
| `assistant.aboutDownloads` | "about {appName} downloads" | ✅ Yes |
| (10 keys khác) | varies | Audit case-by-case ở Pass 03C |

→ Pattern hiện tại OK. Không có over-use. Giữ.

### 11.3 Enforce — không hardcode brand name

- ❌ "Welcome to Svid!" → ✅ "Welcome to {appName}!"
- ❌ `'Downloads/Svid'` (preset_popover.dart leak) → ✅ `'Downloads/${BrandConfig.current.appName}'`
- ❌ "VidCombo Premium" → ✅ "{appName} Premium"

Rule: Tên brand literal **không được xuất hiện** trong i18n value hay dart string. Kiểm tra bằng grep ở Pass 03C.

---

## 12. Tone matrix per surface — concrete patterns

Mỗi surface có structure rule riêng. Bảng dưới là **patterns** — viết string mới phải fit pattern.

### 12.1 Button (action)

**Pattern**: `[Verb]` hoặc `[Verb] [object]`. ≤3 từ. Không period.
**EN**: Title Case nếu nhiều từ. Sentence case nếu 1 từ short.
**VI**: Sentence case strict.

| ✅ | ❌ |
|---|---|
| Tải / Download | INITIALIZE DOWNLOAD / Bắt đầu tải xuống ngay |
| Hủy / Cancel | Hủy bỏ / ABORT |
| Lưu mặc định / Save as Default | Lưu lại làm mặc định / SAVE AS DEFAULT |
| Mở thư mục / Open Folder | Mở thư mục đã tải |

### 12.2 Tab name / Navigation

**Pattern**: Noun phrase. ≤2 từ.
**Cùng cấu trúc**: tất cả tab cùng level cùng grammar shape.

| ✅ | ❌ |
|---|---|
| Lịch sử / History | Lịch sử tải xuống / Download History |
| Hàng đợi / Queue | Hàng đợi tải / Download Queue |
| Cài đặt / Settings | Tùy Chỉnh / SETTINGS |

### 12.3 Tooltip

**Pattern**: Short verb phrase hoặc noun phrase. ≤6 từ VI / 5 từ EN. Không period.
**Mục tiêu**: clarify icon/affordance trong 1 hover.

| ✅ | ❌ |
|---|---|
| Mở thư mục chứa file / Open folder | Click here to open the folder containing the downloaded file |
| Tải hàng loạt / Batch download | Batch Download (multiple URLs) |
| Tùy chỉnh trước khi tải / Customize before download | Mở dialog tùy chỉnh chi tiết các tùy chọn tải xuống |

### 12.4 Dialog — title + body + actions

**Title**: Statement noun phrase / question short. ≤5 từ. EN Title Case. VI sentence case.
**Body**: 1-2 câu. Diagnose + describe consequence + (optional) recommend default.
**Actions**: 2-3 button max. Primary = nội dung Verb (Xóa / Hủy), Secondary = "Cancel". Không "OK".

| Surface | Title | Body | Actions |
|---|---|---|---|
| Confirm delete (1 mục) | "Xóa lượt tải này?" | "File và bản ghi sẽ bị xóa khỏi máy. Hành động này không thể hoàn tác." | [Xóa], [Hủy] |
| Confirm delete (count) | "Xóa {count} mục?" | "File và bản ghi sẽ bị xóa khỏi máy. Hành động này không thể hoàn tác." | [Xóa], [Hủy] |
| Quality fallback | "Chất lượng không có sẵn" | "Chỉ có 720p. Tải bản này hoặc chọn lại." | [Tải 720p], [Đổi chất lượng], [Hủy] |

**Anti-pattern**: title = lệnh thay vì hỏi/statement ("XÓA NGAY!"). Body = chỉ "Are you sure?". Action = "OK / Cancel" (vague — phải nói hành động cụ thể).

### 12.5 Snackbar

**Pattern**: `[Optional emoji per §8] [Result phrase]`. ≤12 từ VI / 10 từ EN. Không period nếu ngắn.
**3 loại**: success / info / error.

| Loại | Svid VI | VidCombo VI |
|---|---|---|
| Success (1) | "✅ Đã tải xong" | "Đã tải" |
| Success (count) | "✅ Đã tải xong {count} file" | "Đã tải {count} file" |
| Info (paste auto) | "✨ Đã dán link" | "Đã dán link" |
| Info (save pref) | "💾 Đã lưu mặc định cho YouTube" | "Đã lưu mặc định cho YouTube" |
| Warning | "⚠️ Sắp hết dung lượng" | "Sắp hết dung lượng" |
| Error (action present) | "❌ Tải thất bại — thử lại" | "Tải thất bại. Thử lại." |
| Error (action absent) | "❌ Lỗi không xác định" | "Lỗi không xác định" |

**Cấm**: snackbar dài kèm full sentence với period + ! mark.

### 12.6 Empty state

**Pattern**: title (status) + subtitle (next step) + icon + optional CTA.
- Title ≤6 từ VI / 5 từ EN. Noun phrase status.
- Subtitle 1 câu, ≤12 từ VI / 10 từ EN, **phải có verb hành động**.
- Phải nói next step user làm gì để thoát empty state.

| Surface | Title | Subtitle |
|---|---|---|
| Home empty (default) — Svid | "Bộ sưu tập của bạn đang chờ" | "Dán link đầu tiên ở trên" |
| Home empty (default) — VidCombo | "Chưa có lượt tải" | "Dán link để bắt đầu" |
| Search no results | "Không tìm thấy" | "Thử từ khóa khác" |
| Filter no match | "Không có mục nào" | "Bỏ bớt bộ lọc để xem nhiều hơn" |

**Anti-pattern hiện tại**: `downloads.emptySubtitle = "Bắt đầu tải xuống từ màn hình Trang chủ"` — sai vì user ĐANG ở Home. Pass 03C fix.

### 12.7 Onboarding

**Pattern**: 3-4 step. Mỗi step: title (action verb) + body (1-2 sentence).
- Title ≤5 từ.
- Body 15-25 từ. Sentence case. Có thể có ví dụ cụ thể.
- **Đây là surface duy nhất** cho phép emotional/marketing voice.

| Step | Svid title | Svid body | VidCombo title | VidCombo body |
|---|---|---|---|---|
| 1 | "Bắt đầu từ một liên kết" | "Dán link video bạn yêu thích từ YouTube, TikTok, Instagram, hay 1000+ trang khác." | "Dán link video" | "Hỗ trợ YouTube, TikTok, Instagram và 1000+ trang khác." |
| 2 | "Chọn cách bạn muốn lưu" | "4K cho trải nghiệm điện ảnh, hay chỉ tách âm thanh — quyết định ở bạn." | "Chọn chất lượng" | "4K, 1080p, 720p, hoặc chỉ âm thanh." |
| 3 | "Quản lý mọi thứ ở một nơi" | "Theo dõi tiến trình, tạm dừng, phát file ngay — không cần rời app." | "Quản lý tải" | "Theo dõi, tạm dừng, phát file. Tất cả ở một nơi." |

### 12.8 Status badge / chip

**Pattern**: 1-2 từ. Sentence case (VI) / Title Case (EN). Hoặc ALL CAPS cho LIVE/4K/HD/NEW.

| ✅ | ❌ |
|---|---|
| "Đang tải" / "Downloading" | "ĐANG TẢI" / "Đang Tải" |
| "Đã xong" / "Completed" | "Hoàn thành" (ổn nhưng "Đã xong" gọn hơn) |
| "Tạm dừng" / "Paused" | "Đã Tạm Dừng" |
| "LIVE" / "4K" / "HD" | "Live" / "4k" |

### 12.9 Quota / banner

**Pattern**: 1 câu factual + 1 CTA action verb.

| Brand | Trạng thái | Banner text | CTA |
|---|---|---|---|
| Svid | Còn lượt | "Bạn còn {count} lượt tải hôm nay" | "Nâng cấp" |
| VidCombo | Còn lượt | "Còn {count} lượt hôm nay" | "Nâng cấp" |
| Svid | Hết lượt | "Đã hết lượt hôm nay. Nâng cấp để tải tiếp." | "Nâng cấp" |
| VidCombo | Hết lượt | "Hết lượt hôm nay. Nâng cấp." | "Nâng cấp" |

### 12.10 Premium upsell

**Svid voice**: emotional appeal, value framing.
**VidCombo voice**: feature list, direct.

| Brand | Title | Subtitle | CTA |
|---|---|---|---|
| Svid | "Mở khóa toàn bộ thư viện" | "Tải không giới hạn. 4K. Hàng loạt. Mãi mãi." | "Nâng cấp" |
| VidCombo | "Bỏ giới hạn lượt tải" | "Tải không giới hạn, 4K, batch, ưu tiên." | "Nâng cấp" |

### 12.11 Settings labels

**Pattern**: Noun phrase ≤4 từ. Description optional dưới ≤15 từ.
**P1 vẫn áp**: tên tool (yt-dlp, FFmpeg, …) OK ở settings advanced — đây là **ngoại lệ duy nhất** P1 cho phép.

| Section | Item label | Item subtitle |
|---|---|---|
| Engine | "yt-dlp Engine" | "Bộ tải video chính" |
| Engine | "Dự phòng API" | "Dùng API khi yt-dlp lỗi" |
| Format | "Codec video" | "H.264 phổ biến nhất, H.265 nhỏ hơn" |

→ Settings cho phép technical term, nhưng vẫn cần subtitle giải thích bằng đời thường.

---

## 13. Anti-patterns — explicit "do not" list

### 13.1 Vocabulary anti-patterns

Cấm xuất hiện trong UI text (trừ joke/easter egg cố ý):

| Cấm | Vì sao |
|---|---|
| MISSION BRIEFING / NHIỆM VỤ | Military jargon, không phục vụ user mental model |
| ARSENAL / KHO | Military jargon |
| TARGET INTEL / MỤC TIÊU | Military jargon |
| INITIALIZE / KHỞI ĐỘNG / KHỞI TẠO | Engineering verb — user thường nói "bắt đầu", "tải" |
| ABORT / HỦY BỎ | Aerospace/programming jargon — "Hủy" / "Cancel" đủ |
| EXECUTE / THỰC THI | Engineering verb |
| TASK / NHIỆM VỤ / TÁC VỤ | Generic engineering noun. Dùng concrete: "lượt tải", "video", "file" |
| PROCESS / TIẾN TRÌNH / QUÁ TRÌNH | Engineering noun. Dùng "tải", "đang chạy" |
| STREAM / LUỒNG | Engineering — concept "audio track" / "video track" gần user hơn |
| BINARY / NHỊ PHÂN | Engineering — "công cụ" |
| CONSOLE / BẢNG ĐIỀU KHIỂN | Enterprise jargon |
| CONFIGURATION / CẤU HÌNH | Heavy — "tùy chọn", "cài đặt" gần user |
| OPERATION / VẬN HÀNH | Industrial jargon — dùng "chạy", "đang làm" |
| MODULE / MÔ-ĐUN | Engineering noun — "phần", "công cụ" |
| COMPONENT / THÀNH PHẦN | Engineering noun — chỉ OK ở settings advanced |
| BUFFER / ĐỆM | Engineering — không user-facing |
| (… thêm khi gặp) |

**Edge case có ý kiến**: "ENGINE / ĐỘNG CƠ" — hiện app dùng "yt-dlp Engine" ở settings. Borderline. **Verdict**: cho phép trong settings advanced (subtitle giải thích đời thường), KHÔNG cho phép ở in-flow surface.

### 13.2 Grammar anti-patterns

- ❌ Title Case mỗi từ trong VI.
- ❌ ALL CAPS title dialog/section.
- ❌ Multi-emoji per string.
- ❌ Question form khi không phải yes/no thật.
- ❌ Hedge words ("có thể", "có lẽ", "thử", "hi vọng") trong status xác định.
- ❌ Royal "we" trong UI thường EN.
- ❌ Honorific VI ("anh/chị/quý khách").
- ❌ Period sau title (button, tab, section, chip).
- ❌ Exclamation mark `!` trong functional text (chỉ OK ở marketing/onboarding).

### 13.3 Structure anti-patterns

- ❌ Empty state subtitle dẫn user đi nơi khác khi user đang ở đúng surface.
- ❌ Error message chỉ mô tả, không action verb.
- ❌ String dài gấp đôi limit §9.1 mà không lý do.
- ❌ Inconsistent tense trong cùng namespace (mix "đã tải xong" với "tải xong" với "vừa tải").
- ❌ Mix register trong cùng dialog ("Save as default" cạnh "MISSION BRIEFING").

---

## 14. Stitch prompt addendum — wire voice spec vào AI design

### 14.1 Rule

Khi prompt Stitch tạo screen mới, **bắt buộc** thêm voice spec vào prompt để AI sinh copy đúng tone, không chế "INITIALIZE DOWNLOAD" lần nữa.

### 14.2 Voice prompt block (dán sau DESIGN.md token block)

**Cho Svid**:
```
COPY VOICE — Warm-Confident:
- Pronouns: "you / your". Personal but not chatty.
- Tone: confident clarity, no hedge words. Cinematic concision (≤12 words per line).
- Sentence case for body. Title Case only for nav/button labels (≤3 words).
- Emoji: ✅/✨/💾 OK as 1-icon prefix in snackbars only. Never in titles.
- Banned vocabulary: MISSION, ARSENAL, INITIALIZE, ABORT, TASK, PROCESS, STREAM, BINARY, CONSOLE, CONFIGURATION.
- Use plain words: "Download" not "Initialize Download". "Cancel" not "Abort". "Options" not "Configuration".
- Empty state: warm 1-line title + 1-line next-step. Example: "Your library is waiting. / Paste your first link above."
- Error: diagnosis + action verb. Example: "Disk full. Free up space and retry."
- Marketing: aspirational but never grandiose. ≤6 words.
```

**Cho VidCombo**:
```
COPY VOICE — Clean-Utility:
- Pronouns: "you / your". Direct, factual, no emotional appeal.
- Tone: verb-first, speed signals. ≤10 words per line.
- Sentence case for body. Title Case only for nav/button labels (≤2 words).
- Emoji: NO emoji in any UI string. Icons via component, not text.
- Banned vocabulary: same Svid list + no aspirational lines.
- Use functional concrete: "Save here" not "Add to your library".
- Empty state: factual title + next-step. Example: "No downloads yet. / Paste a link to start."
- Error: diagnosis + period + action. Example: "Disk full. Free up space."
- Marketing: feature-list direct. ≤5 words.
```

### 14.3 Khi nào skip Stitch copy output

Stitch thường sinh copy on-the-fly để mockup screen. **Coi đây là gợi ý**, không phải final. Final copy luôn pass qua VOICE.md + TERMINOLOGY.md trước khi commit vào i18n.

→ Workflow: Stitch sinh mockup → designer xem visual + structure → engineer extract layout → write copy theo VOICE.md → commit.

---

## 15. Application rule for developers — viết string mới như thế nào

### 15.1 Quyết định cây 6 bước

```
1. Concept của string là gì? (download, audio, cancel, …)
   → tra TERMINOLOGY.md → có nhãn canonical chưa?
       Có  → dùng đúng nhãn đó.
       Chưa → request thêm vào TERMINOLOGY.md (PR), KHÔNG tự đặt inline.

2. Surface là gì? (button / dialog / snackbar / empty / error / tooltip / settings / onboarding)
   → tra §12 — có pattern không?
       Có  → fit pattern (length, structure, emoji rule).
       Chưa → propose pattern mới ở §12 (PR), bao gồm rationale.

3. Brand-specific?
   → tra §5.2 — surface nằm trong 30% brand-specific list?
       Yes → viết 2 version (Svid + VidCombo) hoặc dùng BrandConfig getter.
       No  → viết 1 version chung.

4. Pronoun + capitalization
   → §6 + §7 — apply rule.

5. Length check
   → §9 — đếm từ. Quá → cắt.

6. Anti-pattern check
   → §13 — string có chứa banned vocab? Có ALL CAPS không cần thiết? Có Title Case VI?
   Pass → ✅ commit.
```

### 15.2 Code review checklist (cho reviewer)

```
[ ] String đi qua i18n (không hardcode dart literal)?
[ ] Concept dùng nhãn từ TERMINOLOGY.md?
[ ] Brand name không hardcode (dùng {appName} hoặc BrandConfig)?
[ ] Pattern surface đúng §12?
[ ] Pronoun + capitalization đúng §6 + §7?
[ ] Length within §9?
[ ] Không chứa banned vocab §13?
[ ] Plural an toàn (không xài `{plural}` literal append)?
[ ] EN + VI có cả 2, không có VI = EN?
[ ] EN + VI cùng nói 1 thứ (semantic match)?
```

→ Pass 03C sẽ tạo lint rule (analyze custom hoặc grep-based pre-commit hook) cho 3-4 check tự động được.

---

## 16. Trạng thái + bước tiếp

- ✅ Pass 03A VOICE.md — **CHỐT** (Chairman delegate self-answer V1-V10, em đã reasoning + apply refinement vào doc)
- ⏳ Pass 03B TERMINOLOGY.md — em đi tiếp luôn
- ⏳ Pass 03C — apply (rewrite home keys + fix bugs + kill hardcoded) — sau 03B

**V1-V10 self-answer record:**

| # | Câu hỏi | Verdict | Refinement đã apply |
|---|---|---|---|
| V1 | Voice anchors | ✅ Giữ "Warm-Confident" + "Clean-Utility" | — |
| V2 | 7 principle thiếu | ⚠ Thêm P8 | **P8 Native first, not translated** đã add §2 |
| V3 | Svid tagline | ✅ Đổi sang B | "Tải video. Đơn giản. Đẹp." chốt §3.4 |
| V4 | VidCombo tagline | ✅ Giữ C | "Tải nhanh. Lưu sạch." chốt §4.4 |
| V5 | 70/30 split | ✅ Đủ + thêm note | Note §5.2.1 về surface resolve qua `{appName}` |
| V6 | Pronoun | ✅ "bạn" cả 2 + nuance | §6.1.1 VidCombo selective drop, Svid keep |
| V7 | VI sentence case sweep | ✅ Yes | — |
| V8 | Emoji policy | ✅ Svid selective / VidCombo none | Pass 03C: snackbar accept icon component (eng task) |
| V9 | Plural Option A | ✅ Yes | — |
| V10 | Anti-vocab | ⚠ Thêm 4 | OPERATION/MODULE/COMPONENT/BUFFER add §13.1; ENGINE edge-case clarified |

**Edge case cần document riêng** (em note ngắn, không expand vì không gốc):
- **Notification system-level OS push** → vẫn theo VOICE.md, brand resolve qua `{appName}`.
- **Platform conventions** ("Sign in with Google", "Open System Settings…") → override VOICE.md, theo standard platform.
- **Legal / Terms of Service** → register pháp lý riêng, KHÔNG theo VOICE.md.
- **Date/time relative** ("2 phút trước") → chuẩn hoá qua `intl` package, không tự sinh mỗi screen.

Em đi 03B luôn. KHÔNG đụng code/i18n cho đến khi 03B chốt.

---

**Reminder**: File này là **firmware ngôn ngữ**. Đổi voice principles (§2-§4) sau ship = re-train user mental model = chi phí cao. Đừng đổi vì 1 string khó chịu — fix string đó. Đổi voice chỉ khi audit định kỳ phát hiện voice drift hệ thống.
