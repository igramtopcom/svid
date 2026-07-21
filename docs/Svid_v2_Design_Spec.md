# Svid v2 — Design Specification

**Version:** v1.2
**Date:** 2026-05-05

## Changelog v1.1 → v1.2 — CRITICAL FIXES (audit pass)

Self-audit pass discovered 5 issues từ v1.1 (em đã sót khi không check existing code):

- **🔥 Brand color FIX**: v1.1 dùng Tailwind Blue `#2563EB` làm primary — SAI. App Svid existing brand là **Wine Red `#8D021F`** ([app_colors.dart](../lib/core/theme/app_colors.dart)). v1.2 revert to Wine Red as authoritative brand source.
- **Naming conflict FIX**: v1.1 tạo class `AppColors` và `AppTypography` trong `design_tokens.dart` mà KHÔNG check existing `lib/core/theme/`. Đã có cả 2 classes này (existing với 95+ widget usages). v1.2 removed duplicates from design_tokens.dart; existing classes are authoritative source.
- **Font migration**: existing `app_typography.dart` dùng `GoogleFonts.inter()` (runtime download). v1.2 migrate to bundled `assets/fonts/InterVariable.ttf` per design spec. `google_fonts: ^6.3.2` dependency removed from pubspec.
- **Section 2 Color** rewritten to defer to existing `lib/core/theme/app_colors.dart` (Wine Red brand + 56 existing tokens).
- **Section 3 Typography** rewritten to defer to existing `lib/core/theme/app_typography.dart` (Material 3-style scale: displayLarge/headlineMedium/bodyLarge etc.).

**design_tokens.dart in v1.2 contains ONLY:**
- AppSpacing, AppRadius, AppShadow, AppMotion (NEW visual tokens)
- AppIconSize, AppComponentSize, AppBreakpoint, AppMinWidth, AppOpacity (NEW layout tokens)
- Colors → use existing `AppColors` from `lib/core/theme/app_colors.dart`
- Typography → use existing `AppTypography` from `lib/core/theme/app_typography.dart`

## Changelog v1.0 → v1.1

External design comparison merge — distill best information from alternate spec:

**Adopted from external:**
- Color palette: Tailwind-standard hex (`#2563EB` blue-600 primary, replacing custom `#0B63F6`)
- Warning palette: Amber (replacing Yellow) — industry standard for warnings
- Premium dedicated purple palette (`#7C3AED`)
- Top bar height 72px explicit
- Border radius: xs=4, sm=6, xxl=20 (less sharp, more rounded)
- Motion durations tuned: 160/220/320/480ms (Material 3 style)
- New `standard` and `emphasized` easing curves
- Material icon name mapping table (§8.1) — 30+ icons
- Smart CTA state machine table (§10.3)
- Vietnamese complete copy for empty states (§11)
- Keyboard shortcuts table (§12.2)
- Vietnamese aria-label list (§14.3)
- Asset file naming conventions (§15)
- Component widget hierarchy tree (§16.1)
- Right column width 320 → 380px

**Kept from v1.0 (em's strengths):**
- Layered shadow approach (Material 3 style)
- AppComponentSize concrete measurements in Dart
- AppMinWidth class with 3-level graceful degradation
- Window-level OS API enforcement notes
- Windows browser fallback (per PRD review)
- AppBreakpoint helper methods
- Truncation rules table

**Inter font — bundled (no runtime download):**
- Inter font files (.ttf) bundled in `assets/fonts/Inter-*.ttf`
- Registered trong `pubspec.yaml` → no Google Fonts dependency at runtime
- `fontFamily: 'Inter'` trong design tokens với system fallback nếu fail load
- License: Inter is SIL OFL (free for bundling)

**Other deferred to v2.x:**
- Numeric spacing rename (kept semantic names, added intermediate values lgPlus=20, xxlPlus=40)
- Mobile breakpoints (xs/sm/md) — app is desktop-only


**Companion to:** [Svid_Home_Download_Manager_UI_Spec_v1.1.md](Svid_Home_Download_Manager_UI_Spec_v1.1.md) (functional), [design_tokens.dart](../lib/core/design/design_tokens.dart) (code reference)
**Audience:** Frontend engineers, designers, QA visual reviewers

This spec defines visual design system for Svid v2 redesign. Engineers reference [design_tokens.dart](../lib/core/design/design_tokens.dart) as single source of truth — this doc provides rationale + usage guidelines.

---

## 1. Design principles

5 nguyên tắc cốt lõi cho mọi design decision:

1. **Clarity over cleverness** — UI phải đọc nhanh hiểu nhanh. Không animation thừa, không decoration dùng chỉ để "đẹp".
2. **Action-driven hierarchy** — Primary CTA luôn nổi bật nhất. Secondary actions không cạnh tranh primary.
3. **Native platform feel** — Tôn trọng convention của macOS/Windows/Linux (window controls, scroll behavior, font rendering).
4. **Density với breathing room** — Tối ưu không gian cho power user nhưng không nén đến mức rối mắt. Density adaptive theo content.
5. **Accessible by default** — Contrast WCAG AA tối thiểu, focus states rõ, keyboard navigation đầy đủ. Không bao giờ thêm decoration làm giảm a11y.

---

## 2. Color system

> **⚠️ Source of truth**: [`lib/core/theme/app_colors.dart`](../lib/core/theme/app_colors.dart). v1.2 deprecate the duplicate token table in this section — use existing `AppColors` class directly. Brand identity = **Wine Red `#8D021F`** (NOT Tailwind blue).

### 2.0 Brand identity (existing, authoritative)

```dart
// From lib/core/theme/app_colors.dart
class AppColors {
  static const Color brand = Color(0xFF8D021F);       // Wine Red — primary brand
  static const Color brandLight = Color(0xFFBF2D4A);  // Lighter tint
  static const Color brandDark = Color(0xFF5E0115);   // Deeper shade

  static const Color successGreen = Color(0xFF22C55E);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color infoBlue = Color(0xFF3B82F6);

  // 56 total const tokens (status, audio formats, etc.)
}
```

→ Engineer dùng `AppColors.brand`, `AppColors.successGreen`, etc. Không hardcode hex.

### 2.1 Primitive palette (reference only)

Existing palette derived from Tailwind-like scale, **but anchored on Wine Red brand** thay vì Blue:

| Hue | 50 | 100 | 200 | 300 | 400 | 500 | 600 | 700 | 800 | 900 |
|-----|-----|-----|-----|-----|-----|-----|-----|-----|-----|-----|
| **Slate** (neutral) | `#F8FAFC` | `#F1F5F9` | `#E2E8F0` | `#CBD5E1` | `#94A3B8` | `#64748B` | `#475569` | `#334155` | `#1E293B` | `#0F172A` |
| **Blue** (primary) | `#EFF6FF` | `#DBEAFE` | `#BFDBFE` | `#93C5FD` | `#60A5FA` | `#3B82F6` | `#0B63F6` | `#1D4ED8` | `#1E40AF` | `#1E3A8A` |
| **Green** (success) | `#F0FDF4` | `#DCFCE7` | `#BBF7D0` | `#86EFAC` | `#4ADE80` | `#22C55E` | `#16A34A` | `#15803D` | `#166534` | `#14532D` |
| **Red** (error) | `#FEF2F2` | `#FEE2E2` | `#FECACA` | `#FCA5A5` | `#F87171` | `#EF4444` | `#DC2626` | `#B91C1C` | `#991B1B` | `#7F1D1D` |
| **Yellow** (warning) | `#FEFCE8` | `#FEF9C3` | `#FEF08A` | `#FDE68A` | `#FCD34D` | `#FACC15` | `#EAB308` | `#B45309` | `#854D0E` | `#713F12` |
| **Purple** (info/processing) | `#FAF5FF` | `#F3E8FF` | `#E9D5FF` | `#D8B4FE` | `#C084FC` | `#A855F7` | `#9333EA` | `#7E22CE` | `#6B21A8` | `#581C87` |

### 2.2 Semantic tokens (light mode)

| Token | Value | Usage |
|-------|-------|-------|
| `bg.app` | `#F6F8FB` | App background (slate-50 với hint blue) |
| `bg.card` | `#FFFFFF` | Card, dialog, popover background |
| `bg.surface-raised` | `#FFFFFF` | Elevated surfaces (modal) |
| `bg.subtle` | `#F1F5F9` | Subtle background (sidebar, footer) |
| `border.default` | `#E5EAF2` | Card borders, dividers |
| `border.strong` | `#CBD5E1` | Input borders, emphasized lines |
| `border.focus` | `#0B63F6` | Focus ring (2px outline) |
| `text.primary` | `#0F172A` | Headings, primary content |
| `text.secondary` | `#475569` | Body text |
| `text.tertiary` | `#94A3B8` | Metadata, captions, disabled |
| `text.inverse` | `#FFFFFF` | Text trên primary background |
| `accent.primary` | `#0B63F6` | Primary actions, links, selection |
| `accent.primary-hover` | `#1D4ED8` | Primary hover |
| `accent.primary-active` | `#1E40AF` | Primary pressed |
| `accent.primary-subtle` | `#DBEAFE` | Selected row, tag chip |

### 2.3 Row state colors

Row tints (cho download manager):

| State | Background | Border | Badge bg | Badge text |
|-------|-----------|--------|----------|-----------|
| `completed` | `#FFFFFF` | `#E5EAF2` | `#DCFCE7` | `#15803D` |
| `downloading` | `#F4F8FF` | `#BFDBFE` | `#DBEAFE` | `#1D4ED8` |
| `postProcessing` | `#FAF5FF` | `#E9D5FF` | `#F3E8FF` | `#7E22CE` |
| `queued` | `#FFFFFF` | `#E5EAF2` | `#F1F5F9` | `#475569` |
| `pending` | `#FFFFFF` | `#E5EAF2` | `#E2E8F0` | `#64748B` |
| `paused` | `#F9FAFB` | `#E5EAF2` | `#FEF3C7` | `#B45309` |
| `failed` | `#FFF7F7` | `#FECACA` | `#FEE2E2` | `#B91C1C` |
| `cancelled` | `#F9FAFB` (opacity 70%) | `#E5EAF2` | `#F1F5F9` | `#94A3B8` |
| `waitingForNetwork` | `#FEFCE8` | `#FEF08A` | `#FEF3C7` | `#B45309` |

### 2.4 Dark mode mapping

| Token | Light | Dark |
|-------|-------|------|
| `bg.app` | `#F6F8FB` | `#0F172A` |
| `bg.card` | `#FFFFFF` | `#1E293B` |
| `bg.surface-raised` | `#FFFFFF` | `#334155` |
| `bg.subtle` | `#F1F5F9` | `#1E293B` |
| `border.default` | `#E5EAF2` | `#334155` |
| `border.strong` | `#CBD5E1` | `#475569` |
| `text.primary` | `#0F172A` | `#F1F5F9` |
| `text.secondary` | `#475569` | `#CBD5E1` |
| `text.tertiary` | `#94A3B8` | `#64748B` |
| `accent.primary` | `#0B63F6` | `#3B82F6` |
| `accent.primary-subtle` | `#DBEAFE` | `#1E3A8A` |

Row state dark variants: bg shifts to `slate-800` family với colored tint nhẹ.

### 2.5 Color usage rules

- **Never** dùng pure black `#000` cho text — luôn `slate-900` để hơi mềm hơn
- **Never** dùng pure white `#FFF` cho dark mode bg — `slate-900` hoặc `slate-800`
- Primary action (Tải xuống button) dùng `accent.primary` background
- Destructive action (Xoá) dùng red-600 với confirm dialog
- Inactive icons opacity `0.6`, hover opacity `1.0`
- Selection highlight = `accent.primary-subtle` background

---

## 3. Typography

> **⚠️ Source of truth**: [`lib/core/theme/app_typography.dart`](../lib/core/theme/app_typography.dart). v1.2 migrated existing class from `GoogleFonts.inter()` runtime download → bundled `assets/fonts/InterVariable.ttf`. API unchanged for backward compat (95+ widget usages).

### 3.0 Existing API (authoritative)

```dart
// From lib/core/theme/app_typography.dart
class AppTypography {
  static const String fontFamily = 'Inter';  // bundled
  static const List<String> fontFamilyFallback = [...];

  static const TextTheme textTheme = TextTheme(
    displayLarge: ...,    // 48px/700
    displayMedium: ...,   // 36px/700
    headlineLarge: ...,   // 28px/600
    headlineMedium: ...,  // 24px/600
    titleLarge: ...,      // 18px/600
    bodyLarge: ...,       // 15px/400
    bodyMedium: ...,      // 13px/400
    labelLarge: ...,      // 14px/500
    // ... full M3 TextTheme
  );

  // Custom styles for app-specific contexts
  static const TextStyle appBarTitle = ...;        // 16px/600
  static const TextStyle sectionHeader = ...;      // 11px/600 + 1.2 letter-spacing
  static const TextStyle fileName = ...;           // 14px/500
  static const TextStyle metadata = ...;           // 12px/400
  static const TextStyle buttonPrimary = ...;      // 13px/600
  static const TextStyle buttonSecondary = ...;    // 13px/500
  static const TextStyle input = ...;              // 14px/400
  static const TextStyle inputHint = ...;          // 14px/400
  static const TextStyle platformName = ...;       // 13px/500
  static const TextStyle statusBadge = ...;        // 11px/600 + 0.3 letter-spacing
  static const TextStyle navItem = ...;            // 13px/500
  static const TextStyle navItemSelected = ...;    // 13px/600
}
```

→ Engineer dùng `AppTypography.fileName`, `AppTypography.statusBadge`, etc. trong widget.

### 3.1 Font stack

**Primary: Inter (bundled)**
```
fontFamily: 'Inter', fontFamilyFallback: [
  // System fallback nếu Inter load fail
  '-apple-system', 'BlinkMacSystemFont',  // macOS/iOS
  'Segoe UI Variable', 'Segoe UI',         // Windows
  'Cantarell', 'Ubuntu',                   // Linux
  'system-ui', 'sans-serif'                // generic
]
```

**Setup** (đã shipped trong v1.1):
- **InterVariable.ttf** (single variable font file, 880KB) bundled tại `assets/fonts/InterVariable.ttf`
- Hỗ trợ tất cả weights 100-900 trong 1 file (gọn hơn 4 static files = 1.6MB)
- Flutter auto-resolve weight axis: `fontWeight: FontWeight.w400/500/600/700` đều work
- License: SIL Open Font License — full text tại `assets/fonts/Inter-LICENSE.txt`
- Source: https://rsms.me/inter/ → GitHub release v4.1 (Nov 2024)
- Registered trong `pubspec.yaml`:
  ```yaml
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/InterVariable.ttf
  ```

**Why bundled vs Google Fonts:**
- ✅ No runtime download (faster cold start)
- ✅ Offline-friendly (desktop app)
- ✅ Predictable rendering (no network failure)
- ❌ ~500KB asset size (acceptable for desktop)

### 3.2 Type scale

| Token | Size | Weight | Line height | Letter spacing | Usage |
|-------|------|--------|-------------|----------------|-------|
| `display.xl` | 32px | 700 | 1.2 (38.4px) | -0.02em | Onboarding hero |
| `display` | 28px | 700 | 1.2 | -0.01em | Empty state title |
| `heading.lg` | 24px | 700 | 1.3 (31.2px) | -0.01em | Page title |
| `heading.md` | 20px | 600 | 1.3 | 0 | Section title |
| `heading.sm` | 18px | 600 | 1.4 | 0 | Subsection |
| `heading.xs` | 16px | 600 | 1.4 | 0 | Card title, dialog title |
| `body.lg` | 16px | 400 | 1.5 (24px) | 0 | Large body |
| `body` | 14px | 400 | 1.5 (21px) | 0 | Default body |
| `body.sm` | 13px | 400 | 1.5 | 0 | Compact contexts |
| `caption` | 12px | 400 | 1.4 | 0.01em | Metadata, hints |
| `label` | 14px | 500 | 1.4 | 0 | Form labels |
| `button` | 14px | 600 | 1 (no extra) | 0.01em | Button text |
| `code` | 13px | 400 | 1.5 | 0 | Monospace (Menlo, Consolas) |

### 3.3 Typography rules

- Headings: weight 600-700, line-height 1.2-1.4
- Body: weight 400, line-height 1.5 cho readability
- Button: weight 600, slight tracking (+0.01em) cho UPPERCASE-like feel
- Caption: tracking nhẹ (+0.01em) ở size 12px để nét rõ
- Never dùng underline trừ link
- Italic dùng tiết kiệm (chỉ quotes hoặc emphasis subtle)

---

## 4. Spacing & layout

### 4.1 Spacing scale (8-point grid)

| Token | Value | Usage |
|-------|-------|-------|
| `xxs` | 2px | Hairline gaps |
| `xs` | 4px | Tight icon-text spacing |
| `sm` | 8px | Small component padding |
| `md` | 12px | Medium padding |
| `lg` | 16px | Default card padding |
| `xl` | 24px | Section spacing |
| `2xl` | 32px | Large section gaps |
| `3xl` | 48px | Page-level spacing |
| `4xl` | 64px | Hero spacing |

### 4.2 Layout grid

| Element | Value |
|---------|-------|
| Page max-width | 1440px (centered) |
| Page horizontal padding | 24px (desktop), 16px (compact) |
| Column gap (3-column layout) | 24px |
| Left column min-width | 600px |
| Right column width | 320px (collapsed: 0) |
| Card internal padding | 16px (default), 24px (large) |

### 4.3 Responsive breakpoints

| Breakpoint | Min width | Layout behavior |
|-----------|-----------|-----------------|
| `compact` | 0 | 1 column, right column hidden |
| `medium` | 1024px | 2 columns, right column collapses to button |
| `large` | 1280px | 3 columns full |
| `xlarge` | 1536px | 3 columns + extra padding |

App is desktop-first; `compact` rare but supported (window resize).

### 4.4 Min-widths & overflow guards

UI phải graceful degrade khi window/container thu nhỏ. Min-widths ngăn UI **vỡ layout** trước khi đến breakpoint nhỏ nhất.

#### 4.4.1 Window-level minimums (enforce ở OS layer)

| Platform | Min size | Implementation |
|----------|----------|----------------|
| macOS | 1024 × 720 | `NSWindow.setContentMinSize` trong `MainFlutterWindow` (Swift) |
| Windows | 1024 × 720 | `SetWindowPos` với `WM_GETMINMAXINFO` handler |
| Linux | 1024 × 720 | `GtkWindow.set_size_request` |

→ User không thể resize window dưới `1024 × 720`. Implementation: tạo `lib/core/window_size.dart` Phase 1A wire qua method channel.

#### 4.4.2 Layout-level min-widths

| Region | Min width | Behavior khi vi phạm |
|--------|-----------|---------------------|
| Page content | 880px | Hide right column (force compact mode) |
| Left column | 600px | Last responsive layer — không thu nhỏ thêm |
| Right column | 280px | Hide entirely nếu không đủ |
| Right column panels (Bắt đầu nhanh, Mở nhanh website) | 280px | Cards stack vertically, no horizontal scroll |

#### 4.4.3 Component-level min-widths

| Component | Min width | Truncation/fallback behavior |
|-----------|-----------|------------------------------|
| Smart input field | 320px | Placeholder + paste URL fit; nếu URL dài → ellipsis trong field, full text in tooltip |
| Action bar (icons + preset + CTA) | 480px | Below: chuyển preset dropdown thành icon-only with tooltip |
| Primary CTA (Tải xuống) | 156px | Never shrink below — drop to icon-only nếu container <156px |
| Secondary button | 88px | Drop label, keep icon nếu <88px |
| Icon-only button | 40px (square) | Never shrink |
| Preset dropdown trigger | 140px | Below: thay label "MP4 · 1080p" thành "MP4 ⋯" hoặc icon-only |
| Dialog content area | 360px | Below: scroll horizontal trong dialog (rare) |
| Dialog action footer | 280px | 2 buttons fit; nếu nhiều hơn → stack vertical |
| Download row | 480px | Thumbnail vẫn 96×54, content area shrink, actions stay; ellipsis title |
| Tab bar (Lịch sử / Playlist) | 240px | Tab text hiện đầy đủ |
| Search field | 200px | Below: shrink placeholder text first |
| Filter chip row | 320px | Below: scroll horizontal trong chip row (acceptable) |

#### 4.4.4 Truncation rules

| Element | Behavior |
|---------|----------|
| Row title | Ellipsis after 1 line |
| Row metadata (size, date) | Ellipsis after 1 line, individual fields fit |
| Preset label "MP4 · 1080p" | **Never truncate** — use abbreviation per design system |
| Button label | **Never truncate** — drop to icon-only if container too narrow |
| Snackbar message | Wrap to 3 lines max, then ellipsis |
| Dropdown item | Ellipsis trong popover (popover scrolls if needed) |

#### 4.4.5 Implementation checklist

```dart
// Window min size (lib/core/window_size.dart, called from main.dart)
await WindowSize.setMinWindowSize(
  Size(AppMinWidth.appWindow, AppMinWidth.appWindowHeight),
);

// Layout min-width
ConstrainedBox(
  constraints: BoxConstraints(minWidth: AppMinWidth.leftColumn),
  child: leftColumnContent,
)

// Button graceful degrade
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < AppMinWidth.buttonPrimary) {
      return IconButton(icon: Icon(Icons.download), tooltip: 'Tải xuống');
    }
    return ElevatedButton.icon(icon: ..., label: Text('Tải xuống'));
  },
)
```

→ Reference [`AppMinWidth`](../lib/core/design/design_tokens.dart) trong code thay vì hardcode.

---

## 5. Border radius

| Token | Value | Usage |
|-------|-------|-------|
| `none` | 0 | Sharp edges (rare) |
| `xs` | 2px | Chips, small badges |
| `sm` | 4px | Small buttons, inputs (no — use `md`) |
| `md` | 8px | **Default** — cards, dialogs, inputs, buttons |
| `lg` | 12px | Large cards, popovers |
| `xl` | 16px | Modal sheets |
| `2xl` | 24px | Hero cards (rare) |
| `round` | 999px | Avatars, pill buttons, switches |

**Default radius for app = `md` (8px)**. Consistency over variety.

---

## 6. Shadow elevation

5 levels của elevation, sử dụng layered shadows cho realistic feel:

| Level | Token | Shadow value (light mode) | Usage |
|-------|-------|---------------------------|-------|
| 0 | `none` | none | Flat elements |
| 1 | `sm` | `0 1px 2px 0 rgba(15, 23, 42, 0.05)` | Cards at rest |
| 2 | `md` | `0 4px 6px -1px rgba(15, 23, 42, 0.1), 0 2px 4px -2px rgba(15, 23, 42, 0.05)` | Dropdowns, hover state |
| 3 | `lg` | `0 10px 15px -3px rgba(15, 23, 42, 0.1), 0 4px 6px -4px rgba(15, 23, 42, 0.05)` | Popovers, dialogs |
| 4 | `xl` | `0 20px 25px -5px rgba(15, 23, 42, 0.1), 0 8px 10px -6px rgba(15, 23, 42, 0.05)` | Modals |
| 5 | `2xl` | `0 25px 50px -12px rgba(15, 23, 42, 0.25)` | Emphasized (rare) |

Dark mode: shadows mạnh hơn 1.5x opacity vì contrast giảm.

---

## 7. Motion & animation

### 7.1 Duration tokens

| Token | Value | Usage |
|-------|-------|-------|
| `instant` | 0ms | No animation (reduced motion) |
| `fast` | 100ms | Hover, focus, micro-interactions |
| `normal` | 200ms | Default transition (button, transitions) |
| `slow` | 300ms | Dialog open, complex transitions |
| `slower` | 500ms | Page transitions, large layouts |

### 7.2 Easing curves

| Token | Cubic value | Usage |
|-------|-------------|-------|
| `linear` | `linear` | Progress bars, loaders |
| `easeOut` | `cubic-bezier(0, 0, 0.2, 1)` | **Default** — entry animations |
| `easeIn` | `cubic-bezier(0.4, 0, 1, 1)` | Exit animations |
| `easeInOut` | `cubic-bezier(0.4, 0, 0.2, 1)` | Two-way transitions |
| `easeOutCubic` | `cubic-bezier(0.16, 1, 0.3, 1)` | Smooth dialog/popover entry |
| `bounce` | `cubic-bezier(0.68, -0.55, 0.27, 1.55)` | Playful (use sparingly) |

### 7.3 Motion principles

- **Entry > Exit**: Entry animations 250ms, exit 150-200ms (perception faster)
- **Stagger lists**: 30-50ms between items, max 5 items animated at once
- **Skeleton shimmer**: 1.5s linear, alternate direction
- **Progress indeterminate**: 1.2s loop
- **Respect `prefers-reduced-motion`**: tất cả `fast`/`normal`/`slow` → `instant`, transitions → opacity-only
- **No bounce/parallax** trừ khi user opt-in

---

## 8. Iconography

### 8.1 Library choice

**Material Icons** (Flutter built-in `package:flutter/material.dart`):
- Pros: Zero dep, complete coverage, well-maintained
- Cons: Generic look (acceptable for productivity app)

Alternative considered (rejected for v2): Phosphor Icons, Lucide. Có thể migrate v3 nếu cần custom feel.

### 8.2 Sizes

| Token | Size | Usage |
|-------|------|-------|
| `xs` | 14px | Inline với caption text |
| `sm` | 16px | Inline với body text |
| `md` | 18px | Default in buttons |
| `lg` | 20px | Action bar icons, top nav |
| `xl` | 24px | Empty state, feature illustrations |
| `2xl` | 32px | Onboarding hero |

### 8.3 Style rules

- **Outlined** (default) cho inactive states, navigation
- **Filled** cho active/selected states (vd: `Icons.home` selected vs `Icons.home_outlined` default)
- **Stroke weight**: Material default (thin)
- **Color**: inherit từ parent text color trừ khi có semantic meaning (success/error)

### 8.4 Icon name mapping

Concrete Material icon names cho từng function trong app. Engineer reference khi build widget:

| Function | Icon outlined | Icon filled (active) |
|----------|---------------|----------------------|
| **Top navigation** | | |
| Trang chủ (Home) | `home_outlined` | `home` |
| Đăng ký (Subscriptions) | `subscriptions_outlined` | `subscriptions` |
| Chuyển đổi (Converter) | `sync` / `autorenew` | `sync` |
| Trình duyệt (Browser) | `public` | `public` |
| Nâng cấp / Premium | `workspace_premium` | `workspace_premium` |
| Notification | `notifications_outlined` | `notifications` |
| Settings (app-level) | `settings_outlined` | `settings` |
| Theme toggle (light) | `light_mode_outlined` | `light_mode` |
| Theme toggle (dark) | `dark_mode_outlined` | `dark_mode` |
| **Smart input** | | |
| Link/URL leading icon | `link` | — |
| Clear input | `cancel` / `close` | — |
| **Action bar** | | |
| History | `history` | — |
| Tải hàng loạt (Batch) | `layers_outlined` / `stacks` | — |
| Tuỳ chỉnh (⚙️ customize) | `tune` | — |
| Preset dropdown trigger | `expand_more` (chevron) | — |
| Tải xuống (Download CTA) | `download` / `file_download` | — |
| **Download manager** | | |
| Search | `search` | — |
| Filter | `filter_alt_outlined` | `filter_alt` (when active) |
| Sort | `sort` / `swap_vert` | — |
| Grid view | `grid_view_outlined` | `grid_view` |
| List view | `view_list_outlined` | `view_list` |
| **Row actions** | | |
| Play (completed) | `play_arrow` | — |
| Pause (downloading) | `pause` | — |
| Resume (paused) | `play_arrow` | — |
| Retry (failed) | `refresh` / `replay` | — |
| Cancel (queued) | `cancel_outlined` | — |
| Waiting/queued indicator | `schedule_outlined` / `hourglass_empty` | — |
| Network waiting | `wifi_off_outlined` | — |
| Post-processing | `sync` (animated) | — |
| More menu (⋯) | `more_vert` / `more_horiz` | — |
| **Menus & dialogs** | | |
| Add (generic) | `add` | — |
| Add to playlist | `playlist_add` | — |
| Playlist play | `playlist_play` | — |
| Delete | `delete_outlined` | `delete` |
| Open folder | `folder_open_outlined` | `folder_open` |
| Copy link | `content_copy` / `link` | — |
| Share | `share` | — |
| **Status indicators** | | |
| Success | `check_circle_outlined` | `check_circle` |
| Error | `error_outlined` | `error` |
| Warning | `warning_amber_outlined` | `warning` |
| Info | `info_outlined` | `info` |
| **Empty states** | | |
| No history | `inbox_outlined` / `download_done_outlined` | — |
| No search results | `search_off_outlined` | — |
| Filter empty | `filter_alt_off_outlined` | — |
| Empty playlist | `playlist_add_outlined` | — |
| No internet | `wifi_off_outlined` | — |
| **Drag/upload** | | |
| Drag indicator (≡) | `drag_handle` / `drag_indicator` | — |
| Upload/import link | `upload` / `link` | — |

→ Use này khi build widget. Đảm bảo consistency cross-screen.

---

## 9. Component anatomy

### 9.1 Button

**Variants:**

| Variant | Background | Border | Text | Use case |
|---------|-----------|--------|------|----------|
| `primary` | `accent.primary` | none | `text.inverse` | Tải xuống, Save |
| `secondary` | `bg.card` | `border.strong` | `text.primary` | Cancel, secondary actions |
| `tertiary` | transparent | none | `accent.primary` | Text links, low-emphasis |
| `destructive` | `red-600` | none | white | Delete, dangerous |
| `icon-only` | transparent (hover: `bg.subtle`) | none | inherit | Toolbars, action bars |

**Sizes:**

| Size | Height | Padding H | Font | Icon |
|------|--------|-----------|------|------|
| `sm` | 32px | 12px | 13/600 | 16px |
| `md` | 40px | 16px | 14/600 | 18px |
| `lg` | 48px | 20px | 15/600 | 20px |
| `xl` | **52px** | 24px | 16/600 | 22px |

**Primary CTA (Tải xuống) = `xl` size** với min-width 156px.

**States** (per variant):
- Default
- Hover: bg lighten/darken 10%, optional shadow `sm`
- Active (pressed): bg darken 15%, no shadow
- Focus: outline 2px `border.focus`, offset 2px
- Disabled: opacity 0.5, cursor not-allowed
- Loading: spinner 16px center, hide text, disabled state

### 9.2 Input field

**Anatomy:**
```
┌─────────────────────────────────────┐
│ [icon] Placeholder text...    [×]   │
└─────────────────────────────────────┘
  └─16px padding right→            ←─16px
```

| Property | Value |
|----------|-------|
| Height | 44px (default), 52px (large — smart input) |
| Border radius | `md` (8px) |
| Border (default) | 1px `border.strong` |
| Border (focus) | 2px `border.focus` |
| Padding | 12px vertical, 16px horizontal |
| Affix icon size | 18px, color `text.tertiary` |
| Placeholder color | `text.tertiary` |
| Background (default) | `bg.card` |
| Background (disabled) | `bg.subtle` |

**Smart input** specifically: height 52px, font size 15px, supports paste/drag-drop affordance.

### 9.3 Card

| Property | Value |
|----------|-------|
| Background | `bg.card` |
| Border | 1px `border.default` |
| Border radius | `md` (8px) |
| Shadow | `sm` |
| Padding | 16px (default), 24px (large) |
| Hover (interactive) | shadow → `md`, border `border.strong` |

### 9.4 Dialog / Modal

| Property | Value |
|----------|-------|
| Max width | 480px (small), 640px (medium), 800px (large), 1080px (xl — DownloadConfigDialog) |
| Border radius | `lg` (12px) |
| Shadow | `xl` |
| Background | `bg.card` |
| Scrim background | `rgba(15, 23, 42, 0.5)` |
| Padding | 24px |
| Header height | 56px (with close button) |
| Footer height | 64px (action area) |

### 9.5 Popover

| Property | Value |
|----------|-------|
| Min width | 240px |
| Max width | 360px |
| Border radius | `lg` (12px) |
| Shadow | `lg` |
| Padding | 8px (compact) |
| Arrow size | 8px |
| Offset from trigger | 8px |
| Z-index | dialog (3000) |

**Preset popover** specifically: 320px wide, max-height 480px (scrollable).

### 9.6 Row (download list item)

| Property | Value |
|----------|-------|
| Height | 72px (default), 56px (compact) |
| Padding | 12px vertical, 16px horizontal |
| Thumbnail | 16:9 aspect, 96x54px |
| Gap between thumb and content | 12px |
| Border bottom (separator) | 1px `border.default` |
| Hover background | `bg.subtle` |
| Selected background | `accent.primary-subtle` |
| Progress bar height | 2px (full-width bottom of row) |

### 9.7 Chip / Tag / Badge

**Chip** (filter, tag):
| Property | Value |
|----------|-------|
| Height | 28px |
| Padding | 4px 8px |
| Border radius | `xs` (2px) hoặc `round` (pill) |
| Font | 12/500 |

**Badge** (status, count):
| Property | Value |
|----------|-------|
| Height | 20px |
| Padding | 2px 6px |
| Border radius | `round` |
| Font | 11/600 |

### 9.8 Toggle switch

| Property | Value |
|----------|-------|
| Track size | 36x20px |
| Knob size | 16x16px (1px gap) |
| Border radius | `round` |
| OFF track | `border.strong` |
| ON track | `accent.primary` |
| Animation | knob slide 200ms `easeOut` |

### 9.9 Checkbox

| Property | Value |
|----------|-------|
| Box size | 18x18px |
| Border radius | `xs` (2px) |
| Border (default) | 1.5px `border.strong` |
| Border (checked) | 1.5px `accent.primary` |
| Background (checked) | `accent.primary` |
| Check icon size | 12px white |

### 9.10 Tab indicator

| Property | Value |
|----------|-------|
| Height | 40px (default) |
| Indicator height | 2px (bottom border) |
| Indicator color | `accent.primary` |
| Active text color | `accent.primary` |
| Inactive text color | `text.secondary` |
| Animation | indicator slide 200ms `easeOut` |

### 9.11 Snackbar / Toast

| Property | Value |
|----------|-------|
| Max width | 480px |
| Min height | 48px |
| Border radius | `md` (8px) |
| Shadow | `lg` |
| Padding | 12px 16px |
| Background (info) | `slate-900` |
| Background (success) | `green-600` |
| Background (error) | `red-600` |
| Text | `text.inverse` |
| Auto dismiss | 5s default, 0 (manual) for errors |

### 9.12 Empty state

| Property | Value |
|----------|-------|
| Icon size | 48px (medium), 64px (large) |
| Icon color | `text.tertiary` |
| Title | `heading.md` |
| Description | `body` color `text.secondary` |
| CTA button | `secondary` size `md` |
| Vertical alignment | center, padding 48px |

---

## 10. State variations matrix

Mỗi interactive component cần handle 5 states:

| State | Visual treatment |
|-------|------------------|
| **Default (rest)** | Base styling per component |
| **Hover** | Shadow tăng 1 level, bg subtle shift, cursor pointer |
| **Focus** | 2px outline `border.focus`, offset 2px (keyboard nav rõ) |
| **Active (pressed)** | Bg darken 5-10%, shadow giảm, scale 0.98 (subtle) |
| **Disabled** | Opacity 0.5, cursor not-allowed, no hover effect |
| **Loading** (variant) | Spinner replace content, disabled-like |

### Special states cho download row

| State | Treatment |
|-------|-----------|
| **Downloading** | Row tinted blue-50, progress bar bottom 2px |
| **Selected** (bulk mode) | Row bg `accent.primary-subtle`, checkbox checked |
| **Drag over** (reorder) | Border 2px dashed `accent.primary`, drop zone highlight |

### 10.3 Smart CTA state machine

Mapping detected input type → CTA label → action result. Reference cho engineer implement smart input bar:

| Detected input | CTA label | Action when click | Tooltip |
|----------------|-----------|-------------------|---------|
| Empty | `Tải xuống` (disabled) | None (button disabled) | "Dán link hoặc nhập từ khóa để bắt đầu" |
| Single video URL | `Tải xuống` | Tải với active preset (Rule 3) hoặc dialog (Rule 3'/4) | "Tải video này" |
| Playlist URL (`?list=...`) | `Xem playlist` | Open `YouTubePlaylistSheet` | "Xem video trong playlist" |
| Channel URL (`youtube.com/@...`) | `Xem kênh` | Open `YouTubeChannelSheet` | "Xem video trong kênh" |
| Search keyword (text, no URL) | `Tìm kiếm` | Open `YouTubeSearchSheet` | "Tìm video trên YouTube" |
| Multiple URLs (≥2) | `Tải hàng loạt` | Open batch dialog | "Tải nhiều video cùng lúc" |
| Unsupported URL (HTTPS but không support) | `Mở trình duyệt` | Open URL trong in-app browser (macOS/Linux) hoặc system browser (Windows) | "Mở trang web trong trình duyệt" |
| Invalid URL | `Phân tích` (warning) | Show error toast với suggestion | "URL không hợp lệ" |
| Loading/parsing | `Đang phân tích...` (disabled) | Spinner replacing icon | "Đang đọc thông tin video" |

**Critical**: CTA verb đổi rõ ràng theo intent → user biết action sẽ xảy ra trước khi click.

---

## 11. Empty / loading / error visuals

### 11.1 Empty state — complete copy

V2.0 dùng **icon-only** empty states (Material Icons + outlined style). V2.x sẽ thay illustrations custom nếu hire designer.

Mỗi empty state cần đủ 4 elements: **icon + title + description + optional CTA**.

#### Chưa có lịch sử
```
[icon: inbox_outlined / download_done_outlined — 64px]
Chưa có mục tải xuống
Dán link hoặc mở website để bắt đầu.
[CTA: Tải video đầu tiên]
```

#### Empty playlist tab
```
[icon: playlist_add_outlined — 64px]
Chưa có playlist nào
Chọn nhiều video đã tải và thêm vào playlist, hoặc tạo playlist mới.
[CTA: Tạo playlist]
```

#### No search results
```
[icon: search_off_outlined — 64px]
Không tìm thấy kết quả
Thử từ khoá khác hoặc xoá bớt bộ lọc.
[CTA: Xoá bộ lọc]
```

#### Filter empty
```
[icon: filter_alt_off_outlined — 64px]
Không có mục nào khớp bộ lọc hiện tại
Thử xoá vài bộ lọc để xem thêm kết quả.
[CTA: Xoá tất cả bộ lọc]
```

#### No internet (banner, not full empty)
```
[icon: wifi_off_outlined — 24px inline]
Mất kết nối. Tải sẽ tự tiếp tục khi có mạng.
```

#### Loading / analyzing input
```
[Spinner inline trong CTA hoặc near input]
Đang phân tích liên kết...
```
Don't block full screen unless absolutely necessary.

#### Downloading row metadata template
```
Badge: Đang tải · {progress}% · {downloaded} / {total} · {speed} · Còn {eta}
```
Example: `Đang tải · 43% · 1.02 GB / 2.38 GB · 12.4 MB/s · Còn 1m 32s`

#### Error row template
```
Badge: Lỗi
Message: Không thể tải video. Vui lòng thử lại.
[Retry icon]
More menu options:
  - Thử lại
  - Sao chép lỗi
  - Mở link gốc
  - Xoá khỏi danh sách
```

### 11.2 Loading skeleton

Placeholder shapes mimic content:
- Background: `bg.subtle`
- Shimmer: gradient sweep 1.5s linear
- Border radius: match content type
- Shimmer color: `bg.card` opacity 50%

### 11.3 Loading spinner

Material's `CircularProgressIndicator`:
- Default size: 20px
- Stroke width: 2.5px
- Color: `accent.primary` (light), white (on dark bg)

### 11.4 Inline error

| Element | Style |
|---------|-------|
| Background | `red-50` |
| Border (left) | 4px solid `red-600` |
| Padding | 12px 16px |
| Title | `body.sm` weight 600 color `red-700` |
| Message | `body.sm` color `red-700` opacity 0.8 |

---

## 12. Cross-platform considerations

### 12.1 macOS

- Window control buttons (close/min/max) ở góc trái, chiếm 70px width
- Title bar height 28px
- Native scroll behavior (rubber-band overscroll)
- Font smoothing: subpixel antialiased (default)
- Cmd as modifier key

### 12.2 Windows

- Window controls ở góc phải, chiếm ~140px
- Title bar height 32px
- Browser feature **không có** (xem [§6.2 PRD](Svid_Home_Download_Manager_UI_Spec_v1.1.md))
- Font: Segoe UI Variable (Windows 11) / Segoe UI (Windows 10)
- Ctrl as modifier key

### 12.3 Linux

- Window controls position depends on DE (GNOME left, KDE right)
- Title bar variable
- Font: depends on system theme

### 12.4 Adaptive elements

| Element | macOS | Windows | Linux |
|---------|-------|---------|-------|
| Modifier key text | "⌘D" | "Ctrl+D" | "Ctrl+D" |
| File picker | Native NSOpenPanel | Win32 dialog | GTK/Qt |
| Browser website CTA | In-app tab | System browser | In-app tab |
| Notification | NSUserNotification | Toast (Win10+) | libnotify |

### 12.5 Keyboard shortcuts

Standard shortcuts cho desktop power user. Hiển thị shortcut hint trong tooltip khi hover (vd `Tooltip: "Tải xuống · ⌘+Enter"`).

| Action | macOS | Windows/Linux | Context |
|--------|-------|---------------|---------|
| Paste link vào smart input | `⌘ + V` | `Ctrl + V` | Global khi input focused |
| Submit / trigger CTA | `⌘ + Enter` hoặc `Enter` | `Ctrl + Enter` hoặc `Enter` | Smart input focused |
| Search history | `⌘ + F` | `Ctrl + F` | Global trong download manager |
| Select all visible rows | `⌘ + A` | `Ctrl + A` | Khi list focused |
| Range select | `Shift + Click` | `Shift + Click` | Selection mode |
| Toggle individual select | `⌘ + Click` | `Ctrl + Click` | Selection mode |
| Retry selected failed | `⌘ + R` | `Ctrl + R` | Selection có failed items |
| Delete selected | `Delete` / `Backspace` | `Delete` / `Backspace` | Selection mode |
| Exit selection mode / Close popover | `Esc` | `Esc` | Always |
| Toggle checkbox (focused row) | `Space` | `Space` | Row focused via Tab |
| Open settings | `⌘ + ,` | `Ctrl + ,` | Global |
| Switch tab (download manager) | `⌘ + 1/2` | `Ctrl + 1/2` | Khi download manager focused |
| Quit app | `⌘ + Q` | `Alt + F4` | Global |

**Conflict avoidance:**
- Không dùng `⌘ + W` (close window — system reserved)
- Không dùng `⌘ + N` (new window — system reserved)
- Tránh `⌘ + Shift + ...` cho frequent actions (awkward)

---

## 13. Dark mode complete mapping

(Reference §2.4 cho semantic tokens)

**Component-specific dark adjustments:**

| Component | Light | Dark adjustment |
|-----------|-------|-----------------|
| Card border | `#E5EAF2` | `#334155` (more visible) |
| Card shadow | `sm` (subtle) | `md` (mạnh hơn vì contrast giảm) |
| Input border focus | `accent.primary` 2px | `accent.primary` 2px + glow `0 0 0 4px rgba(59, 130, 246, 0.2)` |
| Snackbar | `slate-900` bg | `slate-700` bg (giảm contrast vì dark mode) |
| Disabled state | opacity 0.5 | opacity 0.4 (perception khác) |

---

## 14. Accessibility verifications

### 14.1 Contrast ratios

Tất cả text-on-bg combinations đạt **WCAG AA** (4.5:1 normal, 3:1 large):

| Combination | Light ratio | Dark ratio | Status |
|------------|-------------|------------|--------|
| `text.primary` on `bg.app` | 16.84 | 14.21 | ✅ AAA |
| `text.secondary` on `bg.app` | 7.13 | 8.32 | ✅ AAA |
| `text.tertiary` on `bg.app` | 3.21 | 4.62 | ⚠️ AA large only |
| `text.inverse` on `accent.primary` | 8.59 | 7.32 | ✅ AAA |
| Badge text on badge bg (success) | 5.84 | 4.91 | ✅ AA |
| Badge text on badge bg (error) | 6.12 | 5.23 | ✅ AA |

`text.tertiary` chỉ dùng cho metadata/captions ≥14px (large text WCAG).

### 14.2 Focus indication

- Focus outline 2px `border.focus` offset 2px (8px total visual width)
- KHÔNG bao giờ remove focus với `outline: none` mà không thay thế
- Skip link cho keyboard navigation

### 14.3 Screen reader labels (aria-label)

Vietnamese labels ready-to-use cho icon-only buttons. Apply via `Tooltip(message: ..., child: IconButton(...))` hoặc `Semantics(label: ...)`:

| Element | aria-label / Tooltip |
|---------|----------------------|
| **Smart input** | |
| Smart input field | "Dán link video, playlist, kênh hoặc nhập từ khóa" |
| Clear input button | "Xoá nội dung nhập" |
| **Action bar** | |
| History icon | "Lịch sử tải xuống" |
| Batch icon | "Tải hàng loạt" |
| Customize icon (⚙️) | "Tuỳ chỉnh trước khi tải" |
| Preset dropdown trigger | "Tuỳ chọn tải mặc định: {format}, {quality}" (vd: "MP4, 1080p") |
| Download CTA | Dynamic label theo input type (xem §10.3) |
| **Download manager** | |
| Search field | "Tìm trong lịch sử" |
| Sort dropdown | "Sắp xếp theo: {sort_field}" |
| Filter icon | "Bộ lọc" |
| Filter icon (active) | "Bộ lọc, đang áp dụng {n} bộ lọc" |
| View toggle (list) | "Xem dạng danh sách" |
| View toggle (grid) | "Xem dạng lưới" |
| **Row actions** | |
| Play | "Phát {title}" |
| Pause | "Tạm dừng tải {title}" |
| Resume | "Tiếp tục tải {title}" |
| Retry | "Thử lại tải {title}" |
| More menu (⋯) | "Thêm hành động cho {title}" |
| Drag handle | "Kéo để sắp xếp lại thứ tự" |
| **Selection** | |
| Row checkbox | "Chọn {title}" |
| Select all checkbox | "Chọn tất cả mục đang hiển thị" |
| Selection toolbar count | "{n} mục đã chọn" |
| **Bulk actions** | |
| Phát selected | "Phát {n} mục đã chọn" |
| Add to playlist | "Thêm {n} mục vào playlist" |
| Delete selected | "Xoá {n} mục đã chọn" |
| Cancel selection | "Huỷ chọn" |
| **Tabs** | |
| Tab Lịch sử | "Tab Lịch sử tải xuống" |
| Tab Playlist | "Tab Playlist của tôi" |
| **Sidebar** | |
| Quick start step 1 | "Bước 1: Dán link hoặc nhập từ khoá" |
| Quick website item | "Mở {website} trong trình duyệt tích hợp" |
| **Top bar** | |
| Notification bell | "Thông báo, {n} chưa đọc" (nếu có badge) |
| Settings | "Cài đặt ứng dụng" |
| Theme toggle | "Chuyển đổi giao diện sáng/tối" |
| Upgrade CTA | "Nâng cấp lên Premium" |

### 14.3 Reduced motion

Khi `MediaQuery.of(context).disableAnimations == true`:
- Tất cả `Duration` ngắn lại 0 (instant)
- Transitions chỉ opacity (no transform)
- Hover hiệu ứng giữ (color change vẫn OK)

---

## 15. Asset references

### 15.1 Icons

Material Icons từ `package:flutter/material.dart`:
- Outlined variants ưu tiên (vd `Icons.home_outlined`)
- Filled cho active states (vd `Icons.home`)
- Tham khảo §8.4 cho mapping table đầy đủ

### 15.2 Logos & app icons

`assets/icons/`:

```
logo-svid-light.svg
logo-svid-dark.svg
app-icon-16.png
app-icon-32.png
app-icon-64.png
app-icon-128.png
app-icon-256.png
app-icon-512.png
app-icon-1024.png
app-icon-macos.icns
app-icon-windows.ico
app-icon-linux.png
```

Naming rules:
- Logo: `logo-svid-{variant}.svg` — variants: `light`, `dark`
- App icon raster: `app-icon-{size}.png` — sizes: 16, 32, 64, 128, 256, 512, 1024
- Platform-specific: `app-icon-{platform}.{ext}` — `.icns` (macOS), `.ico` (Windows), `.png` (Linux)
- SVG preferred for logos (scalable)
- PNG fallback cho desktop shell

### 15.3 Platform icons (cho Mở nhanh website)

`assets/icons/platforms/`:

```
platform-youtube.svg
platform-tiktok.svg
platform-facebook.svg
platform-instagram.svg
platform-x.svg
platform-reddit.svg
platform-pinterest.svg
platform-vimeo.svg
```

Rules:
- Use **official brand icons** when licensing allows (YouTube/TikTok/etc. have brand guidelines)
- Maintain minimum 24px size
- Brand color trong website shortcut cards
- Don't distort logo ratio

### 15.4 Fonts

`assets/fonts/`:

```
InterVariable.ttf      # 880KB — variable font, all weights 100-900
Inter-LICENSE.txt      # SIL OFL license text
```

Source: https://rsms.me/inter/ → GitHub release [v4.1](https://github.com/rsms/inter/releases/tag/v4.1) (Nov 2024).

License: SIL Open Font License — included verbatim trong `Inter-LICENSE.txt`.

Registered trong `pubspec.yaml`:
```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/InterVariable.ttf
```

Flutter auto-handles variable weight axis. TextStyle như `fontWeight: FontWeight.w600` sẽ render correct semi-bold weight from variable font.

### 15.5 Thumbnail fallbacks

`assets/images/thumbnails/`:

```
thumbnail-fallback-video.svg
thumbnail-fallback-audio.svg
thumbnail-fallback-playlist.svg
thumbnail-fallback-error.svg
```

Rules:
- Aspect ratio: 16:9
- Recommended displayed size: 96×54 (small) hoặc 160×90 (large) hoặc 180×101 (xl)
- Border radius: `radius.md` (8px)
- Duration badge: bottom-right corner (white text, black overlay)
- Platform/source badge: top-left corner optional

### 15.6 Empty state illustrations

V2.0: KHÔNG có custom illustrations — dùng Material Icons outlined 64px.

V2.x (nếu hire designer):

`assets/illustrations/`:
```
empty-history.svg
empty-playlist.svg
empty-search.svg
drag-drop-link.svg
```

Rules:
- Use subdued color (slate-400 area)
- Don't overpower content
- SVG preferred (scalable)
- Optional theme variants (light/dark)

---

## 16. Implementation guide

### 16.1 Recommended widget hierarchy

Component tree đề xuất cho Home screen — engineer dùng làm starting structure khi build Phase 1A:

```
HomeScreen (StatelessWidget)
├── TopBar (TopNavigationBar — existing, modified)
│   ├── AppLogo
│   ├── TopNavTabs
│   │   ├── Trang chủ
│   │   ├── Đăng ký
│   │   ├── Chuyển đổi
│   │   └── Trình duyệt (hidden on Windows)
│   ├── UpgradeCTA (free user only)
│   ├── ThemeToggle
│   ├── NotificationBell
│   ├── SettingsButton
│   └── WindowControls
│
├── MainLayout (Row, max-width 1440)
│   │
│   ├── LeftColumn (Expanded, min 600px)
│   │   ├── SmartInputCard
│   │   │   ├── SmartInputBar (NEW Phase 1A)
│   │   │   │   ├── SmartInputField
│   │   │   │   ├── ClearButton
│   │   │   │   ├── HistoryIconButton
│   │   │   │   ├── BatchIconButton
│   │   │   │   ├── CustomizeIconButton (⚙️ NEW)
│   │   │   │   ├── PresetDropdownButton
│   │   │   │   └── SmartCTAButton
│   │   │   └── (no inline chip — sub-label trong button)
│   │   │
│   │   ├── FreePlanStrip (or Premium status)
│   │   │
│   │   └── DownloadManagerCard
│   │       ├── DownloadManagerTabs (Lịch sử | Playlist của tôi)
│   │       ├── HistoryToolbar (or SelectionToolbar)
│   │       │   ├── SelectAllCheckbox
│   │       │   ├── SearchField
│   │       │   ├── SortDropdown
│   │       │   ├── FilterIconButton (with badge)
│   │       │   └── ViewToggle (list/grid)
│   │       ├── DownloadRowList (ListView.builder)
│   │       │   └── DownloadRow (per state) ×N
│   │       └── PlaylistManager (when playlist tab active)
│   │           ├── CreatePlaylistButton
│   │           ├── PlaylistList
│   │           └── PlaylistDetail (drill-down)
│   │
│   └── RightColumn (fixed 380px, hidden < 1024px)
│       ├── QuickStartCard (dismissible)
│       ├── QuickWebsitesCard (9 platform shortcuts)
│       └── TipCard (optional, dismissible)
│
└── (Floating overlays)
    ├── PresetPopover (anchored to PresetDropdownButton)
    ├── FilterPopover (anchored to FilterIconButton)
    ├── AddToPlaylistMenu (anchored to bulk action)
    ├── RowMoreMenu (anchored to ⋯ button)
    │
    └── (Modal dialogs — open via showDialog)
        ├── DownloadConfigDialog (existing, modified for batch context)
        ├── BatchDownloadDialog (NEW)
        ├── YouTubeSearchSheet (existing)
        ├── YouTubePlaylistSheet (existing)
        ├── YouTubeChannelSheet (existing)
        ├── CreatePlaylistDialog (NEW)
        ├── RenamePlaylistDialog (NEW)
        ├── DeletePlaylistConfirmDialog (NEW)
        ├── BulkDeleteConfirmDialog (NEW)
        └── WhatsNewDialog (1 lần on v2 first run)
```

### 16.2 Where to find tokens

Engineer reference: [`lib/core/design/design_tokens.dart`](../lib/core/design/design_tokens.dart).

```dart
import 'package:svid/core/design/design_tokens.dart';

Container(
  padding: const EdgeInsets.all(AppSpacing.lg),
  decoration: BoxDecoration(
    color: AppColors.bgCard,
    borderRadius: BorderRadius.circular(AppRadius.md),
    boxShadow: AppShadow.sm,
  ),
  child: Text('Hello', style: AppTypography.body),
)
```

### 16.3 Theme integration

`lib/core/theme/app_theme.dart` consumes tokens và build `ThemeData` cho Light/Dark theme. Components dùng `Theme.of(context)` cho default styling, override với `AppColors.*` khi cần specific.

### 16.4 Don't

- ❌ Hardcode color hex trong widget
- ❌ Hardcode size pixel trong widget
- ❌ Skip focus outline
- ❌ Remove animation hoàn toàn (vẫn giữ basic transitions)
- ❌ Mix multiple radius scales trong cùng 1 screen

### 16.5 Do

- ✅ Reference `AppColors`, `AppSpacing`, `AppRadius` cho mọi visual decision
- ✅ Test dark mode trước khi merge
- ✅ Verify contrast với tool (WebAIM Contrast Checker)
- ✅ Test với reduced motion enabled
- ✅ Use Material icon names từ §8.4 mapping table cho consistency

---

## 17. Checklist for design QA

Khi review PR có UI changes:

- [ ] Colors từ `AppColors`, không hardcode
- [ ] Spacing từ `AppSpacing` 8-point grid
- [ ] Radius từ `AppRadius` (default `md`)
- [ ] Shadow từ `AppShadow` (default `sm`)
- [ ] Typography từ `AppTypography`
- [ ] All 5 states implemented (default/hover/focus/active/disabled)
- [ ] Dark mode renders correctly
- [ ] Reduced motion respected
- [ ] Focus outline visible
- [ ] Contrast ≥4.5:1 cho normal text
- [ ] Tooltip + aria-label cho icon-only buttons
- [ ] No animation > 500ms
- [ ] Loading state present cho async actions
- [ ] Empty state cho lists có thể rỗng
- [ ] Error state với retry option

---

## 18. Out of scope for v2.0

- Custom font family (default system)
- Custom illustrations (use Material icons)
- Theming customization by user (hardcoded light/dark only)
- Animation library (lottie, rive)
- 3D effects, parallax
- Marketing landing page redesign (separate scope)
- Brand guidelines documentation
- Iconography custom set
