import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/services/clipboard_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_transitions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/premium_feature.dart';
import '../../domain/entities/premium_license.dart';
import '../providers/payment_providers.dart';
import '../providers/premium_providers.dart';
import '../widgets/upgrade_prompt_dialog.dart';

/// Nocturne Cinematic celebration screen — "Welcome Home".
///
/// Full-page cinematic celebration shown after payment success or manual license
/// activation. Replaces the old AlertDialog success prompt.
///
/// Design ref: Stitch `631d2228` — docs/design-specs/premium-welcome-home.md
class PremiumWelcomeScreen extends ConsumerWidget {
  const PremiumWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // Layer 0: Atmospheric background
          _WelcomeBackgroundEffects(isDark: isDark),

          // Layer 1: Scrollable content
          SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal:
                  MediaQuery.sizeOf(context).width < 560
                      ? AppSpacing.lg
                      : AppSpacing.xxl,
            ).copyWith(top: AppSpacing.xxxl, bottom: 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    const _CelebrationHeader(),
                    const SizedBox(height: AppSpacing.xxl),
                    const _LicenseKeyCard(),
                    const SizedBox(height: AppSpacing.lg),
                    const _SubscriptionSummary(),
                    const SizedBox(height: AppSpacing.xl),
                    const _UnlockedFeaturesBento(),
                    const SizedBox(height: AppSpacing.xxl),
                    _WelcomeCtas(
                      onDone: () {
                        ref.read(paymentProvider.notifier).reset();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Layer 2: Bottom gradient overlay (fixed, non-interactive)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.of(context).size.height / 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [cs.surface, cs.surface.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== BACKGROUND EFFECTS ====================

class _WelcomeBackgroundEffects extends StatelessWidget {
  final bool isDark;
  const _WelcomeBackgroundEffects({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Premium radial glow
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.7,
                colors: [
                  AppColors.brand.withValues(
                    alpha: isDark ? AppOpacity.subtle : AppOpacity.hover,
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Shimmer dots pattern
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.30 : 0.15,
            child: const CustomPaint(painter: _ShimmerDotsPainter()),
          ),
        ),

        // Bottom-right orb
        Positioned(
          bottom: -192,
          right: -192,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: AppOpacity.divider),
              ),
            ),
          ),
        ),

        // Center orb
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).size.height * 0.2,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 150, sigmaY: 150),
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: 600,
              color: AppColors.brand.withValues(alpha: AppOpacity.divider),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerDotsPainter extends CustomPainter {
  const _ShimmerDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = BrandConfig.current.colors.gradientTail.withValues(
            alpha: AppOpacity.divider,
          )
          ..style = PaintingStyle.fill;
    const step = 40.0;
    for (double x = 2; x < size.width; x += step) {
      for (double y = 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== CELEBRATION HEADER ====================

class _CelebrationHeader extends StatefulWidget {
  const _CelebrationHeader();

  @override
  State<_CelebrationHeader> createState() => _CelebrationHeaderState();
}

class _CelebrationHeaderState extends State<_CelebrationHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? AppColors.darkLightText : AppColors.darkSurface1;
    final accentColor = BrandConfig.current.colors.gradientTail;

    return Column(
      children: [
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [baseColor, accentColor, baseColor],
                  stops: const [0.2, 0.5, 0.8],
                  transform: _SlideGradientTransform(_shimmerController.value),
                ).createShader(bounds);
              },
              child: Text(
                AppLocalizations.premiumWelcomeTitle,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1.44,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.smMd),
        Text(
          AppLocalizations.premiumWelcomeSubtitle.toUpperCase(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w300,
            letterSpacing: 3.2,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlideGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 0.5),
      0,
      0,
    );
  }
}

// ==================== LICENSE KEY CARD ====================

class _LicenseKeyCard extends ConsumerStatefulWidget {
  const _LicenseKeyCard();

  @override
  ConsumerState<_LicenseKeyCard> createState() => _LicenseKeyCardState();
}

class _LicenseKeyCardState extends ConsumerState<_LicenseKeyCard> {
  bool _copied = false;

  Future<void> _copyKey(String key) async {
    await ClipboardService.setText(key);
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final license = ref.watch(premiumLicenseProvider);
    final licenseKey = license.licenseKey ?? '—';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: cs.surfaceContainer.withValues(alpha: AppOpacity.secondary),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: cs.onSurface.withValues(alpha: AppOpacity.divider),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: AppOpacity.medium),
                blurRadius: 25,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.premiumWelcomeActivationKey.toUpperCase(),
                style: AppTypography.sectionHeader.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  final keyBox = Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(
                        alpha: AppOpacity.secondary,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(
                          alpha: AppOpacity.divider,
                        ),
                      ),
                    ),
                    child: Text(
                      licenseKey,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: [
                          'SF Mono',
                          'Consolas',
                          'Menlo',
                          'monospace',
                        ],
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.4,
                      ).copyWith(color: cs.primary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  final copyButton = Container(
                    width: compact ? double.infinity : null,
                    decoration: BoxDecoration(
                      gradient: AppGradients.premium,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _copyKey(licenseKey),
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        _copied
                            ? AppLocalizations.premiumWelcomeCopied
                            : AppLocalizations.premiumWelcomeCopy,
                        style: AppTypography.buttonSecondary.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.mdLg,
                          vertical: AppSpacing.md,
                        ),
                      ),
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        keyBox,
                        const SizedBox(height: AppSpacing.smMd),
                        copyButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: keyBox),
                      const SizedBox(width: AppSpacing.smMd),
                      copyButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.premiumWelcomeSaveKeyWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(
                    alpha: AppOpacity.strong,
                  ),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== SUBSCRIPTION SUMMARY ====================

class _SubscriptionSummary extends ConsumerWidget {
  const _SubscriptionSummary();

  String _cycleName(BillingCycle? cycle) => switch (cycle) {
    BillingCycle.monthly => AppLocalizations.premiumMonthly,
    BillingCycle.semiannual => AppLocalizations.premiumSemiannual,
    BillingCycle.yearly => AppLocalizations.premiumYearly,
    BillingCycle.p7 => AppLocalizations.premiumMemberDurationDays(7),
    BillingCycle.p30 => AppLocalizations.premiumMemberDurationDays(30),
    BillingCycle.p90 => AppLocalizations.premiumMemberDurationDays(90),
    BillingCycle.lifetime => AppLocalizations.premiumLifetime,
    BillingCycle.lifetime1 => AppLocalizations.premiumLifetime1,
    BillingCycle.lifetime2 => AppLocalizations.premiumLifetime2,
    BillingCycle.lifetime3 => AppLocalizations.premiumLifetime3,
    null => AppLocalizations.premiumPremiumLabel,
  };

  String _formatDate(DateTime date) {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final license = ref.watch(premiumLicenseProvider);

    Widget pane({
      required String eyebrow,
      required String title,
      required String detail,
    }) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: AppTypography.sectionHeader.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final planPane = pane(
      eyebrow: AppLocalizations.premiumWelcomePlanDetails,
      title: _cycleName(license.billingCycle),
      detail:
          license.paymentMethod == 'crypto'
              ? AppLocalizations.premiumWelcomePaidViaCrypto
              : license.paymentMethod == 'paypal_pdfconv'
              ? 'PayPal'
              : AppLocalizations.premiumWelcomePaidViaStripe,
    );
    final billingDateLabel =
        license.isAutoRenew
            ? AppLocalizations.premiumRenewsOn
            : AppLocalizations.premiumExpiresOn;
    final billingPane = pane(
      eyebrow: AppLocalizations.premiumWelcomeBillingInfo,
      title:
          license.billingCycle?.isLifetime == true
              ? AppLocalizations.premiumActiveSubscription
              : license.expiresAt != null
              ? '$billingDateLabel ${_formatDate(license.expiresAt!)}'
              : AppLocalizations.premiumActiveSubscription,
      detail:
          license.billingCycle?.isLifetime == true
              ? AppLocalizations.premiumWelcomeOneTimePurchase
              : license.isAutoRenew
              ? AppLocalizations.premiumMemberAutoRenewalEnabled
              : AppLocalizations.premiumWelcomeManualRenewal,
    );

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: AppOpacity.quarter),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                planPane,
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(
                    alpha: AppOpacity.quarter,
                  ),
                ),
                billingPane,
              ],
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: planPane),
                VerticalDivider(
                  width: 1,
                  color: cs.outlineVariant.withValues(
                    alpha: AppOpacity.quarter,
                  ),
                ),
                Expanded(child: billingPane),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==================== UNLOCKED FEATURES BENTO ====================

/// 4 representative features to showcase on the welcome screen.
const _highlightedFeatures = [
  PremiumFeature.unlimitedDownloads,
  PremiumFeature.highQuality4K,
  PremiumFeature.advancedPlayer,
  PremiumFeature.smartCollections,
];

class _UnlockedFeaturesBento extends StatelessWidget {
  const _UnlockedFeaturesBento();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.premiumWelcomeUnlockedFeatures.toUpperCase(),
          style: AppTypography.sectionHeader.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth < 460
                    ? 1
                    : constraints.maxWidth < 680
                    ? 2
                    : 4;
            final gap = AppSpacing.smMd;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final feature in _highlightedFeatures)
                  SizedBox(width: width, child: _BentoCell(feature: feature)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BentoCell extends StatefulWidget {
  final PremiumFeature feature;
  const _BentoCell({required this.feature});

  @override
  State<_BentoCell> createState() => _BentoCellState();
}

class _BentoCellState extends State<_BentoCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: AnimatedScale(
        scale: _isHovered ? 1.10 : 1.0,
        duration: AppTransitions.fast,
        curve: AppTransitions.curveEnter,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: cs.outlineVariant.withValues(
                alpha: _isHovered ? 0.3 : 0.15,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: AppOpacity.quarter),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  UpgradePromptDialog.featureIcon(widget.feature),
                  size: 24,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.smMd),
              Text(
                UpgradePromptDialog.featureDisplayName(widget.feature),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== CTAs ====================

class _WelcomeCtas extends StatefulWidget {
  final VoidCallback onDone;
  const _WelcomeCtas({required this.onDone});

  @override
  State<_WelcomeCtas> createState() => _WelcomeCtasState();
}

class _WelcomeCtasState extends State<_WelcomeCtas> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: AppTransitions.fast,
            curve: AppTransitions.curveEnter,
            child: AnimatedContainer(
              duration: AppTransitions.fast,
              constraints: const BoxConstraints(minWidth: 320),
              decoration: BoxDecoration(
                gradient: AppGradients.premiumExtended,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: AppOpacity.medium),
                    blurRadius: _isHovered ? 35 : 25,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextButton(
                onPressed: widget.onDone,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                    vertical: AppSpacing.mdLg,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
                child: Text(
                  AppLocalizations.premiumWelcomeStartExploring,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: widget.onDone,
          child: Text(
            AppLocalizations.premiumManageSubscription,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: cs.primary),
          ),
        ),
      ],
    );
  }
}
