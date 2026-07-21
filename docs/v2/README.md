# V2 UI/UX Campaign — Working Set Index

**Branch**: `v2/home-redesign-foundation`
**Base**: `main @ d5545a71` (2026-05-04 — last Windows installer hardening)
**Setup turn**: 2026-05-05

Mục tiêu nhánh này: **chuyển hóa 3 input từ CEO Ngọc Kỳ thành 1 working set rõ ràng + đầy đủ**, sẵn sàng cho campaign nâng cấp UI/UX toàn app (SSvid + VidCombo).

> **Định vị tổ chức**
> - **CEO Ngọc Kỳ** (kynndev) = REQUIREMENT layer — ship spec / mockup / design tokens
> - **Desktop CTO + Chairman** = EXECUTION layer — audit, design, code, ship
> - Chỉ chuyển vận spec, không tự paraphrase. Khi spec vs mockup vs intent chat lệch nhau → escalate.

---

## 1. Three inputs từ CEO Ngọc Kỳ

| # | Input | Format | Đã chuyển hóa vào |
|---|---|---|---|
| 1 | Branch `kynndev/claude/sharp-diffie-f83a32` (HEAD `806bd308`) | Git remote (kynndev fork landing repo) | 5 docs + 2 font files (xem §2) |
| 2 | Mockup ảnh chụp UI Home V2 | JPG (1152×776) | `docs/v2/mockups/home-v2-mockup-001.jpg` |
| 3 | Zalo chat 2026-05-05 (3 message bursts + 3 feature flags) | text | `docs/v2/requirements-from-ceo-ky.md` |

---

## 2. Spec & Asset Map

### Mandatory specs (anh Kỳ flag, ưu tiên cao nhất)

| File | Size | Vai trò |
|---|---:|---|
| `docs/SSvid_Home_Download_Manager_UI_Spec_v1.1.md` | 51K | **PRIMARY UI SPEC** — "v1.5 content" sau Gemini external review fix 4 P1 |
| `docs/SSvid_v2_Implementation_Roadmap.md` | 22K | **PRIMARY PLAN** — phase / milestone |
| `docs/SSvid_v2_Design_Spec.md` | 49K | **DESIGN SYSTEM** — tokens, font, color, component spec |
| `assets/fonts/InterVariable.ttf` | 859K | Variable font weights 100-900 |
| `assets/fonts/Inter-LICENSE.txt` | 4.3K | SIL OFL v1.1 |

### Reference / context (không mandatory)

| File | Size | Vai trò |
|---|---:|---|
| `docs/SSvid_Home_Download_Manager_UI_Spec.md` | 18K | Bản v1.0 cũ — superseded by v1.1, giữ làm history |
| `docs/FIGMA-MCP-CLAUDE-SETUP.md` | 17K | Figma MCP setup (đã có sẵn trên main, không phải V2-specific) |
| `docs/v2/mockups/home-v2-mockup-001.jpg` | 248K | Visual reference Home V2 |
| `docs/v2/requirements-from-ceo-ky.md` | — | Chat nguyên văn + 3 feature flags + open questions |

### KHÔNG commit (theo CLAUDE.md convention)

| File | Lý do |
|---|---|
| `memory/master_roadmap.md` (trên branch anh Kỳ) | `memory/` là gitignored — phase tracking local only. Đọc tham khảo, không đem vào nhánh execution. |

---

## 3. Three new mandatory features (chi tiết ở `requirements-from-ceo-ky.md`)

| ID | Tính năng | Conflict với code hiện tại |
|---|---|---|
| F1 | Profile tải mặc định dùng ngay ở box search (chip `MP4·1080p ▾`) | Hiện format/quality chọn POST-extract trong `video_details_modal` |
| F2 | "Playlist của tôi" — user gom file thành playlist | `lib/features/downloads/.../collections_screen.dart` đã tồn tại — cần audit gộp/tách |
| F3 | Player play được list (queue) | `lib/features/player/` (31 files MediaKit) — chưa rõ khả năng queue |

---

## 4. Workflow downstream (đã thống nhất với Chairman)

1. **Setup turn (turn này)** — chuyển hóa 3 input → working set. Không commit, không code.
2. **Discussion turns (sắp tới, one-by-one)** — đào sâu từng topic theo thứ tự:
   - (A) Đọc `SSvid_v2_Design_Spec.md` → lập design tokens nền
   - (B) Đọc `SSvid_Home_Download_Manager_UI_Spec_v1.1.md` → UI logic
   - (C) Đọc `SSvid_v2_Implementation_Roadmap.md` → phase hóa
   - (D) Đối chiếu spec ↔ mockup, flag mọi divergence
   - (E) Audit code hiện tại vs spec (3 feature mới F1/F2/F3 đặc biệt)
   - (F) Multi-brand consideration (SSvid vs VidCombo)
3. **Implementation turns (sau khi anh duyệt strategy)** — code, theo phase đã chốt.

---

## 5. Cảnh báo

- Branch nguồn `kynndev/claude/sharp-diffie-f83a32` phân kỳ rất xa khỏi `origin/main` (983 files, +44k/-200k). **TUYỆT ĐỐI KHÔNG `git merge` thẳng** — sẽ xóa các Windows installer hardening fix vừa ship. Đây là lý do em selective extract chỉ requirement files.
- Spec V2 chưa xác định scope multi-brand. VidCombo có 25× user base SSvid Go DB — quyết định scope sai sẽ block release.
- Mockup có thể đã lệch khỏi spec v1.1 (v1.1 = post-Gemini-review fix). Khi đào, ưu tiên spec text > mockup > chat intent — escalate khi mâu thuẫn.
