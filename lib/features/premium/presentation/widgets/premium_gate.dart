import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/premium_feature.dart';
import '../providers/premium_providers.dart';
import 'upgrade_prompt_dialog.dart';

/// Nocturne Cinematic feature gate — "The Glass Wall".
///
/// 3-layer sandwich: blurred content → glass frost → gate overlay.
/// When premium, renders [child] normally.
///
/// Design ref: Stitch `ac7c1235` — docs/design-specs/premium-glass-wall.md
class PremiumGate extends ConsumerWidget {
  final PremiumFeature feature;
  final Widget child;

  /// Optional feature name override for the lock overlay.
  final String? featureLabel;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.child,
    this.featureLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = ref.watch(premiumFeatureProvider(feature));

    if (isAvailable) return child;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Layer 0: Blurred content (teaser) — blur(8px), 40% opacity
        IgnorePointer(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Opacity(opacity: 0.4, child: child),
          ),
        ),

        // Layer 1: Glass frost — gradient mask fading from transparent to frosted
        Positioned.fill(
          child: IgnorePointer(
            child: ShaderMask(
              shaderCallback:
                  (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0.0, 0.15],
                  ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColoredBox(
                  color: cs.surface.withValues(alpha: isDark ? 0.56 : 0.42),
                ),
              ),
            ),
          ),
        ),

        // Layer 2: Gate overlay — lock + CTA
        Positioned.fill(
          child: _GateOverlay(
            feature: feature,
            featureLabel: featureLabel,
            onUpgrade:
                () => UpgradePromptDialog.showAndNavigate(
                  context,
                  ref,
                  feature: feature,
                ),
          ),
        ),
      ],
    );
  }
}

/// Centered gate overlay with glowing lock icon, badge, title, and CTA.
class _GateOverlay extends StatelessWidget {
  final PremiumFeature feature;
  final String? featureLabel;
  final VoidCallback onUpgrade;

  const _GateOverlay({
    required this.feature,
    this.featureLabel,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = BrandConfig.current.colors;
    final accent = isDark ? colors.accentHighlight : colors.brand;
    final surface = isDark ? colors.darkElevated : colors.lightElevated;
    final border = isDark ? colors.homeDarkBorderStrong : colors.lightMuted;
    final primaryText = isDark ? colors.darkLightText : cs.onSurface;
    final secondaryText = isDark ? colors.darkMetaText : colors.lightMetaText;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: surface.withValues(alpha: isDark ? 0.94 : 0.96),
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LockIconWithGlow(primaryColor: accent),

                const SizedBox(height: AppSpacing.md),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.36 : 0.24),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppLocalizations.premiumGateBadge.toUpperCase(),
                    style: AppTypography.compact.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: accent,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.mdLg),

                Text(
                  featureLabel ?? AppLocalizations.premiumGateLocked,
                  style: tt.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: primaryText,
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.sm),

                Text(
                  AppLocalizations.premiumGateUpgradeToUnlock,
                  style: tt.bodyLarge?.copyWith(
                    color: secondaryText,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.xl),

                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BrandConfig.current.premiumGradient,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withValues(
                          alpha: AppOpacity.quarter,
                        ),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: MaterialButton(
                      onPressed: onUpgrade,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.smMd,
                      ),
                      child: Text(
                        AppLocalizations.premiumUpgrade,
                        style: AppTypography.appBarTitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                Text(
                  AppLocalizations.premiumGateTrustSignals.toUpperCase(),
                  style: AppTypography.compact.copyWith(
                    letterSpacing: 0.8,
                    color: secondaryText.withValues(alpha: AppOpacity.medium),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lock icon in a circle with a glowing halo behind it.
class _LockIconWithGlow extends StatelessWidget {
  final Color primaryColor;

  const _LockIconWithGlow({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = BrandConfig.current.colors;

    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow halo
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryColor.withValues(alpha: AppOpacity.quarter),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Lock circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? colors.darkBase : colors.lightBase,
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryColor.withValues(alpha: AppOpacity.quarter),
              ),
            ),
            child: Icon(Icons.lock_rounded, size: 28, color: primaryColor),
          ),
        ],
      ),
    );
  }
}
