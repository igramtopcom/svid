import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../../core/providers/navigation_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/premium_feature.dart';

/// Nocturne Cinematic upgrade prompt — "The Velvet Rope".
///
/// Contextual modal shown when a user attempts a Premium-only feature.
/// Shows the gated feature front-and-center with value props and a gradient CTA.
///
/// Design ref: Stitch `351adcfd` — docs/design-specs/premium-velvet-rope.md
/// Returns `true` if user taps Upgrade, `null` if dismissed.
class UpgradePromptDialog extends StatelessWidget {
  final PremiumFeature? feature;

  const UpgradePromptDialog({super.key, this.feature});

  /// Show the upgrade prompt dialog.
  /// Returns `true` if user taps Upgrade, `null` if dismissed.
  static Future<bool?> show(BuildContext context, {PremiumFeature? feature}) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => UpgradePromptDialog(feature: feature),
    );
  }

  /// Show the upgrade prompt and navigate to Premium screen if user taps Upgrade.
  static Future<void> showAndNavigate(
    BuildContext context,
    WidgetRef ref, {
    PremiumFeature? feature,
  }) async {
    final result = await show(context, feature: feature);
    if (result == true && context.mounted) {
      ref
          .read(navigationProvider.notifier)
          .navigateToTab(NavigationConstants.premiumIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColors = BrandConfig.current.colors;
    final surface =
        isDark ? brandColors.darkElevated : brandColors.lightElevated;
    final border =
        isDark ? brandColors.homeDarkBorderStrong : brandColors.lightMuted;
    final primaryText =
        isDark ? brandColors.darkLightText : const Color(0xFF15171A);
    final secondaryText =
        isDark ? brandColors.darkMetaText : brandColors.lightMetaText;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadius.dialog),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.16),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),

          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl,
                      AppSpacing.xl,
                      AppSpacing.xxl,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        _PremiumIcon(),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          AppLocalizations.premiumUpgradeTitle,
                          textAlign: TextAlign.center,
                          style: tt.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: primaryText,
                            letterSpacing: 0,
                            height: 1.15,
                          ),
                        ),
                        if (feature != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _FeatureHighlightCard(
                            icon: _featureIcon(feature!),
                            name: _featureDisplayName(feature!),
                            description: _featureDescription(feature!),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Column(
                          children: [
                            _ValuePropItem(
                              icon: Icons.all_inclusive,
                              label:
                                  AppLocalizations
                                      .premiumFeatureUnlimitedDownloads,
                            ),
                            const SizedBox(height: AppSpacing.smMd),
                            _ValuePropItem(
                              icon: Icons.hd,
                              label:
                                  AppLocalizations.premiumFeatureHighQuality4K,
                            ),
                            const SizedBox(height: AppSpacing.smMd),
                            _ValuePropItem(
                              icon: Icons.speed,
                              label:
                                  AppLocalizations
                                      .premiumFeatureExtendedConcurrent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.md,
                  AppSpacing.xxl,
                  AppSpacing.xl,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Column(
                  children: [
                    Text(
                      AppLocalizations.premiumSubscriptionCta,
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: secondaryText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.smMd),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: BrandConfig.current.premiumGradient,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          boxShadow: [BrandConfig.current.glowCta],
                        ),
                        child: MaterialButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                          child: Text(
                            AppLocalizations.premiumUpgrade,
                            style: tt.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          MaterialLocalizations.of(context).cancelButtonLabel,
                          style: tt.labelLarge?.copyWith(
                            color: secondaryText,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Feature description for the highlight card.
  static String _featureDescription(PremiumFeature feature) {
    return switch (feature) {
      PremiumFeature.unlimitedDownloads =>
        AppLocalizations.premiumFeatureDescUnlimitedDownloads,
      PremiumFeature.highQuality4K =>
        AppLocalizations.premiumFeatureDescHighQuality4K,
      PremiumFeature.extendedConcurrent =>
        AppLocalizations.premiumFeatureDescExtendedConcurrent,
      PremiumFeature.batchDownload =>
        AppLocalizations.premiumFeatureDescBatchDownload,
      PremiumFeature.advancedPlayer =>
        AppLocalizations.premiumFeatureDescAdvancedPlayer,
      PremiumFeature.browserShield =>
        AppLocalizations.premiumFeatureDescBrowserShield,
      PremiumFeature.scheduledDownloads =>
        AppLocalizations.premiumFeatureDescScheduledDownloads,
      PremiumFeature.bandwidthControl =>
        AppLocalizations.premiumFeatureDescBandwidthControl,
      PremiumFeature.smartCollections =>
        AppLocalizations.premiumFeatureDescSmartCollections,
      PremiumFeature.advancedAnalytics =>
        AppLocalizations.premiumFeatureDescAdvancedAnalytics,
      PremiumFeature.batchImport =>
        AppLocalizations.premiumFeatureDescBatchImport,
      PremiumFeature.prioritySupport =>
        AppLocalizations.premiumFeatureDescPrioritySupport,
      PremiumFeature.mediaConverter =>
        'Convert and edit media with advanced presets, effects, and filters.',
    };
  }

  /// Map feature to an appropriate icon
  static IconData _featureIcon(PremiumFeature feature) {
    return switch (feature) {
      PremiumFeature.unlimitedDownloads => Icons.all_inclusive,
      PremiumFeature.highQuality4K => Icons.hd,
      PremiumFeature.extendedConcurrent => Icons.speed,
      PremiumFeature.batchDownload => Icons.playlist_add_check,
      PremiumFeature.advancedPlayer => Icons.featured_play_list,
      PremiumFeature.browserShield => Icons.shield,
      PremiumFeature.scheduledDownloads => Icons.schedule,
      PremiumFeature.bandwidthControl => Icons.wifi_tethering,
      PremiumFeature.smartCollections => Icons.folder_special,
      PremiumFeature.advancedAnalytics => Icons.bar_chart,
      PremiumFeature.batchImport => Icons.upload_file,
      PremiumFeature.prioritySupport => Icons.support_agent,
      PremiumFeature.mediaConverter => Icons.transform_rounded,
    };
  }

  /// Map feature to a localized user-facing display name
  static String _featureDisplayName(PremiumFeature feature) {
    return switch (feature) {
      PremiumFeature.unlimitedDownloads =>
        AppLocalizations.premiumFeatureUnlimitedDownloads,
      PremiumFeature.highQuality4K =>
        AppLocalizations.premiumFeatureHighQuality4K,
      PremiumFeature.extendedConcurrent =>
        AppLocalizations.premiumFeatureExtendedConcurrent,
      PremiumFeature.batchDownload =>
        AppLocalizations.premiumFeatureBatchDownload,
      PremiumFeature.advancedPlayer =>
        AppLocalizations.premiumFeatureAdvancedPlayer,
      PremiumFeature.browserShield =>
        AppLocalizations.premiumFeatureBrowserShield,
      PremiumFeature.scheduledDownloads =>
        AppLocalizations.premiumFeatureScheduledDownloads,
      PremiumFeature.bandwidthControl =>
        AppLocalizations.premiumFeatureBandwidthControl,
      PremiumFeature.smartCollections =>
        AppLocalizations.premiumFeatureSmartCollections,
      PremiumFeature.advancedAnalytics =>
        AppLocalizations.premiumFeatureAdvancedAnalytics,
      PremiumFeature.batchImport => AppLocalizations.premiumFeatureBatchImport,
      PremiumFeature.prioritySupport =>
        AppLocalizations.premiumFeaturePrioritySupport,
      PremiumFeature.mediaConverter => 'Media Converter',
    };
  }

  /// Get the icon for a premium feature (public for reuse).
  static IconData featureIcon(PremiumFeature feature) => _featureIcon(feature);

  /// Get the localized display name for a premium feature (public for reuse).
  static String featureDisplayName(PremiumFeature feature) =>
      _featureDisplayName(feature);

  /// Get the description for a premium feature (public for reuse).
  static String featureDescription(PremiumFeature feature) =>
      _featureDescription(feature);
}

// ==================== PRIVATE COMPONENTS ====================

/// Rotated gradient icon with glow halo.
class _PremiumIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = BrandConfig.current.colors;
    final accent = isDark ? colors.accentHighlight : colors.brand;
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow halo behind icon
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: AppOpacity.medium),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Rotated gradient square with stars icon
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ(3 * pi / 180),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: BrandConfig.current.premiumGradient,
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: AppOpacity.scrim),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stars_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feature highlight card with left accent border.
class _FeatureHighlightCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;

  const _FeatureHighlightCard({
    required this.icon,
    required this.name,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = BrandConfig.current.colors;
    final accent = isDark ? colors.accentHighlight : colors.brand;
    final surface = isDark ? colors.darkBase : colors.lightBase;
    final textPrimary = isDark ? colors.darkLightText : const Color(0xFF15171A);
    final textSecondary = isDark ? colors.darkMetaText : colors.lightMetaText;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  name,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xl),
            child: Text(
              description,
              style: tt.bodyMedium?.copyWith(color: textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single value proposition row — icon + label.
class _ValuePropItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ValuePropItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = BrandConfig.current.colors;
    final accent = isDark ? colors.accentHighlight : colors.brand;
    final text = isDark ? colors.darkLightText : const Color(0xFF15171A);
    return Row(
      children: [
        Icon(icon, size: 20, color: accent),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Text(
            label,
            style: tt.titleSmall?.copyWith(
              color: text,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
