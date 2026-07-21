import 'package:flutter/material.dart';
import '../config/brand_config.dart';

/// Design System — Color Palette v3.1 (Brand-Aware)
/// Colors delegate to [BrandConfig.current] for brand-specific values.
/// Semantic constants (success, warning, etc.) are shared across all brands.
class AppColors {
  AppColors._();

  // ==================== BRAND (delegated) ====================

  static Color get brand => BrandConfig.current.colors.brand;
  static Color get brandLight => BrandConfig.current.colors.brandLight;
  static Color get brandDark => BrandConfig.current.colors.brandDark;
  static Color get accentHighlight => BrandConfig.current.colors.accentHighlight;
  static Color get accentMuted => BrandConfig.current.colors.accentMuted;

  /// Soft, layered card shadow (a tight contact shadow + a wide ambient one)
  /// for elevated surfaces — the refined "premium card" depth used across the
  /// home surfaces. Theme-aware; kept subtle so light mode stays clean.
  static List<BoxShadow> softCardShadow(bool isDark) {
    if (isDark) {
      return const [
        BoxShadow(color: Color(0x38000000), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(
          color: Color(0x4D000000),
          blurRadius: 26,
          offset: Offset(0, 12),
          spreadRadius: -14,
        ),
      ];
    }
    return const [
      BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x0F000000),
        blurRadius: 24,
        offset: Offset(0, 12),
        spreadRadius: -14,
      ),
    ];
  }

  // ==================== LIGHT THEME UTILITY (brand-tinted) ====================
  // Svid: warm tones. VidCombo: cool tones.

  /// Muted foreground — disabled icons, inactive tabs (light mode)
  static Color get lightMuted => BrandConfig.current.colors.lightMuted;

  /// Muted metadata text — timestamps, secondary info (light mode)
  static Color get lightMetaText => BrandConfig.current.colors.lightMetaText;

  /// Base light surface — app background (light mode)
  static Color get lightBase => BrandConfig.current.colors.lightBase;

  /// Elevated light surface — cards, panels (light mode)
  static Color get lightElevated => BrandConfig.current.colors.lightElevated;

  // ==================== DARK THEME UTILITY (brand-tinted) ====================
  // Svid: warm tones (rose/brown). VidCombo: cool tones (blue-gray).

  /// Muted foreground — disabled icons, inactive tabs, subtle borders
  static Color get darkMuted => BrandConfig.current.colors.homeDarkTextMuted;

  /// Light text on dark backgrounds
  static Color get darkLightText => BrandConfig.current.colors.darkLightText;

  /// Muted metadata text — timestamps, secondary info
  static Color get darkMetaText => BrandConfig.current.colors.homeDarkTextSecondary;

  /// Base dark surface — deepest background layer
  static Color get darkBase => BrandConfig.current.colors.darkBase;

  /// Elevated dark surface — cards, panels above base
  static Color get darkElevated => BrandConfig.current.colors.darkElevated;

  // ==================== MISSION BRIEFING TOKENS (delegated) ====================

  /// Deeper-than-base dark surface — inset wells (e.g. quality cards in dialog)
  static Color get darkSurfaceLowest => BrandConfig.current.colors.darkSurfaceLowest;

  /// Light-mode counterpart — softest tinted card surface
  static Color get lightSurfaceLowest => BrandConfig.current.colors.lightSurfaceLowest;

  /// Brand-specific peach/cyan secondary accent — rotating section icons
  static Color get accentSecondary => BrandConfig.current.colors.accentSecondary;

  /// Brand-specific teal/ice tertiary accent — rare section icons
  static Color get accentTertiary => BrandConfig.current.colors.accentTertiary;

  /// Context-aware deepest surface (dark or light variant)
  static Color surfaceLowest(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? lightSurfaceLowest
          : darkSurfaceLowest;

  // ==================== SEMANTIC CONSTANTS ====================

  static const Color successGreen = Color(0xFF22C55E);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color infoBlue = Color(0xFF3B82F6);

  // ==================== DOWNLOAD STATUS CONSTANTS ====================

  static const Color statusDownloading = Color(0xFF3B82F6);
  static const Color statusQueued = Color(0xFF64748B);
  static const Color statusPostProcessing = Color(0xFF8B5CF6);

  // ==================== LIGHT-MODE STATUS COLORS ====================

  static const Color warningAmberLight = Color(0xFFD97706);
  static const Color infoBlueLight = Color(0xFF2563EB);
  static const Color statusQueuedLight = Color(0xFF475569);
  static const Color statusPostProcessingLight = Color(0xFF7C3AED);
  static const Color statusInProgress = Color(0xFF0D9488);
  static const Color incognitoAccent = Color(0xFF9333EA);

  // ==================== SEMANTIC BACKGROUND TINTS ====================

  static const Color warningBgDark = Color(0xFF1A1A0E);
  static const Color warningBgLight = Color(0xFFFFF8E1);
  static const Color warningTextDark = Color(0xFFE0D8A8);
  static const Color warningTextLight = Color(0xFF6D5D00);
  static const Color dangerBgDark = Color(0xFF1A0E0E);
  static const Color dangerBgLight = Color(0xFFFEE2E2);
  static const Color dangerTextDark = Color(0xFFE0A8A8);
  static const Color dangerTextLight = Color(0xFF991B1B);

  // ==================== AUDIO FORMAT BADGES ====================

  static const Color audioFormatMP3 = Color(0xFFF97316);
  static const Color audioFormatM4A = Color(0xFF3B82F6);
  static const Color audioFormatOpus = Color(0xFF8B5CF6);
  static const Color audioFormatWav = Color(0xFF06B6D4);
  static const Color audioFormatFlac = Color(0xFF22C55E);
  static const Color audioFormatDefault = Color(0xFF64748B);

  // ==================== COLOR SCHEMES (delegated) ====================

  static ColorScheme get lightColorScheme => BrandConfig.current.lightColorScheme;
  static ColorScheme get darkColorScheme => BrandConfig.current.darkColorScheme;

  // ==================== SURFACE TOKENS (brand-delegated) ====================
  // Runtime getters — values tint per active brand (Svid warm / VidCombo cool).
  // Callers that used these inside `const` constructors must drop `const`.

  static Color get lightBg => BrandConfig.current.colors.lightBase;
  static Color get lightSurface1 =>
      BrandConfig.current.lightColorScheme.surfaceContainerLowest;
  static Color get lightSurface2 =>
      BrandConfig.current.lightColorScheme.surfaceContainerLow;
  static Color get lightSurface3 =>
      BrandConfig.current.lightColorScheme.surfaceContainer;
  static Color get lightBorder =>
      BrandConfig.current.lightColorScheme.outlineVariant;

  static Color get darkBg => BrandConfig.current.colors.homeDarkAppBg;
  static Color get darkSurface1 =>
      BrandConfig.current.darkColorScheme.surfaceContainer;
  static Color get darkSurface2 =>
      BrandConfig.current.darkColorScheme.surfaceContainerHigh;
  static Color get darkSurface3 =>
      BrandConfig.current.darkColorScheme.surfaceContainerHighest;
  static Color get darkBorder =>
      BrandConfig.current.darkColorScheme.outlineVariant;

  // ==================== HOME DARK OPERATOR TOKENS ====================
  // Semantic surface ladder for Home screen dark mode.
  // All values are flat opaque — no alpha, no opacity stack.

  static Color get homeDarkAppBg       => BrandConfig.current.colors.homeDarkAppBg;
  static Color get homeDarkCardBg      => BrandConfig.current.colors.homeDarkCardBg;
  static Color get homeDarkCardHover   => BrandConfig.current.colors.homeDarkCardHover;
  static Color get homeDarkCardSelected => BrandConfig.current.colors.homeDarkCardSelected;
  static Color get homeDarkCardActive  => BrandConfig.current.colors.homeDarkCardActive;
  static Color get homeDarkBorderSubtle => BrandConfig.current.colors.homeDarkBorderSubtle;
  static Color get homeDarkBorderStrong => BrandConfig.current.colors.homeDarkBorderStrong;
  static Color get homeDarkTextSecondary => BrandConfig.current.colors.homeDarkTextSecondary;
  static Color get homeDarkTextMuted   => BrandConfig.current.colors.homeDarkTextMuted;
  static Color get homeDarkInputBorder => BrandConfig.current.colors.homeDarkInputBorder;
  static Color get homeDarkAccentSoft  => BrandConfig.current.colors.homeDarkAccentSoft;

  // ==================== LEGACY COMPAT CONSTANTS ====================

  static const Color lightOnSuccess = Color(0xFFFFFFFF);
  static const Color lightOnWarning = Color(0xFFFFFFFF);
  static const Color lightOnInfo = Color(0xFFFFFFFF);
  static const Color darkOnSuccess = Color(0xFF052E16);
  static const Color darkOnWarning = Color(0xFF451A03);
  static const Color darkOnInfo = Color(0xFF1E3A5F);

  static const Color lightStatusActive = Color(0xFF2563EB);
  static const Color lightStatusActiveContainer = Color(0xFFDBEAFE);
  static const Color lightStatusCompleted = Color(0xFF16A34A);
  static const Color lightStatusCompletedContainer = Color(0xFFDCFCE7);
  static const Color lightStatusPaused = Color(0xFFD97706);
  static const Color lightStatusPausedContainer = Color(0xFFFEF3C7);
  static const Color lightStatusFailed = Color(0xFFDC2626);
  static const Color lightStatusFailedContainer = Color(0xFFFEE2E2);
  static const Color lightStatusCancelled = Color(0xFF64748B);
  static const Color lightStatusCancelledContainer = Color(0xFFF1F5F9);

  static const Color darkStatusActive = Color(0xFF60A5FA);
  static const Color darkStatusActiveContainer = Color(0xFF1E3A5F);
  static const Color darkStatusCompleted = Color(0xFF4ADE80);
  static const Color darkStatusCompletedContainer = Color(0xFF14532D);
  static const Color darkStatusPaused = Color(0xFFFBBF24);
  static const Color darkStatusPausedContainer = Color(0xFF78350F);
  static const Color darkStatusFailed = Color(0xFFFCA5A5);
  static const Color darkStatusFailedContainer = Color(0xFF7F1D1D);
  static const Color darkStatusCancelled = Color(0xFF94A3B8);
  static const Color darkStatusCancelledContainer = Color(0xFF334155);

  // V2 row-state extensions (Spec §8.3 — 9 row states).
  // The original 5-state set above (active/completed/paused/failed/cancelled)
  // is preserved verbatim; the four sets below complete the spec.
  // Pass 2A finding: 4 row states were missing container pairs.

  /// Downloading state: distinct from generic "active". Text/icon color.
  static const Color lightStatusDownloading = Color(0xFF1D4ED8);
  static const Color lightStatusDownloadingContainer = Color(0xFFDBEAFE);
  static const Color darkStatusDownloading = Color(0xFF93C5FD);
  static const Color darkStatusDownloadingContainer = Color(0xFF1E3A5F);

  /// Post-processing state (FFmpeg merge, conversion). Purple family.
  static const Color lightStatusPostProcessing = Color(0xFF7E22CE);
  static const Color lightStatusPostProcessingContainer = Color(0xFFF3E8FF);
  static const Color darkStatusPostProcessing = Color(0xFFD8B4FE);
  static const Color darkStatusPostProcessingContainer = Color(0xFF581C87);

  /// Pending state — "Sắp tải" (preparing, not yet queued).
  /// Subtle slate, distinguishable from generic "queued" by lighter tone.
  static const Color lightStatusPending = Color(0xFF64748B);
  static const Color lightStatusPendingContainer = Color(0xFFE2E8F0);
  static const Color darkStatusPending = Color(0xFF94A3B8);
  static const Color darkStatusPendingContainer = Color(0xFF1E293B);

  /// Waiting-for-network — auto-retry when online. Amber/yellow family.
  static const Color lightStatusWaitingForNetwork = Color(0xFFB45309);
  static const Color lightStatusWaitingForNetworkContainer = Color(0xFFFEF3C7);
  static const Color darkStatusWaitingForNetwork = Color(0xFFFCD34D);
  static const Color darkStatusWaitingForNetworkContainer = Color(0xFF78350F);

  static const Color lightSuccess = Color(0xFF16A34A);
  static const Color lightSuccessContainer = Color(0xFFDCFCE7);
  static const Color darkSuccess = Color(0xFF4ADE80);
  static const Color darkSuccessContainer = Color(0xFF14532D);

  // ==================== CONTEXT-AWARE HELPERS ====================

  static Color surface1(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightSurface1 : darkSurface1;

  static Color surface2(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightSurface2 : darkSurface2;

  static Color surface3(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightSurface3 : darkSurface3;

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightBorder : darkBorder;

  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightSuccess : darkSuccess;

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? warningAmberLight : const Color(0xFFFCD34D);

  static Color info(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? infoBlueLight : const Color(0xFF93C5FD);

  static Color warningBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? warningBgLight : warningBgDark;

  static Color warningText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? warningTextLight : warningTextDark;

  static Color dangerBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? dangerBgLight : dangerBgDark;

  static Color dangerText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? dangerTextLight : dangerTextDark;

  static Color statusActive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusActive : darkStatusActive;

  static Color statusCompleted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusCompleted : darkStatusCompleted;

  static Color statusPaused(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPaused : darkStatusPaused;

  static Color statusFailed(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusFailed : darkStatusFailed;

  static Color statusCancelled(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusCancelled : darkStatusCancelled;

  static Color statusActiveContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusActiveContainer : darkStatusActiveContainer;

  static Color statusCompletedContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusCompletedContainer : darkStatusCompletedContainer;

  static Color statusPausedContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPausedContainer : darkStatusPausedContainer;

  static Color statusFailedContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusFailedContainer : darkStatusFailedContainer;

  static Color statusCancelledContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusCancelledContainer : darkStatusCancelledContainer;

  // V2 row-state context helpers (Spec §8.3).
  // NOTE: `statusDownloading` and `statusPostProcessing` already exist as
  // raw const colors above (line 80-82) used by the converter feature. The
  // theme-aware V2 row text/container colors expose `*Row` helpers below.

  static Color statusDownloadingRow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusDownloading : darkStatusDownloading;

  static Color statusDownloadingContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusDownloadingContainer : darkStatusDownloadingContainer;

  static Color statusPostProcessingRow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPostProcessing : darkStatusPostProcessing;

  static Color statusPostProcessingContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPostProcessingContainer : darkStatusPostProcessingContainer;

  static Color statusPending(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPending : darkStatusPending;

  static Color statusPendingContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusPendingContainer : darkStatusPendingContainer;

  static Color statusWaitingForNetwork(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusWaitingForNetwork : darkStatusWaitingForNetwork;

  static Color statusWaitingForNetworkContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightStatusWaitingForNetworkContainer : darkStatusWaitingForNetworkContainer;

  // ==================== BRAND-AWARE CONTEXT HELPERS ====================
  // These use BrandColors for per-brand tinting (warm Svid vs cool VidCombo).

  /// Muted foreground — disabled icons, inactive tabs
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightMuted : darkMuted;

  /// Metadata text — timestamps, secondary info. Full opacity, WCAG AA safe.
  static Color metaText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightMetaText : darkMetaText;

  /// Base surface — deepest background layer
  static Color base(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightBase : darkBase;

  /// Elevated surface — cards, panels above base
  static Color elevated(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? lightElevated : darkElevated;
}

/// Semantic opacity constants — replaces arbitrary alpha values across the app.
/// Use with `.withValues(alpha: AppOpacity.hover)` etc.
class AppOpacity {
  AppOpacity._();

  /// Hover overlays, subtle highlights (0.08)
  static const double hover = 0.08;

  /// Active/pressed state overlays (0.12)
  static const double pressed = 0.12;

  /// Subtle dividers, hairline borders (0.06)
  static const double divider = 0.06;

  /// Disabled elements — Material Design spec (0.38)
  static const double disabled = 0.38;

  /// Secondary text, inactive icons (0.60)
  static const double secondary = 0.60;

  /// Modal background overlays (0.50)
  static const double overlay = 0.50;

  /// Backdrop scrim (0.32)
  static const double scrim = 0.32;

  /// Subtle borders, faint highlights (0.15)
  static const double subtle = 0.15;

  /// Quarter opacity — light wash, soft tint (0.25)
  static const double quarter = 0.25;

  /// Medium transparency — semi-visible backgrounds (0.40)
  static const double medium = 0.40;

  /// Strong overlay — near-opaque elements (0.70)
  static const double strong = 0.70;

  /// Near-opaque — very faint transparency (0.85)
  static const double nearOpaque = 0.85;
}
