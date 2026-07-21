# Pass 2A — Design Spec Foundation Deep Dive

**Spec đọc**: `docs/SSvid_v2_Design_Spec.md` v1.2 (1322 dòng), tập trung §0-§8 (foundation tokens, ~570 dòng)
**Code đối chiếu**: `lib/core/theme/{app_colors,app_typography,app_theme}.dart` + `lib/core/config/brand_config.dart` + `pubspec.yaml`
**Mục tiêu**: Map tokens spec ↔ tokens code, identify divergence, plan migration.

---

## 1. Executive summary (TL;DR cho Chairman)

1. **🟢 "Wine Red vs Tailwind blue contradiction" Pass 1 flag → RESOLVED IN-DOC**: Spec v1.2 changelog L10 explicit revert to Wine Red. Tables §2.1/§2.2/§2.4 vẫn list Tailwind blue tokens nhưng L84 mark là **DEPRECATED — use existing AppColors directly**. Không phải bug, chỉ là legacy reference table chưa cleanup. Code hiện tại đã đúng.
2. **🟢 Codebase đã RICHER than spec acknowledges**: `app_colors.dart` có ~120 tokens (vs spec ~25), brand-aware via `BrandConfig`, context-aware helpers. `app_typography.dart` có 16 base styles + 8 Mission Briefing tokens. Spec v1.2 explicit "use existing classes as authoritative source" — nghĩa là V2 KHÔNG rewrite, chỉ ADD missing tokens.
3. **🔴 PHANTOM Inter font — silent bug đã tồn tại**: Code `fontFamily: 'Inter'` nhưng `pubspec.yaml fonts:` section ĐANG COMMENTED. App đang chạy với **system fallback** không phải Inter bundle. macOS có thể có Inter native (14+) nên không lộ; Windows/Linux đa số rơi xuống Segoe UI / generic sans-serif. Pass 2A Block #1 phải fix.
4. **🟠 Multi-brand gap đã có tone trong code, KHÔNG có trong spec**: BrandConfig đã 100% multi-brand-aware (SSvid Wine Red + dark default + 3px radius + Inter; VidCombo Arctic Blue + light default + 12px card radius / 999px button radius + DM Sans). Spec V2 chỉ nói SSvid → áp dụng tokens spec sẽ phá VidCombo. → Phải resolve ở Pass 2E.
5. **🟠 NEW tokens missing trong code**: Spec define `AppSpacing` / `AppRadius` / `AppShadow` / `AppMotion` / `AppIconSize` / `AppComponentSize` / `AppBreakpoint` / `AppMinWidth` ở `lib/core/design/design_tokens.dart` — file này CHƯA tồn tại trong nhánh v2/home-redesign-foundation. Phải tạo Phase 1A.
6. **🟢 Mission Briefing + Home Dark Operator tokens — pre-existing investment**: 35 + 69 call sites. KHÔNG mentioned trong spec nhưng đã ship. V2 KHÔNG được vứt — phải ngầm preserve hoặc spec phải acknowledge.

---

## 2. Side-by-side: Spec ↔ Code

### 2.1 Color system

| Spec section | Spec status | Code reality | Verdict |
|---|---|---|---|
| §2.0 Brand identity (Wine Red `#8D021F` source of truth) | MUST | `BrandConfig.SSvidBrand.colors.brand = #8D021F` ✓ | ✅ Match |
| §2.1 Primitive Tailwind palette (10 hue × 10 shade) | DEPRECATED in v1.2 (L11) | Code KHÔNG dùng raw Tailwind palette | ✅ Correct (table is reference cruft, can drop) |
| §2.2 Semantic tokens light (`bg.app #F6F8FB`, `accent.primary #0B63F6`...) | DEPRECATED in v1.2 | Code dùng `BrandConfig.lightColorScheme` (Wine Red `#8D021F` primary, NOT Tailwind blue) | ✅ Correct, spec table = stale |
| §2.3 Row state colors (9 row state combos) | NOT DEPRECATED — actively used | Code có `lightStatus*` + `darkStatus*` constants (`app_colors.dart:167-187`) — 5 trạng thái: Active/Completed/Paused/Failed/Cancelled. **Thiếu**: `postProcessing`, `pending`, `waitingForNetwork` (4 trạng thái thiếu so spec §8.3 9 trạng thái) | 🟠 Gap — bổ sung 4 token mới |
| §2.4 Dark mode mapping | DEPRECATED in v1.2 | Code dùng `BrandConfig.darkColorScheme` brand-aware | ✅ Correct |
| §2.5 Color usage rules ("never pure black/white", "destructive=red-600", "selection=accent.primary-subtle") | MUST | Code đã follow (`darkLightText: #F5F2F3` not `#FFFFFF`; `darkBase: #151214` not `#000000`) | ✅ Match |

**Pre-existing tokens KHÔNG mentioned trong spec** (cần spec acknowledge):
- Audio format badges: `audioFormatMP3/M4A/Opus/Wav/Flac/Default` (`app_colors.dart:106-111`)
- Mission Briefing: `darkSurfaceLowest`, `lightSurfaceLowest`, `accentSecondary`, `accentTertiary` (35 call sites)
- Home Dark Operator: `homeDarkAppBg/CardBg/CardHover/CardSelected/CardActive/Border*/Text*/InputBorder/AccentSoft` (69 call sites)
- Semantic bg pairs: `warningBgDark/Light`, `dangerBgDark/Light`, `warningTextDark/Light`, `dangerTextDark/Light`
- Status colors: `statusDownloading`, `statusQueued`, `statusPostProcessing`, `statusInProgress`, `incognitoAccent`

### 2.2 Typography

| Spec section | Spec status | Code reality | Verdict |
|---|---|---|---|
| §3.0 API authoritative (`displayLarge` 48/700, `bodyMedium` 13/400, `appBarTitle` 16/600...) | MUST — use existing | `AppTypography.textTheme` Material 3 + 13 custom styles (`appBarTitle/sectionHeader/fileName/metadata/buttonPrimary/buttonSecondary/input/inputHint/platformName/statusBadge/navItem/navItemSelected/compact/mini`) | ✅ Match — code phong phú hơn spec |
| §3.1 Font stack: Inter bundled `assets/fonts/InterVariable.ttf` weights 100-900, fallback `-apple-system/Segoe UI Variable/Cantarell/system-ui` | **MUST** | **🔴 Inter PHANTOM**: `pubspec.yaml fonts:` section L171-180 COMMENTED OUT (sample skeleton từ Flutter init). `assets/fonts/InterVariable.ttf` mới pull về turn này (chưa wired). `google_fonts ^6.3.2` dependency vẫn ở L110 nhưng `main.dart:48` set `allowRuntimeFetching=false`. App SSvid render với **system fallback**, không phải Inter bundle. | 🔴 Pass 2A Block #1 |
| §3.1 Migration: remove `google_fonts` dependency | MUST (v1.2 changelog L12) | Dependency vẫn còn L110, KHÔNG có call site ngoài `main.dart:48` (chỉ disable fetch flag) | 🟠 Cleanup — remove dependency |
| §3.2 Type scale (display.xl 32/700 → caption 12/400 → button 14/600 → code 13/400 monospace) | MUST | Code dùng Material 3 textTheme (displayLarge 48/700 — KHÁC spec display.xl 32/700) + custom styles. Type scale spec ≠ code spec | 🟠 Cần align — spec §3.2 vs code §3.0 |
| §3.3 Rules ("body weight 400 line-height 1.5", "no underline trừ link", "italic tiết kiệm") | RECOMMENDED | Code follow (no widget có decoration: underline, italic rare) | ✅ Match |
| Mission Briefing tokens (`commandTitle 18/w900`, `briefingSection 14/w900`, `briefingCardTitle 13/w800`, ...) | NOT MENTIONED IN SPEC | 8 custom styles + 35 call sites trong download config dialog | 🟢 Pre-existing — preserve |

### 2.3 Spacing & layout

| Spec section | Spec status | Code reality | Verdict |
|---|---|---|---|
| §4.1 Scale 8-point grid (`xxs 2 / xs 4 / sm 8 / md 12 / lg 16 / xl 24 / 2xl 32 / 3xl 48 / 4xl 64`) + intermediate `lgPlus=20`, `xxlPlus=40` | MUST | **🔴 KHÔNG có `AppSpacing` class** — code dùng raw `EdgeInsets.all(16)`, `SizedBox(height: 24)` rải rác | 🔴 Pass 2A Block #2 — tạo `lib/core/design/design_tokens.dart` |
| §4.2 Layout grid (page 1440 max, padding 24, column gap 24, left col min 600, right col 320) | MUST | Một số widget có hardcoded width nhưng chưa centralize | 🟠 Migrate progressively |
| §4.3 Breakpoints (compact/medium 1024 / large 1280 / xlarge 1536) | MUST | Code có `BrandConfig` không có `AppBreakpoint` class | 🟠 Tạo Phase 1A |
| §4.4 Min-widths multi-level (window 1024×720 enforced ở OS layer; layout-level; component-level; truncation rules) | MUST | KHÔNG có `AppMinWidth` class. Window min size có thể đã set ở `MainFlutterWindow.swift` macOS — cần check | 🟠 Tạo Phase 1A + audit native side |

### 2.4 Border radius / Shadow / Motion / Icons (§5-§8)

| Spec | Code reality | Verdict |
|---|---|---|
| §5 Radius: `none 0 / xs 2 / sm 4 / md 8 (default) / lg 12 / xl 16 / 2xl 24 / round 999` | `BrandConfig.cardRadius/buttonRadius/inputRadius/dialogRadius/chipRadius/popupRadius` — SSvid all `3` (Nocturne angular), VidCombo varied (`12 / 999 / 8 / 12 / 999 / 8`). **Conflict**: spec default = 8 (`md`), code SSvid = 3 toàn bộ | 🔴 **Brand intent conflict** — spec áp dụng SSvid sẽ phá Nocturne Cinematic angular identity |
| §6 Shadow elevation (`sm/md/lg/xl/2xl`, layered Material 3, dark 1.5× opacity) | `BrandConfig.glowSubtle/glowIntense/glowCta` cho premium accents. KHÔNG có generic `AppShadow` class. SSvid `cardElevation = 0` (flat), VidCombo `cardElevation = 2` | 🟠 Tạo `AppShadow` không phá brand elevation policy |
| §7 Motion: `instant 0 / fast 100 / normal 200 / slow 300 / slower 500` + 6 easing curves + reduced-motion respect | `lib/core/theme/app_transitions.dart` có routes transitions. KHÔNG có `AppMotion` token class. Reduced-motion compliance chưa rõ | 🟠 Tạo `AppMotion` + audit a11y |
| §8 Icons: Material Icons (built-in), 6 sizes (xs 14 → 2xl 32), outlined-default + filled-active, 60+ name mapping | Code dùng `Icons.*` rải rác — KHÔNG có `AppIconSize` class | 🟠 Tạo `AppIconSize` + audit consistency với mapping table §8.4 |

---

## 3. Multi-brand impact for V2 tokens

| Token group | SSvid current | VidCombo current | V2 spec impact |
|---|---|---|---|
| Brand color | Wine Red `#8D021F` | Arctic Blue `#0066CC` | Spec say "Wine Red". Áp dụng nguyên xi sẽ phá VidCombo. **Resolution**: V2 spec chỉ apply lên SSvid — VidCombo continues qua BrandConfig override. |
| Font family | Inter (phantom hiện tại) | DM Sans (phantom hiện tại — DM Sans cũng KHÔNG bundled) | Cả 2 brand đều phantom font. V2 ship Inter bundle cho SSvid. **Câu hỏi cho Chairman**: VidCombo nên giữ DM Sans hay unify Inter? DM Sans có ý nghĩa branding "Arctic Command geometric" — nếu unify Inter sẽ mất brand differentiation. |
| Card radius | 3px (Nocturne angular) | 12px (Arctic frosted) | Spec default 8px. **Conflict** với cả 2 brand. → Spec default chỉ áp dụng cho generic components mới; brand-shaped components giữ nguyên BrandConfig values. |
| Button radius | 3px | 999px (pill) | Same — brand-specific, spec không override |
| Theme mode default | dark (Nocturne Cinematic) | light (Arctic Clarity) | Mockup ảnh anh Kỳ là **light mode**. Spec không nói. → Confirm: dark default cho SSvid V2 vẫn giữ? |
| Free tier quota | 15 | 10 | Banner copy spec say "15 lượt" cứng — phá VidCombo. → Banner phải brand-aware (đọc từ `BrandConfig` chứ không hardcode). |

---

## 4. Pass 2A Blockers (cần resolve trước Pass 2B/2C)

### 🔴 Block #1 — PHANTOM Inter font (silent existing bug)
**State hiện tại**:
- `pubspec.yaml` L171-180 COMMENTED `fonts:` section (sample placeholder từ flutter create)
- `assets/fonts/InterVariable.ttf` đã có (commit 69e05683) nhưng KHÔNG declare ở pubspec
- `app_typography.dart:15` reference `'Inter'` nhưng Flutter ngầm fallback to system
- macOS 14+ có Inter pre-installed → app SSvid trên macOS render đúng Inter (system, không phải bundle)
- Windows / Linux không có Inter system → silently render Segoe UI / generic sans-serif
- `google_fonts ^6.3.2` dependency vẫn ở pubspec L110, `main.dart:48` set `GoogleFonts.config.allowRuntimeFetching = false` (kill switch)

**Action**:
1. Declare `fonts:` section trong pubspec wrap `assets/fonts/InterVariable.ttf` cho 'Inter' family
2. (VidCombo) Quyết định: bundle DM Sans tương tự, HOẶC unify Inter cho cả 2 brand (giảm brand differentiation)
3. Remove `google_fonts ^6.3.2` dependency (chỉ kill switch ở main.dart, không có call site khác → safe to remove)
4. Smoke test: Windows VM verify Inter render correct
5. **Risk**: Visual regression khi Inter bundle khác Inter system trên macOS — ít rủi ro vì InterVariable.ttf v4.1 = upstream truth

### 🔴 Block #2 — Missing `lib/core/design/design_tokens.dart`
**State hiện tại**: Spec reference file này khắp `AppSpacing.lg`, `AppRadius.md`, `AppShadow.md`, `AppMotion.normal`, `AppIconSize.lg`, `AppMinWidth.leftColumn`. File CHƯA tồn tại.

**Action**:
1. Tạo `lib/core/design/design_tokens.dart` với 8 classes:
   - `AppSpacing` (9 tokens + 2 intermediate)
   - `AppRadius` (8 tokens, default `md`)
   - `AppShadow` (6 levels light + dark variants)
   - `AppMotion` (5 durations + 6 easing curves)
   - `AppIconSize` (6 sizes)
   - `AppComponentSize` (button heights, input heights, etc.)
   - `AppBreakpoint` (4 breakpoints + helper methods `isCompact()`, `isMedium()`, etc.)
   - `AppMinWidth` (window + 4 layout regions + 13 component minimums)
2. KHÔNG đụng `AppColors` / `AppTypography` (spec v1.2 deprecate duplicate)
3. Migrate raw `EdgeInsets.all(16)` → `EdgeInsets.all(AppSpacing.lg)` progressively (Phase 1A scope)

### 🟠 Block #3 — 4 row states thiếu trong `AppColors`
Spec §2.3 + §8.3 spec 9 row states; code có 5. Thiếu: `postProcessing`, `pending` (separate from `queued`), `waitingForNetwork`. Code có sẵn `statusPostProcessing`/`statusPostProcessingLight` nhưng không đủ container variant. → Bổ sung trong Phase 1B (Manager rows).

---

## 5. Decisions cần Chairman chốt (gửi anh Kỳ confirm)

| # | Câu hỏi | Em đề xuất |
|---|---|---|
| Q1 | **Spec §2.1/§2.2/§2.4 Tailwind blue tables — keep as legacy or DELETE?** | **Delete** — tránh confusion future engineers. Add note "use AppColors directly" thay thế. Send to anh Kỳ. |
| Q2 | **Spec §3.2 Type scale (display.xl 32 → caption 12) vs code Material 3 (displayLarge 48 → bodySmall 12) — align cái nào?** | **Code wins** — spec §3.0 đã explicit "use existing classes". Spec §3.2 là nice-to-have intent, không deprecate code. Mark §3.2 là "internal design language guide", không phải engineer reference. |
| Q3 | **VidCombo font — keep DM Sans hay unify Inter?** | **Keep DM Sans** — brand differentiation (Arctic Command geometric vs Nocturne humanist). Phải bundle DM Sans tương tự Inter. **Cost**: ~870KB asset thêm, nhưng VidCombo nếu publish phải có font đúng dù V2 không nói. |
| Q4 | **Default theme mode SSvid V2 = dark hay light?** | Mockup là light. SSvid hiện default `ThemeMode.dark` (Nocturne). **Đề xuất**: giữ dark default, mockup chỉ là 1 mode demo — cả 2 mode phải support đầy đủ (a11y). |
| Q5 | **Card radius mâu thuẫn (spec default 8px vs SSvid 3px Nocturne angular)** — apply theo brand hay theo spec? | **Brand wins** cho brand-defining components (cards, buttons, inputs) — đây là Nocturne identity. Spec 8px chỉ cho NEW generic components không brand-specific (vd: empty state illustrations, generic dialogs). |
| Q6 | **Mission Briefing + Home Dark Operator tokens (35+69 call sites) — preserve hay refactor về spec?** | **Preserve** — đây là pre-existing brand investment, V2 spec không acknowledge nhưng cũng không deprecate. Add inline comment "// Mission Briefing — operator-grade, pre-V2 investment" cho clarity. |

---

## 6. Migration plan high-level (input cho Pass 2C)

**Scope Phase 1A foundation token block** (subset của roadmap Phase 1A 6.5d):

```
Day 1 (foundation):
  - Tạo lib/core/design/design_tokens.dart 8 classes
  - Wire pubspec.yaml fonts: section (Inter bundle)
  - Remove google_fonts dependency
  - Smoke test 3 platforms

Day 2 (color completeness):
  - Bổ sung 4 row state token (postProcessing/pending/waitingForNetwork pairs)
  - Document Mission Briefing + Home Dark Operator tokens (inline comment)
  - Verify VidCombo override path works

Day 3 (window min size):
  - Wire AppMinWidth.appWindow → MainFlutterWindow.swift (macOS) / win32_window.cpp (Windows) / Linux equivalent
  - Test resize prevention

Day 4-6.5 (gradual migration):
  - Migrate home_screen.dart, video_details_modal, app_scaffold raw EdgeInsets/SizedBox → AppSpacing
  - Continue Phase 1A spec items (smart_input_bar, smart_cta_button, customize_icon_button, ...)
```

KHÔNG breaking change: existing `AppColors` / `AppTypography` API stable. Chỉ ADD `AppSpacing`/`AppRadius`/etc. Existing widgets vẫn run.

---

## 7. Status sau Pass 2A

| ✓ | Hoàn thành |
|---|---|
| ✅ | Đọc full Design Spec §1-§8 (570 dòng) |
| ✅ | Đối chiếu `app_colors.dart` (320 dòng) ↔ spec §2 |
| ✅ | Đối chiếu `app_typography.dart` (327 dòng) ↔ spec §3 |
| ✅ | Đối chiếu `brand_config.dart` (805 dòng) ↔ spec §2.0 + §5 |
| ✅ | Audit pubspec.yaml fonts state |
| ✅ | Phát hiện PHANTOM Inter font silent bug |
| ✅ | Phát hiện 35+69 call sites token chưa được spec acknowledge |
| ✅ | Resolve 7 contradictions Pass 1 flagged (đa số là deprecated reference, không phải bug) |
| ✅ | Đề xuất 6 decision points cho Chairman + anh Kỳ |

| ⏳ | Chờ |
|---|---|
| ⏳ | Chairman duyệt 6 decision points (Q1-Q6) |
| ⏳ | Anh Kỳ confirm Q1, Q3, Q5 (REQUIREMENT layer decisions) |
| ⏳ | Pass 2B: UI Spec v1.1 deep dive (Smart input + Preset 3-layer + Manager + Playlist) |
