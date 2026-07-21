# Pass 2D — Mockup vs Spec Audit

**Mockup**: `docs/v2/mockups/home-v2-mockup-001.jpg` (1152×776, 248K)
**Specs**: `SSvid_v2_Design_Spec.md` v1.2 + `SSvid_Home_Download_Manager_UI_Spec_v1.1.md` v1.5
**Mục tiêu**: Pixel-by-pixel + copy-by-copy audit, identify mọi divergence, classify priority (P0 must-fix / P1 spec wins / P2 mockup wins / P3 cosmetic).

---

## 1. Executive summary (TL;DR)

1. **🔴 P0 BLOCKER divergence: Tab 2 = "Hàng đợi tải" mockup vs "Playlist của tôi" spec** — mockup violate UI Spec §8.1 + §10. Hàng đợi tải KHÔNG tồn tại như tab trong spec; queue items hiển thị inline trong tab Lịch sử (queued state).

2. **🟠 P1 cosmetic divergence: "Đã hoàn thành" badge text** — mockup show old copy; UI Spec §17.1 step 6 mandate đổi → "Đã tải". Update i18n.

3. **🟠 P1 audio row inconsistency: "MP4 320kbps"** — mockup row 5 (Lofi audio) hiển thị "MP4 320kbps" — không có MP4 audio-only ở 320kbps. Phải là **"MP3 320kbps"** hoặc **"M4A 320kbps"**. Mockup error.

4. **🟢 Pass 1 "4-tab divergence" CONFIRMED FALSE positive — spec §2 list 5-tab structure đúng align mockup**: Trang chủ / Đăng ký / Chuyển đổi / Trình duyệt + (right) Nâng cấp. Mockup ↔ spec match.

5. **🟢 Filter chip set [Tất cả/Video/Audio/Playlist]**: Mockup OK với UI Spec §8.1 — filter chip row tách rời với filter popover. "Playlist" chip filter list theo media type (video chứa playlist source).

6. **🟠 P2 brand color render**: Mockup CTA + active tab dùng **blue tone** (~`#2563EB`-`#3B82F6`). Spec v1.2 mandate **Wine Red `#8D021F`** cho brand. → Mockup được render trước v1.2 brand fix; visual đã obsolete cho SSvid identity. Phải re-render mockup khi triển khai.

7. **🟢 5 row state demo subset OK**: Mockup show completed + downloading + queued + failed + completed-audio. Spec mandate 9 states; mockup là DEMO subset, không phải requirement subset.

8. **🟢 Free tier banner copy "Bạn còn 15 lượt tải hôm nay" + "Nâng cấp ngay →"** — match UI Spec §7 plan strip exactly. SSvid 15-quota correct.

9. **🟢 Right rail layout OK**: Bắt đầu nhanh 3-step + Mở nhanh website 3×3 (9 sites + "Thêm") + Tip card. Match spec §6.

10. **🟠 P2 missing dark mode preview**: Mockup chỉ light mode. Spec mandate dark mode complete (§13). Implementation phải support cả 2.

---

## 2. Top bar audit

| Element | Mockup | Spec §2/§3 | Status |
|---|---|---|---|
| Logo | "SSvid" với squircle red logo + wine icon | Logo present | ✅ |
| Tab 1 | "Trang chủ" (active, blue underline) | Trang chủ ✓ | ✅ |
| Tab 2 | "Đăng ký" với play icon | Đăng ký ✓ | ✅ |
| Tab 3 | "Chuyển đổi" với refresh icon | Chuyển đổi ✓ | ✅ |
| Tab 4 | "Trình duyệt" với globe icon | Trình duyệt ✓ | ✅ |
| Right cluster | [Nâng cấp pill ⭐ blue] [🔔 6 badge] [⚙️ settings] [🌙 theme] [─□✕ window] | Nâng cấp + notification + settings + theme + window controls ✓ | ✅ |
| Premium + Nâng cấp mutual exclusion | User free → only Nâng cấp visible | §3 mandate ✓ | ✅ |

**Verdict**: Top bar 100% spec-aligned. Pass 1 agent flag "4 tab vs 3 tab divergence" was misread of §3 (which talks about MUTUAL EXCLUSION rule, not tab count). §2 layout table is the source of truth and has 4 navigation tabs.

---

## 3. Smart input + control bar audit

| Element | Mockup | Spec §4 | Status |
|---|---|---|---|
| Section label | "Link hoặc từ khóa" | (not explicit in spec) | ✅ Acceptable header |
| Input field | "Dán link video, playlist, kênh hoặc nhập từ khóa..." | Spec L119 same exactly | ✅ Match |
| Clear icon | `[X]` button right side | Spec L120 implicit | ✅ |
| History icon | clock icon, label "Lịch sử" below | Spec L114 + L120 | ✅ |
| Batch icon | layered stack icon, label "Tải hàng loạt" below | Spec L114 + L121 | ✅ |
| **Customize icon ⚙️** | 🔴 **MISSING in mockup** | Spec §4 L114 + L122 mandate it as 3rd icon between Batch and Preset | 🔴 **P1 spec wins** — mockup outdated, missing ⚙️ icon |
| Preset chip | `[MP4 · 1080p ▾]` | Spec L123 same | ✅ Match |
| Primary CTA | Blue button "Tải xuống" with download icon | Spec L124 — note "không có dropdown" ✓ | ✅ |
| Icon labels below | "Lịch sử" / "Tải hàng loạt" inline labels | Spec say "Icon-only with tooltip" — mockup adds caption labels | 🟠 P2 — mockup more verbose than spec. OK to keep labels OR use tooltip per spec. CTO decide. |

**Verdict**: 1 P1 missing element (⚙️ Customize icon between Batch + Preset). Spec wins — implementation MUST add ⚙️ icon.

---

## 4. Preset popover (open state) audit

Mockup show popover OPEN with header "Tùy chọn tải mặc định" + 5 rows.

| Spec §5.2 row | Mockup | Status |
|---|---|---|
| Profile section header "── Profile ──" | 🔴 **MISSING** | 🔴 Mockup missing entire profile selector section |
| 6 built-in profiles list (Tự động, 1080p MP4, 720p tiết kiệm, Audio MP3 320k, 4K cao nhất, Lưu trữ) | 🔴 **MISSING** | 🔴 Spec wins — popover MUST show profile list with 🔒 builtin |
| User-created presets section | 🔴 **MISSING** | 🔴 |
| "+ Tạo profile mới..." CTA | 🔴 **MISSING** | 🔴 |
| Header "── Tùy chỉnh nhanh ──" | 🔴 **MISSING** (mockup has no section header, just 5 rows) | 🟠 |
| Row 1: Định dạng MP4 (Video) | ✅ Match | ✅ |
| Row 2: Chất lượng 1080p | ✅ Match | ✅ |
| Row 3: Khi không có chất lượng → Gần nhất | ✅ Match | ✅ |
| Row 4: Vị trí lưu Downloads/SSvid `[Đổi]` | ✅ Match (no `[Đổi]` button) | 🟠 P2 — `[Đổi]` button missing in mockup, spec has it |
| Header "── Tùy chọn nâng cao ──" | 🔴 **MISSING** | 🔴 |
| Toggle "Tuỳ chỉnh chuyên sâu trước khi tải" + helper text | 🔴 **MISSING** | 🔴 Spec wins — Tier 2 toggle MUST be present |
| "Mở cài đặt tải nâng cao →" link | ✅ Match (last row "Mở cài đặt tải nâng cao →") | ✅ |

**Verdict**: 🔴 **MAJOR DIVERGENCE — popover mockup ~40% incomplete**. Missing entire Profile selector section + Tier 2 toggle. Spec §5.2 layout block diagram is much more comprehensive than mockup demo. Implementation MUST follow spec, not mockup.

→ Mockup là demo "minimal default config" view, KHÔNG phải full popover spec.

---

## 5. Plan strip audit

| Element | Mockup | Spec §7 | Status |
|---|---|---|---|
| ⭐ Premium icon | Yes (purple star) | (implicit "Gói miễn phí" prefix) | ✅ |
| "Gói miễn phí" label | ✅ | ✅ | ✅ |
| "Bạn còn **15** lượt tải hôm nay" | "Bạn còn 15 lượt tải hôm nay" | spec L438 exactly | ✅ Match |
| "Nâng cấp ngay →" CTA | "Nâng cấp ngay →" link blue | spec L438 say "Nâng cấp →" — mockup adds "ngay" | 🟠 P3 cosmetic — "Nâng cấp" vs "Nâng cấp ngay". Either acceptable. |
| Layout placement | Below smart input, above tabs | Spec §2 layout map ✓ | ✅ |

**Verdict**: ✅ Plan strip aligned. SSvid 15-quota matches BrandConfig. **VidCombo would show 10 (per CLAUDE.md flutter-frontend rules)** — multi-brand handling at runtime via BrandConfig.

---

## 6. Tabs + filter audit

| Element | Mockup | Spec §8.1 + §10 | Status |
|---|---|---|---|
| **Tab 1** | "Lịch sử tải xuống" (active blue underline) | "Lịch sử tải xuống" ✓ | ✅ |
| **Tab 2** | 🔴 **"Hàng đợi tải"** | 🔴 **"Playlist của tôi"** (spec §8.1 L468 + §10 entire feature) | 🔴 **P0 BLOCKER** |
| Filter chips | `[Tất cả ✓]` `[Video]` `[Audio]` `[Playlist]` | Spec §8.1 L470 say toolbar includes "Filter" icon → popover (media type, platform, status, tags, watch state). Mockup show inline chips (subset) | 🟠 P2 — mockup chip row "Tất cả/Video/Audio/Playlist" can co-exist với filter popover (media-type quick filter). Tracker: ensure both tracks coexist. |
| Search box | "Tìm trong lịch sử..." | Spec §8.1 L486 same | ✅ |
| Sort dropdown | "Mới nhất ▾" | Spec §8.1 L473-478 (Mới nhất default + 5 alternatives) ✓ | ✅ |
| View toggle | List icon active + Grid icon outline | Spec §8.1 L484 ✓ | ✅ |

**🔴 P0 BLOCKER explanation**:
- "Hàng đợi tải" trong mockup = render queue management as separate tab.
- Spec §8.3 row state `queued` (state #4) = queue items hiển thị **INLINE** trong History tab as rows with "Đang chờ" badge + drag handle ≡.
- Spec §10 Tab 2 = "Playlist của tôi" (user-curated permanent playlists), which is the primary new feature F2.
- **Mockup violates spec**. Resolution: implementation MUST render Tab 2 as "Playlist của tôi" (spec §10), NOT "Hàng đợi tải".
- **Backstory hypothesis**: Mockup designer (anh Kỳ?) iterated UI before spec §10 finalized, used queue-tab placeholder, never updated. Easy fix in implementation phase.

---

## 7. Download row audit (5 demo rows)

| # | Mockup row | State per UI Spec §8.3 | Issues |
|---|---|---|---|
| 1 | Full Version Âm Mưu... 29:17 thumbnail · "**Đã hoàn thành**" green badge · MP4 1080p 224.51 MB 28/04/2026 14:21 · [▶] [⋮] | `completed` | 🟠 P1 — spec mandates đổi badge text → **"Đã tải"** (UI Spec §17.1 step 6) |
| 2 | Nhạc Chill... 16:9 thumbnail · "Đang tải 43%" blue progress bar · 1.02 GB / 2.38 GB · 12.4 MB/s · Còn 1m 32s · [⏸] [⋮] | `downloading` | ✅ Match spec L511 metadata format exactly |
| 3 | Top 50 Bài Hát TikTok 2026 (Playlist) · audio waveform thumb · "Trong hàng đợi" badge · 50 video · 0 B / 3.24 GB · Chờ xử lý · [⏰] [⋮] | `queued` | 🟠 P2 — spec L513 metadata format `Đang chờ · 0 B / 3.24 GB` (no "50 video" preamble or "Chờ xử lý" suffix). Mockup more verbose. Spec wins for consistency. |
| 4 | Phim Hành Động... · "**Tải lỗi**" red badge · "Không thể tải video. Vui lòng thử lại." · [↻] [⋮] | `failed` | ✅ Match spec L516 |
| 5 | Đừng Hỏi Em Ổn Không 03:45 audio thumb · "**Đã hoàn thành**" green badge · **MP4 320kbps** 8.45 MB 28/04/2026 10:15 · [▶] [⋮] | `completed audio variant` | 🔴 P1 ERROR — **"MP4 320kbps"** không hợp lý (MP4 không phải audio-only format ở 320kbps). Phải là **"MP3 320kbps"** hoặc **"M4A 320kbps"** — audio variant per spec L520-521. Mockup typo. |

**Verdict**: 1 P1 i18n update + 1 P1 mockup error + 2 P2 metadata format minor differences. All resolvable in implementation.

---

## 8. Right rail audit

### 8.1 Bắt đầu nhanh card

| Element | Mockup | Spec §6 | Status |
|---|---|---|---|
| Card header "● Bắt đầu nhanh" với blue dot | OK | Spec say "onboarding 3 bước, dismissible" | ✅ |
| Step 1 icon (link) + "Dán link hoặc nhập từ khóa" + helper "Dán link video, playlist, kênh hoặc nhập từ khóa bạn muốn tìm." | OK | ✅ | ✅ |
| Step 2 icon (filters) + "Xem kết quả & chọn định dạng" + helper "Ứng dụng sẽ tự nhận diện và hiển thị kết quả phù hợp để bạn lựa chọn." | OK | ✅ | ✅ |
| Step 3 icon (download) + "Tải xuống & lưu" + helper "Tải về thiết bị và xem offline mọi lúc, mọi nơi." | OK | ✅ | ✅ |
| Dismiss button | 🔴 MISSING | Spec say "dismissible (lưu state vào SharedPreferences)" | 🟠 P1 — implementation must add dismiss `[X]` button |

### 8.2 Mở nhanh website grid

| Element | Mockup | Spec §6 + §6.2 | Status |
|---|---|---|---|
| Card header "● Mở nhanh website" với blue dot | OK | Spec L411-413 ✓ | ✅ |
| 3×3 grid: YouTube / TikTok / Facebook / Instagram / X (Twitter) / Reddit / Pinterest / Vimeo / **"Thêm"** (with `⋯` icon) | 9 cells | Spec L413 list 8 sites + "Thêm website" → 9 cells | ✅ Match |
| Site logos | Color brand logos (YT red, TikTok black, FB blue, IG gradient, X black, Reddit orange, Pinterest red, Vimeo cyan) | (no explicit spec) | ✅ |
| Click behavior platform-specific | Not visible from static mockup | Spec §6.2 mandate Windows fallback to system browser | ⏳ Implementation detail |
| Tooltip platform-specific | Not visible | Spec §6.2 mandate | ⏳ Implementation detail |

### 8.3 Tip card

| Element | Mockup | Spec | Status |
|---|---|---|---|
| 💡 "Mẹo: Kéo & thả link video vào ô nhập để bắt đầu nhanh hơn." | Yes | Spec không explicit (hidden default per §6 list "Không hiển thị mặc định: Storage, Session Pulse, Download Details, Shortcuts, Tip card") | 🟠 **P2 CONFLICT** — spec say tip card HIDDEN default, mockup show it visible. CTO autonomous decide: keep tip card (mockup) OR hide (spec). |

---

## 9. Footer audit

| Element | Mockup | Spec | Status |
|---|---|---|---|
| Left: "● Sẵn sàng" with green dot | Yes | Spec không explicit | ✅ Acceptable (status indicator) |
| Right: "SSvid v2.0.0" | Yes | Per CLAUDE.md "Never hardcode version — use package_info_plus" | ✅ Conceptually OK; implementation MUST use `package_info_plus` not hardcoded "2.0.0" |

---

## 10. Brand color audit

| Element | Mockup | Spec v1.2 mandate | Status |
|---|---|---|---|
| CTA "Tải xuống" button | Bright blue ~`#3B82F6` | **Wine Red `#8D021F`** | 🔴 P1 brand violation |
| Active tab "Trang chủ" underline | Blue | Wine Red | 🔴 P1 |
| Active filter chip "Tất cả" border | Blue | Wine Red | 🔴 P1 |
| "Nâng cấp" pill text | Blue | (no mandate, but consistent brand) | 🟠 P2 |
| Notification bell "6" badge | Red | Standard error color OK | ✅ |
| Plan strip "Nâng cấp ngay →" link | Blue | (no mandate, link can be info color) | 🟠 P2 |
| Onboarding step icons background | Light blue | Spec §2.0 + Pass 2A: brand Wine Red | 🟠 P2 |

**Critical insight**: Mockup được render trong v1.0/v1.1 spec era khi brand color = Tailwind blue. **Spec v1.2 changelog L10 explicit revert to Wine Red**. → Mockup obsolete cho final brand identity. Implementation **MUST use Wine Red** per Spec v1.2 + existing `BrandConfig.SSvidBrand.colors.brand = #8D021F`. Mockup re-render needed when implementation done.

---

## 11. Theme mode audit

Mockup chỉ light mode. UI Spec §13 + Design Spec §13 mandate dark mode complete coverage.

| Status | Action |
|---|---|
| Light mode ✅ visible in mockup | OK |
| Dark mode 🔴 NOT in mockup | Implementation phải build cả 2; mockup re-render dark variant later |

→ **Pass 2A Q4 decision**: SSvid default `ThemeMode.dark` (Nocturne Cinematic), mockup chỉ là 1 mode demo.

---

## 12. Resolution priorities

### P0 BLOCKERS (must fix before ship)

| # | Item | Action |
|---|---|---|
| P0.1 | Tab 2 "Hàng đợi tải" (mockup) → "Playlist của tôi" (spec) | Implementation render Tab 2 as Playlist tab per spec §10 |

### P1 HIGH (spec wins, must align)

| # | Item | Action |
|---|---|---|
| P1.1 | Customize icon ⚙️ missing in mockup control bar | Add ⚙️ between Batch icon + Preset chip per spec §4 |
| P1.2 | Preset popover incomplete (~40% missing — Profile section + Tier 2 toggle) | Build full popover per spec §5.2 layout |
| P1.3 | Badge text "Đã hoàn thành" → "Đã tải" | i18n update vi/en (per Q8 cut from 5→2 lang) |
| P1.4 | Audio row "MP4 320kbps" → "MP3 320kbps" | Implementation use correct format string for audio variant |
| P1.5 | Brand color blue → Wine Red `#8D021F` | Use `AppColors.brand` / `colorScheme.primary` runtime, NOT hardcoded |
| P1.6 | Bắt đầu nhanh dismiss button missing | Add `[X]` per spec §6 "dismissible" |

### P2 MEDIUM (cosmetic / negotiable)

| # | Item | Action |
|---|---|---|
| P2.1 | Tip card visible (mockup) vs hidden default (spec) | **CTO decision**: keep visible (mockup mạch lạc UX hơn). Override spec §6 hidden-by-default rule. |
| P2.2 | Icon labels below History/Batch (mockup) vs tooltip-only (spec) | Em đề xuất giữ labels (better discoverability). |
| P2.3 | "Vị trí lưu Downloads/SSvid" — `[Đổi]` button missing in mockup | Implementation add per spec |
| P2.4 | Queued row metadata "50 video · 0 B / 3.24 GB · Chờ xử lý" verbose | Trim per spec L513 format `Đang chờ · 0 B / 3.24 GB`. |
| P2.5 | "Nâng cấp ngay →" vs "Nâng cấp →" | Either OK; em đề xuất "ngay" cho stronger CTA. |

### P3 COSMETIC (nice-to-have)

| # | Item | Action |
|---|---|---|
| P3.1 | Footer status "Sẵn sàng" | Implementation OK as nice indicator |
| P3.2 | Footer version stamp | Use `package_info_plus`, not hardcoded |

---

## 13. Decisions Pass 2D resolves

| ID | Resolution |
|---|---|
| Pass 1 "Tab count divergence" | ❌ False positive — confirmed mockup ↔ spec §2 align. CLOSED. |
| Mockup Tab 2 = "Hàng đợi tải" | 🔴 Spec wins. Implementation Tab 2 = "Playlist của tôi". CTO autonomous. |
| Brand color render | 🔴 Spec v1.2 wins. Wine Red mandatory. Mockup re-render after implementation. CTO autonomous. |
| Tip card visibility | 🟠 P2 — em decide keep visible (mockup). CTO autonomous. |
| Dark mode coverage | Implementation build both light + dark; mockup chỉ light demo. CTO autonomous. |

→ **No new Q for Chairman**. Pass 2D fully CTO-autonomous.

---

## 14. Status sau Pass 2D

| ✓ | Hoàn thành |
|---|---|
| ✅ | Re-load mockup ảnh + cross-ref full spec |
| ✅ | Top bar 100% verified ↔ spec §2 align (closes Pass 1 false flag) |
| ✅ | Smart input + control bar audited |
| ✅ | Preset popover gap analysis (~40% missing in mockup) |
| ✅ | Plan strip ↔ spec §7 verified |
| ✅ | Tab 2 P0 BLOCKER identified (Hàng đợi tải vs Playlist) |
| ✅ | 5 row demo state-by-state cross-ref |
| ✅ | Right rail (Bắt đầu nhanh + Mở nhanh website + Tip) verified |
| ✅ | Brand color obsolete blue → mandate Wine Red |
| ✅ | 1 P0 + 6 P1 + 5 P2 + 2 P3 issues categorized |
| ✅ | Zero new Chairman decisions needed (CTO autonomous) |

| ⏳ | Pending |
|---|---|
| ⏳ | Pass 2E — Multi-brand strategy (final research pass) |
| ⏳ | Pass 2F — Hyper-plan synthesis (consolidate all 5 findings docs into 1 executable plan) |
