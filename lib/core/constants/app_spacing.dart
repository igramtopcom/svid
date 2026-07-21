import 'package:flutter/material.dart';

import '../config/brand_config.dart';

/// Application spacing constants
/// Provides consistent spacing scale throughout the app
class AppSpacing {
  AppSpacing._();

  // ==================== SPACING SCALE ====================

  /// Extra extra small spacing (2px)
  static const double xxs = 2.0;

  /// Extra small spacing (4px)
  static const double xs = 4.0;

  /// Small spacing (8px)
  static const double sm = 8.0;

  /// Small-medium spacing (12px) — between sm and md
  static const double smMd = 12.0;

  /// Medium spacing (16px) - DEFAULT
  static const double md = 16.0;

  /// Medium-large spacing (20px) — between md and lg
  static const double mdLg = 20.0;

  /// Large spacing (24px)
  static const double lg = 24.0;

  /// Extra large spacing (32px)
  static const double xl = 32.0;

  /// Extra extra large spacing (48px)
  static const double xxl = 48.0;

  /// Extra extra extra large spacing (64px)
  static const double xxxl = 64.0;

  // ==================== EDGE INSETS HELPERS ====================

  /// Edge insets helpers for common use cases
  static const edgeInsets = _EdgeInsetsHelper();
}

/// Helper class for EdgeInsets shortcuts
class _EdgeInsetsHelper {
  const _EdgeInsetsHelper();

  // All sides
  EdgeInsets get xxs => const EdgeInsets.all(AppSpacing.xxs);
  EdgeInsets get xs => const EdgeInsets.all(AppSpacing.xs);
  EdgeInsets get sm => const EdgeInsets.all(AppSpacing.sm);
  EdgeInsets get md => const EdgeInsets.all(AppSpacing.md);
  EdgeInsets get lg => const EdgeInsets.all(AppSpacing.lg);
  EdgeInsets get xl => const EdgeInsets.all(AppSpacing.xl);
  EdgeInsets get xxl => const EdgeInsets.all(AppSpacing.xxl);

  // Horizontal
  EdgeInsets get horizontalXs => const EdgeInsets.symmetric(horizontal: AppSpacing.xs);
  EdgeInsets get horizontalSm => const EdgeInsets.symmetric(horizontal: AppSpacing.sm);
  EdgeInsets get horizontalMd => const EdgeInsets.symmetric(horizontal: AppSpacing.md);
  EdgeInsets get horizontalLg => const EdgeInsets.symmetric(horizontal: AppSpacing.lg);
  EdgeInsets get horizontalXl => const EdgeInsets.symmetric(horizontal: AppSpacing.xl);

  // Vertical
  EdgeInsets get verticalXs => const EdgeInsets.symmetric(vertical: AppSpacing.xs);
  EdgeInsets get verticalSm => const EdgeInsets.symmetric(vertical: AppSpacing.sm);
  EdgeInsets get verticalMd => const EdgeInsets.symmetric(vertical: AppSpacing.md);
  EdgeInsets get verticalLg => const EdgeInsets.symmetric(vertical: AppSpacing.lg);
  EdgeInsets get verticalXl => const EdgeInsets.symmetric(vertical: AppSpacing.xl);

  // Common component patterns
  EdgeInsets get cardContent =>
      const EdgeInsets.all(AppSpacing.sm); // 8px all
  EdgeInsets get panelSection =>
      const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm); // 16h × 8v
  EdgeInsets get listItemContent =>
      const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs); // 8h × 4v
}

/// Brand-aware radius tokens — reads from BrandConfig at runtime.
/// Svid: angular (3px) — Nocturne Cinematic
/// VidCombo: rounded (8-12px, pill buttons) — Arctic Command
class AppRadius {
  AppRadius._();

  // ==================== SEMANTIC TOKENS (brand-aware) ====================

  /// Card/container radius — most common, use for custom BoxDecorations
  static double get card => BrandConfig.current.cardRadius;

  /// Button radius — elevated, text, outlined, filled, icon, FAB
  static double get button => BrandConfig.current.buttonRadius;

  /// Input field radius — text fields, search bars
  static double get input => BrandConfig.current.inputRadius;

  /// Dialog/picker radius
  static double get dialog => BrandConfig.current.dialogRadius;

  /// Chip/tag radius — chips, filter pills, badges
  static double get chip => BrandConfig.current.chipRadius;

  /// Popup/tooltip/menu radius — context menus, dropdowns, tooltips
  static double get popup => BrandConfig.current.popupRadius;

  /// Full circle (999px) — pills, avatars, circular elements
  static const double full = 999.0;

  // ==================== BORDER RADIUS HELPERS ====================

  static const borderRadius = _BorderRadiusHelper();
  static const radius = _RadiusHelper();
}

/// Helper class for BorderRadius shortcuts
class _BorderRadiusHelper {
  const _BorderRadiusHelper();

  BorderRadius get card => BorderRadius.circular(AppRadius.card);
  BorderRadius get button => BorderRadius.circular(AppRadius.button);
  BorderRadius get input => BorderRadius.circular(AppRadius.input);
  BorderRadius get dialog => BorderRadius.circular(AppRadius.dialog);
  BorderRadius get chip => BorderRadius.circular(AppRadius.chip);
  BorderRadius get popup => BorderRadius.circular(AppRadius.popup);
  BorderRadius get full => BorderRadius.circular(AppRadius.full);

  // PR #234 reconcile: t-shirt size shortcuts (xs/sm/md/lg) used by
  // download_config_dialog + config_preferences_panel. Maps to AppSpacing
  // scale so V2 visual consistency preserved.
  BorderRadius get xs => BorderRadius.circular(AppSpacing.xs);
  BorderRadius get sm => BorderRadius.circular(AppSpacing.sm);
  BorderRadius get md => BorderRadius.circular(AppSpacing.md);
  BorderRadius get lg => BorderRadius.circular(AppSpacing.lg);
}

/// Helper class for individual Radius shortcuts
class _RadiusHelper {
  const _RadiusHelper();

  Radius get card => Radius.circular(AppRadius.card);
  Radius get button => Radius.circular(AppRadius.button);
  Radius get input => Radius.circular(AppRadius.input);
  Radius get dialog => Radius.circular(AppRadius.dialog);
  Radius get chip => Radius.circular(AppRadius.chip);
  Radius get popup => Radius.circular(AppRadius.popup);
  Radius get full => Radius.circular(AppRadius.full);

  // PR #234 reconcile shortcuts.
  Radius get xs => Radius.circular(AppSpacing.xs);
  Radius get sm => Radius.circular(AppSpacing.sm);
  Radius get md => Radius.circular(AppSpacing.md);
  Radius get lg => Radius.circular(AppSpacing.lg);
}

/// Gap helpers for Row/Column spacing (modern alternative to SizedBox)
class Gap extends StatelessWidget {
  final double size;

  const Gap(this.size, {super.key});

  // Named constructors for common gaps
  const Gap.xxs({super.key}) : size = AppSpacing.xxs;
  const Gap.xs({super.key}) : size = AppSpacing.xs;
  const Gap.sm({super.key}) : size = AppSpacing.sm;
  const Gap.smMd({super.key}) : size = AppSpacing.smMd;
  const Gap.md({super.key}) : size = AppSpacing.md;
  const Gap.mdLg({super.key}) : size = AppSpacing.mdLg;
  const Gap.lg({super.key}) : size = AppSpacing.lg;
  const Gap.xl({super.key}) : size = AppSpacing.xl;
  const Gap.xxl({super.key}) : size = AppSpacing.xxl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size);
  }
}
