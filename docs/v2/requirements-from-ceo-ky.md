# V2 UI/UX Campaign — Requirements từ CEO Ngọc Kỳ

**Ngày**: 2026-05-05
**Nguồn**: Zalo chat — Ngọc Kỳ (`kynndev`) ↔ Đinh Văn Mỹ (Chairman)
**Vai trò**: CEO Kỳ = REQUIREMENT layer (spec / reference, có thể mandatory). Desktop CTO = EXECUTION layer.

---

## 1. Source — chat nguyên văn

```
[05/05/2026 01:30:04] Ngọc Kỳ:
  🔗 GitHub
  Latest commit: 4052f89f
  Branch: claude/sharp-diffie-f83a32
  Files:
    docs/Svid_Home_Download_Manager_UI_Spec_v1.1.md (v1.5 content)
    docs/Svid_v2_Implementation_Roadmap.md

[05/05/2026 01:30:26] Ngọc Kỳ:
  em view qua tài liệu V2 cho màn Home nhé

[05/05/2026 08:05:47] Đinh Văn Mỹ: Oke anh

[05/05/2026 08:07:08] Ngọc Kỳ:
  A có commit thêm 2 file đặc tả design token nữa đó

[05/05/2026 08:13:18] Đinh Văn Mỹ: acc kynndev đúng ko a
[05/05/2026 08:15:29] Ngọc Kỳ: Đúng r e

[05/05/2026 08:15:36] Ngọc Kỳ:
  A vừa thêm font:
  assets/fonts/
  ├── InterVariable.ttf  (880KB — variable font, weights 100-900)
  └── Inter-LICENSE.txt  (SIL OFL v1.1)

[05/05/2026 08:18:20] Ngọc Kỳ:
  Với giao diện mới có mấy cái cần lưu ý:
  1: profile tải được sử dụng ở box search.
  2. Thêm tính năng "playlist của tôi" -> gom file vào playlist.
  3. Player có thể play được list.

[05/05/2026 08:19:28] Ngọc Kỳ:
  3 tính năng này là mới -> trước mắt anh vẫn đưa vào plan,
  ae cố gắng hoàn thành luôn.
```

---

## 2. Source artifacts (đã chuyển hóa vào nhánh local)

| Artifact | Nguồn | Đích trong repo | Status |
|---|---|---|---|
| UI Spec v1.1 (v1.5 content) | `kynndev/svid_app@claude/sharp-diffie-f83a32` | `docs/Svid_Home_Download_Manager_UI_Spec_v1.1.md` | mandatory primary spec |
| Implementation Roadmap | same | `docs/Svid_v2_Implementation_Roadmap.md` | mandatory plan |
| Design Spec (tokens) | same | `docs/Svid_v2_Design_Spec.md` | mandatory design system |
| UI Spec v1.0 (legacy) | same | `docs/Svid_Home_Download_Manager_UI_Spec.md` | history reference, superseded by v1.1 |
| Inter Variable font | same | `assets/fonts/InterVariable.ttf` (+ LICENSE) | mandatory typography asset |
| Mockup ảnh chụp | Zalo image attachment | `docs/v2/mockups/home-v2-mockup-001.jpg` | reference visual (có thể đã lệch khỏi spec text — Gemini review fix 4 P1) |
| Master roadmap (memory) | `kynndev/...:memory/master_roadmap.md` | KHÔNG commit (memory/ gitignored theo CLAUDE.md) | reference only |

---

## 3. Three new mandatory features (anh Kỳ flag cuối chat)

> "3 tính năng này là mới → trước mắt anh vẫn đưa vào plan, ae cố gắng hoàn thành luôn."

### F1 — Profile tải dùng ở box search

- Visible trong mockup ảnh: chip `MP4 · 1080p ▾` cạnh nút Download
- Mở dropdown 5 dòng "Tùy chọn tải mặc định": Định dạng / Chất lượng / Khi không có chất lượng / Vị trí lưu / Mở cài đặt nâng cao
- **Conflict cần resolve**: hiện tại format/quality chọn ở `video_details_modal` SAU khi extract. F1 là PRE-extract default. Cần spec rõ flow.

### F2 — "Playlist của tôi" (gom file vào playlist)

- User-curated, KHÔNG phải YouTube playlist tự động
- Chip filter `Playlist` trong tab Lịch sử (visible trong mockup)
- **Conflict cần resolve**: `lib/features/downloads/.../collections_screen.dart` đã tồn tại. Phải audit: gộp khái niệm, hay tách riêng?

### F3 — Player play được list

- Queue / autoplay / khả năng next-prev qua một danh sách
- **Liên kết F2**: playlist của tôi → đưa vào player queue
- **Stack hiện**: `lib/features/player/` 31 files MediaKit-based — cần audit khả năng queue

---

## 4. Open questions (chưa xác định, cần answer khi đào sâu spec)

1. **Multi-brand**: spec V2 áp dụng cho cả Svid + VidCombo, hay Svid only? (Mockup chỉ có brand Svid)
2. **F1 default-vs-override**: nếu user pre-set MP4 1080p nhưng video không có 1080p → spec dropdown nói "Khi không có chất lượng → Gần nhất" — ai quyết định "gần nhất"? Server-side hay client?
3. **F2 schema**: anh Kỳ commit có Drift schema fix (FK type mismatch — Downloads.id IntColumn). Đây là SCHEMA change → cần migration plan.
4. **F3 scope**: chỉ video, hay cả audio playlist? Continuous play across formats?
5. **Mockup vs spec**: image gửi có thể đã lệch khỏi `_v1.1.md` (vì v1.1 = "v1.5 content" sau Gemini review). Khi xung đột — ưu tiên spec text hay mockup?
6. **Inter font**: thay thế font hiện tại toàn app, hay chỉ V2 screens?
7. **Roadmap timeline**: anh Kỳ chốt deadline chưa? Phase hóa thế nào?
8. **CEO authority level**: 3 feature mới — "mandatory" hay "đề xuất ưu tiên"?

---

## 5. Boundary

- Anh Kỳ ship REQUIREMENT. Desktop CTO ship EXECUTION.
- Spec text là source of truth. Mockup là visual reference. Chat là intent.
- Khi 3 nguồn lệch nhau → flag explicit, KHÔNG tự ý chọn → escalate Chairman.
