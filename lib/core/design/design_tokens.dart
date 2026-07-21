/// Design System v2 — Layout & Motion Tokens
///
/// Source-of-truth for spacing, radius, shadow, motion, icon sizing,
/// component sizing, breakpoints, and minimum widths used across V2 UI.
///
/// Color tokens live in [`AppColors`](../theme/app_colors.dart) and typography
/// tokens in [`AppTypography`](../theme/app_typography.dart) — those classes
/// are authoritative and brand-aware via [BrandConfig]. This file adds only
/// the visual tokens the existing theme system did not yet expose.
///
/// Reference: docs/Svid_v2_Design_Spec.md §4-§8.
library;

import 'package:flutter/widgets.dart';

// ============================================================
// Spacing — 8-point grid (Spec §4.1)
// ============================================================

/// Spacing scale built on an 8-point grid with two intermediate stops
/// (`lgPlus` 20 and `xxlPlus` 40) for layouts where the canonical 16/24
/// step is too coarse.
class AppSpacing {
  AppSpacing._();

  /// Hairline gaps between very tight elements.
  static const double xxs = 2;

  /// Tight icon-text spacing.
  static const double xs = 4;

  /// Small component padding.
  static const double sm = 8;

  /// Medium padding (compact rows, small cards).
  static const double md = 12;

  /// Default card padding.
  static const double lg = 16;

  /// Mid-step between [lg] (16) and [xl] (24); useful for dialogs that
  /// want more air than 16 but less than a full 24.
  static const double lgPlus = 20;

  /// Section spacing.
  static const double xl = 24;

  /// Large section gap.
  static const double xxl = 32;

  /// Mid-step between [xxl] (32) and [xxxl] (48).
  static const double xxlPlus = 40;

  /// Page-level spacing.
  static const double xxxl = 48;

  /// Hero-spacing.
  static const double xxxxl = 64;
}

// ============================================================
// Border radius (Spec §5)
// ============================================================

/// Border-radius scale. Default radius for V2 generic components is [md]
/// (8px). Brand-defining components (cards, buttons, inputs) honor
/// [BrandConfig.cardRadius]/[BrandConfig.buttonRadius] etc. instead so Svid
/// (3px Nocturne angular) and VidCombo (12-999px Arctic frosted) keep their
/// brand identity. See `docs/v2/DECISIONS.md` Q5.
class AppRadius {
  AppRadius._();

  static const double none = 0;
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
  static const double round = 999;

  /// Default radius for new generic components added in V2.
  static const double defaultValue = md;
}

// ============================================================
// Shadow elevation (Spec §6)
// ============================================================

/// Five elevation levels using layered Material 3-style shadows. Dark mode
/// values are intentionally darker (1.5× opacity) because reduced canvas
/// contrast makes elevation cues harder to perceive.
class AppShadow {
  AppShadow._();

  static const List<BoxShadow> none = <BoxShadow>[];

  /// Cards at rest.
  static const List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      color: Color(0x0D0F172A), // 0.05 alpha
    ),
  ];

  /// Dropdowns, hover state.
  static const List<BoxShadow> md = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -1,
      color: Color(0x1A0F172A), // 0.10
    ),
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
      color: Color(0x0D0F172A), // 0.05
    ),
  ];

  /// Popovers, dialogs.
  static const List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 15,
      spreadRadius: -3,
      color: Color(0x1A0F172A), // 0.10
    ),
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -4,
      color: Color(0x0D0F172A), // 0.05
    ),
  ];

  /// Modals.
  static const List<BoxShadow> xl = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 20),
      blurRadius: 25,
      spreadRadius: -5,
      color: Color(0x1A0F172A), // 0.10
    ),
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 10,
      spreadRadius: -6,
      color: Color(0x0D0F172A), // 0.05
    ),
  ];

  /// Emphasized; rare.
  static const List<BoxShadow> xxl = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 25),
      blurRadius: 50,
      spreadRadius: -12,
      color: Color(0x400F172A), // 0.25
    ),
  ];

  /// Dark mode equivalents — opacity bumped 1.5× per Spec §6.
  static const List<BoxShadow> smDark = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      color: Color(0x14000000), // 0.075
    ),
  ];

  static const List<BoxShadow> mdDark = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -1,
      color: Color(0x26000000), // 0.15
    ),
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
      color: Color(0x14000000), // 0.075
    ),
  ];

  static const List<BoxShadow> lgDark = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 10),
      blurRadius: 15,
      spreadRadius: -3,
      color: Color(0x26000000), // 0.15
    ),
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -4,
      color: Color(0x14000000), // 0.075
    ),
  ];
}

// ============================================================
// Motion & animation (Spec §7)
// ============================================================

/// Duration tokens for app-wide animations.
class AppMotion {
  AppMotion._();

  /// No animation — used when [MediaQuery.disableAnimationsOf] is true.
  static const Duration instant = Duration.zero;

  /// Hover, focus, micro-interactions.
  static const Duration fast = Duration(milliseconds: 100);

  /// Default transition (button, generic transitions).
  static const Duration normal = Duration(milliseconds: 200);

  /// Dialog open, complex transitions.
  static const Duration slow = Duration(milliseconds: 300);

  /// Page transitions, large layouts.
  static const Duration slower = Duration(milliseconds: 500);

  /// Stagger between list items (cap at 5 items animated simultaneously).
  static const Duration listStagger = Duration(milliseconds: 40);

  /// Skeleton shimmer cycle.
  static const Duration skeletonShimmer = Duration(milliseconds: 1500);

  /// Indeterminate progress loop.
  static const Duration indeterminateProgress = Duration(milliseconds: 1200);

  /// Returns [instant] when reduced motion is preferred, else [normal].
  static Duration responsiveTo(BuildContext context, {Duration? base}) {
    final prefersReduced = MediaQuery.disableAnimationsOf(context);
    return prefersReduced ? instant : (base ?? normal);
  }
}

/// Easing curves matching Spec §7.2.
class AppEasing {
  AppEasing._();

  static const Curve linear = Curves.linear;

  /// Default for entry animations.
  static const Curve easeOut = Cubic(0, 0, 0.2, 1);

  /// Exit animations.
  static const Curve easeIn = Cubic(0.4, 0, 1, 1);

  /// Two-way transitions.
  static const Curve easeInOut = Cubic(0.4, 0, 0.2, 1);

  /// Smooth dialog/popover entry.
  static const Curve easeOutCubic = Cubic(0.16, 1, 0.3, 1);

  /// Playful — use sparingly.
  static const Curve bounce = Cubic(0.68, -0.55, 0.27, 1.55);
}

// ============================================================
// Iconography (Spec §8.2)
// ============================================================

/// Icon size scale used across V2.
class AppIconSize {
  AppIconSize._();

  /// Inline with caption text.
  static const double xs = 14;

  /// Inline with body text.
  static const double sm = 16;

  /// Default icon in buttons.
  static const double md = 18;

  /// Action bar icons, top nav.
  static const double lg = 20;

  /// Empty state, feature illustrations.
  static const double xl = 24;

  /// Onboarding hero.
  static const double xxl = 32;
}

// ============================================================
// Component dimensions (Spec §12.2)
// ============================================================

/// Concrete component measurements derived from §12.2 + §4.4. These are
/// stable across brands; brand-specific adjustments live on [BrandConfig].
class AppComponentSize {
  AppComponentSize._();

  /// Primary CTA button height (e.g., "Tải xuống").
  static const double primaryButtonHeight = 48;

  /// Slightly taller variant for hero CTAs.
  static const double primaryButtonHeightLarge = 52;

  /// Icon-only button (History, Batch, Customize ⚙️).
  static const double iconButtonSize = 40;

  /// Icon glyph size inside [iconButtonSize].
  static const double iconButtonGlyph = 20;

  /// Preset dropdown height (matches text input controls).
  static const double presetDropdownHeight = 44;

  /// Row action button (icon-only inside list rows).
  static const double rowActionSize = 36;

  /// Row download thumbnail width.
  static const double rowThumbnailWidth = 120;

  /// Row download thumbnail height (16:9 ratio with [rowThumbnailWidth]).
  static const double rowThumbnailHeight = 68;

  /// Top bar height (Spec v1.1 — 72px explicit).
  static const double topBarHeight = 72;

  /// Right column width when expanded (Spec §4.2).
  static const double rightColumnWidth = 320;

  /// Right column expanded width — alternate for content-heavier layouts
  /// (e.g., onboarding hero + 3×3 grid).
  static const double rightColumnWidthExpanded = 380;
}

// ============================================================
// Breakpoints (Spec §4.3)
// ============================================================

/// Responsive breakpoints. Desktop-first; the `compact` mode is rare but
/// supported for window-resize scenarios.
class AppBreakpoint {
  AppBreakpoint._();

  static const double compact = 0;
  static const double medium = 1024;
  static const double large = 1280;
  static const double xlarge = 1536;

  /// Returns true when current width is below [medium] — single column.
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < medium;

  /// Returns true when current width is in `[medium, large)` — 2 columns,
  /// right column collapses to a button toggle.
  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= medium && w < large;
  }

  /// Returns true at or above [large] — full 3 columns layout.
  static bool isLarge(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= large;

  /// Returns true at or above [xlarge] — full layout with extra padding.
  static bool isXLarge(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= xlarge;
}

// ============================================================
// Min-widths & overflow guards (Spec §4.4)
// ============================================================

/// Minimum widths enforced across three levels: window (OS), layout
/// regions, and individual components. Components below these thresholds
/// must apply the truncation/fallback rules from Spec §4.4.4.
class AppMinWidth {
  AppMinWidth._();

  // ── Window-level (Spec §4.4.1) ──
  // Wired to NSWindow.setContentMinSize / Win32 WM_GETMINMAXINFO /
  // GtkWindow.set_size_request via lib/core/window_size.dart.

  /// Minimum window width across all desktop platforms.
  static const double appWindow = 1024;

  /// Minimum window height.
  static const double appWindowHeight = 720;

  // ── Layout-level (Spec §4.4.2) ──

  /// Below this, the right column is hidden entirely (force compact mode).
  static const double pageContent = 880;

  /// Last responsive layer for the left column — never shrink further.
  static const double leftColumn = 600;

  /// Hide right column entirely below this width.
  static const double rightColumn = 280;

  /// Right column panel cards (Bắt đầu nhanh, Mở nhanh website).
  static const double rightColumnPanel = 280;

  // ── Component-level (Spec §4.4.3) ──

  /// Smart input field below this → ellipsis + tooltip.
  static const double smartInputField = 320;

  /// Action bar (icons + preset + CTA): below this → preset dropdown
  /// becomes icon-only with tooltip.
  static const double actionBar = 480;

  /// Primary CTA: below this → drop to icon-only.
  static const double primaryCta = 156;

  /// Secondary button: below this → drop label, keep icon.
  static const double secondaryButton = 88;

  /// Icon-only button never shrinks below this.
  static const double iconOnlyButton = 40;

  /// Preset dropdown trigger: below this → "MP4 ⋯" or icon-only.
  static const double presetDropdownTrigger = 140;

  /// Dialog content area: below this → horizontal scroll inside dialog.
  static const double dialogContent = 360;

  /// Dialog action footer: below this → 2 buttons stack vertically.
  static const double dialogActionFooter = 280;

  /// Download row content area: below this → ellipsis title.
  static const double downloadRow = 480;

  /// Tab bar (Lịch sử / Playlist).
  static const double tabBar = 240;

  /// Search field below this → shrink placeholder text first.
  static const double searchField = 200;

  /// Filter chip row below this → horizontal scroll inside chip row.
  static const double filterChipRow = 320;
}
