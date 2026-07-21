import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/startup_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/premium_license.dart';
import '../providers/payment_providers.dart';
import '../providers/premium_providers.dart';

/// Returns the default billing cycles for the current brand.
List<BillingCycle> _brandDefaultCycles() {
  if (BrandConfig.current.brand == Brand.vidcombo) {
    return [
      BillingCycle.p7,
      BillingCycle.p30,
      BillingCycle.p90,
      BillingCycle.lifetime,
    ];
  }
  return [
    BillingCycle.monthly,
    BillingCycle.yearly,
    BillingCycle.lifetime1,
    BillingCycle.lifetime2,
    BillingCycle.lifetime3,
  ];
}

Color _memberPageBg(BuildContext context) {
  final colors = BrandConfig.current.colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? colors.darkBase : colors.lightBase;
}

Color _memberCardBg(BuildContext context) {
  final colors = BrandConfig.current.colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? colors.darkElevated : colors.lightElevated;
}

Color _memberCardBgAlt(BuildContext context) {
  final colors = BrandConfig.current.colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? colors.homeDarkCardHover : colors.lightBase;
}

Color _memberBorder(BuildContext context, {bool strong = false}) {
  final colors = BrandConfig.current.colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return strong ? colors.homeDarkBorderStrong : colors.homeDarkBorderSubtle;
  }
  return strong
      ? Color.alphaBlend(
        colors.brand.withValues(alpha: 0.28),
        colors.lightMuted,
      )
      : colors.lightMuted;
}

Color _memberAccent(BuildContext context) {
  final colors = BrandConfig.current.colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? colors.accentHighlight : colors.brand;
}

List<BoxShadow> _memberShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
      blurRadius: isDark ? 18 : 24,
      offset: const Offset(0, 12),
    ),
  ];
}

/// Nocturne Cinematic subscription dashboard — "Members Lounge".
///
/// Full-page management dashboard shown exclusively to active Premium users.
/// All data driven by [premiumLicenseProvider] and [pricingPlansProvider].
///
/// Design ref: Stitch `83c98c6a` — docs/design-specs/premium-members-lounge.md
class PremiumMembersScreen extends ConsumerWidget {
  const PremiumMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(premiumLicenseProvider);

    return Scaffold(
      backgroundColor: _memberPageBg(context),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: _memberPageBg(context))),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 560
                  ? AppSpacing.md
                  : AppSpacing.lg,
              AppSpacing.lg,
              MediaQuery.sizeOf(context).width < 560
                  ? AppSpacing.md
                  : AppSpacing.lg,
              120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MembershipHeader(license: license),
                const SizedBox(height: AppSpacing.md),
                _DashboardGrid(license: license),
                const SizedBox(height: AppSpacing.lg),
                _TransactionHistorySection(license: license),
                const SizedBox(height: AppSpacing.lg),
                _DeviceManagementCard(license: license),
                const SizedBox(height: AppSpacing.lg),
                _TierSelectorSection(license: license),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _VerificationFooter(license: license),
          ),
        ],
      ),
    );
  }
}

// ==================== MEMBERSHIP HEADER ====================

class _MembershipHeader extends StatelessWidget {
  final PremiumLicense license;
  const _MembershipHeader({required this.license});

  String _formatMonthYear(DateTime date, String locale) {
    return DateFormat.yMMMM(locale).format(date);
  }

  String _cycleLabel(BillingCycle? cycle) => switch (cycle) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final locale = Localizations.localeOf(context).toString();
    final memberSince =
        license.purchaseDate != null
            ? _formatMonthYear(license.purchaseDate!, locale)
            : '—';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _memberCardBg(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context, strong: true)),
        boxShadow: _memberShadow(context),
      ),
      child: Stack(
        children: [
          // Gradient overlay (right 1/3)
          Positioned(
            right: -48,
            top: -48,
            bottom: -48,
            width: 300,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    _memberAccent(
                      context,
                    ).withValues(alpha: AppOpacity.quarter),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _VipBadge(),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, _) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GlowText(
                          AppLocalizations.premiumMemberTitle,
                          style: tt.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smMd),
                        Icon(
                          Icons.workspace_premium,
                          color: _memberAccent(context),
                          size: 36,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.premiumMemberSince(
                  memberSince,
                  _cycleLabel(license.billingCycle),
                ),
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== VIP BADGE ====================

class _VipBadge extends StatelessWidget {
  const _VipBadge();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _memberAccent(context).withValues(alpha: AppOpacity.hover),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _memberBorder(context, strong: true)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.premiumMemberVipAccess,
            style: tt.labelMedium?.copyWith(
              color: _memberAccent(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const _PulseDot(),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFfb7185),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ==================== GLOW TEXT ====================

class _GlowText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _GlowText(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: style?.copyWith(
            foreground:
                Paint()
                  ..color = const Color(
                    0xFFffb3b4,
                  ).withValues(alpha: AppOpacity.medium)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
          ),
        ),
        Text(text, style: style),
      ],
    );
  }
}

// ==================== DASHBOARD GRID ====================

class _DashboardGrid extends StatelessWidget {
  final PremiumLicense license;
  const _DashboardGrid({required this.license});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              _SubscriptionDetailCard(license: license),
              const SizedBox(height: AppSpacing.md),
              _AccountStatusCard(license: license),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: _SubscriptionDetailCard(license: license)),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 5, child: _AccountStatusCard(license: license)),
          ],
        );
      },
    );
  }
}

// ==================== SUBSCRIPTION DETAIL CARD ====================

class _SubscriptionDetailCard extends ConsumerWidget {
  final PremiumLicense license;
  const _SubscriptionDetailCard({required this.license});

  String _formatDate(DateTime date, String locale) {
    return DateFormat.yMMMd(locale).format(date);
  }

  String _paymentMethodLabel(String? method) => switch (method) {
    'stripe' => AppLocalizations.premiumMemberCreditCard,
    'crypto' => AppLocalizations.premiumMemberCryptocurrency,
    'paypal_pdfconv' => 'PayPal',
    _ => '—',
  };

  String _planDisplayName(BillingCycle cycle) => switch (cycle) {
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
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final isPdfConvPayPal = license.paymentMethod == 'paypal_pdfconv';
    final shouldSkipStripePricing =
        isPdfConvPayPal ||
        (BrandConfig.current.hasPdfConvPayPalCheckout &&
            license.paymentMethod == null);
    final AsyncValue<List<PricingPlan>> plansAsync =
        shouldSkipStripePricing
            ? const AsyncValue.data(<PricingPlan>[])
            : ref.watch(pricingPlansProvider);

    // Resolve real price from Stripe
    String planHeader = AppLocalizations.premiumPremiumLabel;
    if (license.billingCycle != null) {
      final planName = _planDisplayName(license.billingCycle!);
      final realPrice = plansAsync.whenOrNull(
        data: (plans) {
          final match = plans.cast<PricingPlan?>().firstWhere(
            (p) => p?.billingCycle == license.billingCycle!.name,
            orElse: () => null,
          );
          if (match == null) return null;
          final suffix = switch (match.interval) {
            'month' => AppLocalizations.premiumMemberPriceSuffixMonth,
            'year' => AppLocalizations.premiumMemberPriceSuffixYear,
            _ => '',
          };
          return '${match.displayPrice}$suffix';
        },
      );
      planHeader = realPrice != null ? '$planName · $realPrice' : planName;
    }

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _memberCardBg(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
        boxShadow: _memberShadow(context),
      ),
      child: Stack(
        children: [
          // Left accent bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: _memberAccent(context)),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(
              28,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: plan + status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.premiumCurrentTier.toUpperCase(),
                            style: AppTypography.sectionHeader.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _memberAccent(context),
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            planHeader,
                            style: tt.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _ActiveStatusBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Detail grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final nextBilling = _DetailCell(
                      label:
                          license.billingCycle?.isLifetime == true
                              ? AppLocalizations.premiumLifetime
                              : license.isAutoRenew
                              ? AppLocalizations.premiumMemberNextBilling
                              : AppLocalizations.premiumExpiresOn,
                      value:
                          license.expiresAt != null
                              ? _formatDate(license.expiresAt!, locale)
                              : (license.billingCycle?.isLifetime ?? false)
                              ? '∞'
                              : '—',
                    );
                    final paymentMethod = _DetailCell(
                      label: AppLocalizations.premiumScreenPaymentMethod,
                      icon:
                          license.paymentMethod == 'crypto'
                              ? Icons.currency_bitcoin_rounded
                              : isPdfConvPayPal
                              ? Icons.account_balance_wallet_outlined
                              : license.paymentMethod != null
                              ? Icons.credit_card_rounded
                              : null,
                      value: _paymentMethodLabel(license.paymentMethod),
                    );

                    if (constraints.maxWidth < 460) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          nextBilling,
                          const SizedBox(height: AppSpacing.smMd),
                          paymentMethod,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: nextBilling),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: paymentMethod),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // License key row
                _LicenseKeyRow(licenseKey: license.licenseKey),
                const SizedBox(height: AppSpacing.md),

                // Auto-renewal toggle — interactive when ON (tap opens
                // cancel confirmation). When already cancelled the toggle
                // renders read-only because re-subscribing requires the
                // full upgrade path, not a single-tap toggle.
                if (!isPdfConvPayPal) ...[
                  _AutoRenewalToggle(
                    isEnabled: license.isAutoRenew,
                    onTap:
                        license.isAutoRenew
                            ? () => _confirmCancelSubscription(context, ref)
                            : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Destructive links
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => _confirmDeactivate(context, ref),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      hoverColor: cs.error.withValues(alpha: AppOpacity.hover),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cancel_outlined,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              AppLocalizations.premiumMemberDeactivateTitle,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!license.isCancelled &&
                        !isPdfConvPayPal &&
                        !(license.billingCycle?.isLifetime ?? false))
                      InkWell(
                        onTap: () => _confirmCancelSubscription(context, ref),
                        child: Text(
                          AppLocalizations.premiumCancelSubscription,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurface.withValues(
                              alpha: AppOpacity.medium,
                            ),
                            decoration: TextDecoration.underline,
                            decorationColor: cs.onSurface.withValues(
                              alpha: AppOpacity.quarter,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                // Already cancelled warning
                if (license.isCancelled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.smMd),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: AppOpacity.hover),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: Colors.orange.withValues(
                          alpha: AppOpacity.quarter,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            AppLocalizations.premiumCancelledInfo,
                            style: tt.bodySmall?.copyWith(color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeactivate(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.premiumMemberDeactivateTitle),
            content: Text(AppLocalizations.premiumMemberDeactivateMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final prefs = ref.read(sharedPreferencesProvider);
                  // Mark explicit user intent + purge stale premium cache
                  // BEFORE deactivating so a concurrent startup task cannot
                  // re-promote from cache mid-tear-down. Tombstone helper is
                  // brand-guarded (no-op on SSvid).
                  await StartupService.setVidComboDeactivateTombstone(prefs);
                  await StartupService.clearVidComboCheckKeyCache(prefs);
                  await ref
                      .read(premiumLicenseProvider.notifier)
                      .deactivateLicense(
                        quotaNotifier: ref.read(
                          downloadQuotaNotifierProvider.notifier,
                        ),
                      );
                },
                child: Text(
                  AppLocalizations.premiumDeactivate,
                  style: AppTypography.buttonSecondary.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _confirmCancelSubscription(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.premiumCancelSubscription),
            content: Text(AppLocalizations.premiumCancelConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.premiumMemberKeepSubscription),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final key = ref.read(premiumLicenseProvider).licenseKey;
                  if (key == null) return;
                  final success = await ref
                      .read(paymentProvider.notifier)
                      .cancelSubscription(key);
                  if (!context.mounted) return;
                  if (success) {
                    AppSnackBar.success(
                      context,
                      message: AppLocalizations.premiumCancelSuccess,
                    );
                  } else {
                    final error = ref.read(paymentProvider).error;
                    AppSnackBar.error(
                      context,
                      message: error ?? AppLocalizations.premiumCancelFailed,
                    );
                  }
                },
                child: Text(
                  AppLocalizations.premiumCancelSubscription,
                  style: AppTypography.buttonSecondary.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

// ==================== SUB-COMPONENTS ====================

class _ActiveStatusBadge extends StatelessWidget {
  const _ActiveStatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _memberCardBgAlt(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _memberBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.successGreen,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 6, height: 6),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.premiumMemberLicenseActive,
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.successGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const _DetailCell({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.compact.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: cs.onSurface),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(color: cs.onSurface),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LicenseKeyRow extends StatelessWidget {
  final String? licenseKey;
  const _LicenseKeyRow({this.licenseKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        color: _memberCardBgAlt(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.premiumMemberMasterKey.toUpperCase(),
            style: AppTypography.compact.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  licenseKey ?? '—',
                  style: AppTypography.statusBadge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (licenseKey != null)
                IconButton(
                  onPressed: () {
                    ClipboardService.setText(licenseKey!);
                    AppSnackBar.info(
                      context,
                      message: AppLocalizations.premiumMemberKeyCopied,
                      duration: const Duration(seconds: 2),
                    );
                  },
                  icon: Icon(
                    Icons.copy_all_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: AppLocalizations.premiumCryptoCopyAddress,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutoRenewalToggle extends StatelessWidget {
  final bool isEnabled;

  /// Tapping the toggle invokes [onTap]. When auto-renew is currently on,
  /// the caller wires this to the cancel-subscription confirmation flow.
  /// When auto-renew is off (already cancelled), [onTap] is typically null
  /// so the toggle renders read-only — re-subscribing requires the regular
  /// upgrade path, not a single-tap toggle.
  final VoidCallback? onTap;

  const _AutoRenewalToggle({required this.isEnabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final content = Row(
      children: [
        Container(
          width: 36,
          height: 20,
          decoration: BoxDecoration(
            color:
                isEnabled
                    ? cs.primaryContainer.withValues(alpha: AppOpacity.medium)
                    : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.all(2),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color:
                    isEnabled
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(
                          alpha: AppOpacity.overlay,
                        ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Text(
            isEnabled
                ? AppLocalizations.premiumMemberAutoRenewalEnabled
                : AppLocalizations.premiumMemberAutoRenewalDisabled,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.titleSmall?.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    );

    if (onTap == null) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: content,
      ),
    );
  }
}

// ==================== ACCOUNT STATUS CARD ====================
//
// Replaces the old _UsageInsightsCard which showed fake placeholder data.
// This card shows REAL data from PremiumLicense:
// - Subscription progress (days remaining)
// - Last verification timestamp
// - Membership duration
// - License status

class _AccountStatusCard extends StatelessWidget {
  final PremiumLicense license;
  const _AccountStatusCard({required this.license});

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return AppLocalizations.premiumMemberJustNow;
  }

  String _formatMemberDuration(DateTime purchaseDate) {
    final diff = DateTime.now().difference(purchaseDate);
    if (diff.inDays >= 365) {
      final years = diff.inDays ~/ 365;
      final months = (diff.inDays % 365) ~/ 30;
      return months > 0
          ? AppLocalizations.premiumMemberDurationYearsMonths(years, months)
          : AppLocalizations.premiumMemberDurationYears(years);
    }
    if (diff.inDays >= 30) {
      return AppLocalizations.premiumMemberDurationMonths(diff.inDays ~/ 30);
    }
    if (diff.inDays > 0) {
      return AppLocalizations.premiumMemberDurationDays(diff.inDays);
    }
    return AppLocalizations.premiumMemberDurationLessThanDay;
  }

  int _cycleTotalDays(BillingCycle? cycle) => switch (cycle) {
    BillingCycle.p7 => 7,
    BillingCycle.p30 => 30,
    BillingCycle.p90 => 90,
    BillingCycle.monthly => 30,
    BillingCycle.semiannual => 182,
    BillingCycle.yearly => 365,
    _ => 0, // lifetime — no progress bar
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLifetime = license.billingCycle?.isLifetime ?? false;
    final daysLeft = license.daysRemaining;
    final totalDays = _cycleTotalDays(license.billingCycle);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _memberCardBg(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
        boxShadow: _memberShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.premiumMemberAccountStatus,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.shield_rounded, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Subscription progress
          if (isLifetime) ...[
            _StatusRow(
              icon: Icons.all_inclusive_rounded,
              label: AppLocalizations.premiumMemberLifetime,
              color: cs.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Full progress bar for lifetime
            Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primaryContainer, cs.primary],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ] else if (totalDays > 0 && daysLeft >= 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.premiumMemberSubscriptionHealth,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    AppLocalizations.premiumMemberDaysRemaining(daysLeft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: daysLeft <= 7 ? Colors.orange : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: FractionallySizedBox(
                widthFactor: (daysLeft / totalDays).clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primaryContainer,
                        daysLeft <= 7 ? Colors.orange : cs.primary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.mdLg),

          // Last verified
          _StatusRow(
            icon: Icons.verified_rounded,
            label:
                license.lastVerified != null
                    ? AppLocalizations.premiumMemberLastVerified(
                      _formatTimeAgo(license.lastVerified!),
                    )
                    : AppLocalizations.premiumMemberNeverVerified,
            color: license.lastVerified != null ? cs.primary : null,
          ),
          const SizedBox(height: AppSpacing.smMd),

          // Member since
          if (license.purchaseDate != null) ...[
            _StatusRow(
              icon: Icons.loyalty_rounded,
              label: AppLocalizations.premiumMemberFor(
                _formatMemberDuration(license.purchaseDate!),
              ),
            ),
            const SizedBox(height: AppSpacing.smMd),
          ],

          // License status
          _StatusRow(
            icon:
                license.isCancelled
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
            label:
                license.isCancelled
                    ? AppLocalizations.premiumCancelled
                    : AppLocalizations.premiumMemberLicenseActive,
            color: license.isCancelled ? Colors.orange : cs.primary,
          ),

          const SizedBox(height: AppSpacing.mdLg),

          // Quick stats boxes
          Row(
            children: [
              Expanded(
                child: _QuickStat(
                  value:
                      license.daysRemaining >= 0
                          ? '${license.daysRemaining}'
                          : '∞',
                  label: AppLocalizations.premiumMemberDaysLeft,
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: _QuickStat(
                  value:
                      license.billingCycle?.isLifetime ?? false
                          ? '∞'
                          : license.isAutoRenew
                          ? AppLocalizations.premiumAutoRenewOn
                          : AppLocalizations.premiumAutoRenewOff,
                  label: AppLocalizations.premiumAutoRenew,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _StatusRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final displayColor = color ?? cs.onSurfaceVariant;

    return Row(
      children: [
        Icon(icon, size: 16, color: displayColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: tt.titleSmall?.copyWith(color: displayColor),
          ),
        ),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String value;
  final String label;
  const _QuickStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: _memberCardBgAlt(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.compact.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== TRANSACTION HISTORY ====================

class _TransactionHistorySection extends ConsumerWidget {
  final PremiumLicense license;
  const _TransactionHistorySection({required this.license});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final txnAsync = ref.watch(transactionsProvider);

    // Server transactions, with local-only fallback
    final serverTxns = txnAsync.valueOrNull ?? [];
    final transactions = <_TransactionRow>[];
    if (serverTxns.isNotEmpty) {
      for (final txn in serverTxns) {
        transactions.add(
          _TransactionRow(
            date: txn.completedAt ?? txn.createdAt,
            description: txn.displayAmount,
            method: txn.paymentMethod,
            status:
                txn.status == 'completed'
                    ? AppLocalizations.premiumMemberTransactionCompleted
                    : txn.status,
          ),
        );
      }
    } else if (license.purchaseDate != null) {
      // Fallback: derive from local license data when backend is unavailable
      transactions.add(
        _TransactionRow(
          date: license.purchaseDate!,
          description: AppLocalizations.premiumMemberTransactionActivation,
          method: license.paymentMethod ?? 'stripe',
          status: AppLocalizations.premiumMemberTransactionCompleted,
        ),
      );
    }

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _memberCardBg(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.premiumMemberTransactionHistory,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                AppLocalizations.premiumMemberTransactionNoHistory,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.smMd,
              ),
              color: _memberCardBgAlt(context),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      AppLocalizations.premiumMemberTransactionDate
                          .toUpperCase(),
                      style: AppTypography.compact.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      AppLocalizations.premiumMemberTransactionDescription
                          .toUpperCase(),
                      style: AppTypography.compact.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      AppLocalizations.premiumMemberTransactionStatus
                          .toUpperCase(),
                      textAlign: TextAlign.end,
                      style: AppTypography.compact.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Transaction rows
            ...transactions.map(
              (tx) => _TransactionRowTile(transaction: tx, locale: locale),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _TransactionRow {
  final DateTime date;
  final String description;
  final String method;
  final String status;
  const _TransactionRow({
    required this.date,
    required this.description,
    required this.method,
    required this.status,
  });
}

class _TransactionRowTile extends StatelessWidget {
  final _TransactionRow transaction;
  final String locale;
  const _TransactionRowTile({required this.transaction, required this.locale});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isCompleted =
        transaction.status ==
        AppLocalizations.premiumMemberTransactionCompleted;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.smMd,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              DateFormat.yMMMd(locale).format(transaction.date),
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Icon(
                  transaction.method == 'crypto'
                      ? Icons.currency_bitcoin_rounded
                      : Icons.credit_card_rounded,
                  size: 14,
                  color: cs.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    transaction.description,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: (isCompleted ? AppColors.successGreen : cs.error)
                      .withValues(alpha: AppOpacity.pressed),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  transaction.status,
                  style: AppTypography.compact.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCompleted ? AppColors.successGreen : cs.error,
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

// ==================== DEVICE MANAGEMENT ====================

class _DeviceManagementCard extends ConsumerWidget {
  final PremiumLicense license;
  const _DeviceManagementCard({required this.license});

  /// Fallback max devices when server data is unavailable.
  int _fallbackMaxDevices(BillingCycle? cycle) => switch (cycle) {
    BillingCycle.lifetime1 => 1,
    BillingCycle.lifetime2 => 3,
    BillingCycle.lifetime3 => 10,
    _ => 3,
  };

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return AppLocalizations.premiumMemberJustNow;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final devicesAsync = ref.watch(devicesProvider);
    final licenseInfoAsync = ref.watch(licenseInfoProvider);
    // Watch early so it starts loading in parallel with devicesProvider,
    // avoiding a 1-frame race where currentDeviceId is null.
    final currentDeviceIdAsync = ref.watch(_currentDeviceIdProvider);

    // Server-authoritative counts, with local fallback
    final serverInfo = licenseInfoAsync.valueOrNull;
    final maxDevices =
        serverInfo?.maxDevices ?? _fallbackMaxDevices(license.billingCycle);
    final deviceCount =
        serverInfo?.deviceCount ?? devicesAsync.valueOrNull?.length ?? 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _memberCardBg(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _memberBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.premiumMemberDeviceManagement,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                AppLocalizations.premiumMemberDeviceSlots(
                  deviceCount,
                  maxDevices,
                ),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Device slot progress
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: FractionallySizedBox(
              widthFactor:
                  maxDevices > 0
                      ? (deviceCount / maxDevices).clamp(0.0, 1.0)
                      : 0.0,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Device list from API
          devicesAsync.when(
            loading: () => _buildLoadingState(cs, tt),
            error: (_, __) => _buildCurrentDeviceOnly(cs, tt),
            data: (devices) {
              if (devices.isEmpty) return _buildCurrentDeviceOnly(cs, tt);
              return _buildDeviceList(
                context,
                ref,
                devices,
                currentDeviceIdAsync.valueOrNull,
                cs,
                tt,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Text(
          AppLocalizations.premiumMemberDeviceLoading,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  /// Fallback: show only the current device (offline or PHP license).
  Widget _buildCurrentDeviceOnly(ColorScheme cs, TextTheme tt) {
    return _DeviceRow(
      icon: _currentDeviceIcon(),
      name: _currentDeviceName(),
      subtitle: AppLocalizations.premiumMemberDeviceThisDevice,
      isCurrentDevice: true,
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    WidgetRef ref,
    List<LicenseDevice> devices,
    String? currentDeviceId,
    ColorScheme cs,
    TextTheme tt,
  ) {
    return Column(
      children: [
        for (int i = 0; i < devices.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) {
              // Defensive: if we can't identify the current device and there's
              // only one device, it must be this device (the API found the license
              // via this device's auth). This prevents showing a remove button
              // on the user's only device.
              final isCurrent =
                  currentDeviceId != null
                      ? devices[i].deviceId == currentDeviceId
                      : devices.length == 1;

              return _DeviceRow(
                icon: _deviceIcon(devices[i].os),
                name: devices[i].displayName,
                subtitle:
                    devices[i].osLabel != 'Desktop'
                        ? '${devices[i].osLabel} · ${_formatDate(devices[i].lastVerifiedAt)}'
                        : AppLocalizations.premiumMemberDeviceLastSeen(
                          _formatDate(devices[i].lastVerifiedAt),
                        ),
                isCurrentDevice: isCurrent,
                onRemove:
                    !isCurrent
                        ? () => _confirmRemoveDevice(context, ref, devices[i])
                        : null,
              );
            },
          ),
        ],
      ],
    );
  }

  void _confirmRemoveDevice(
    BuildContext context,
    WidgetRef ref,
    LicenseDevice device,
  ) {
    final cs = Theme.of(context).colorScheme;
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.premiumMemberDeviceRemoveTitle),
            content: Text(AppLocalizations.premiumMemberDeviceRemoveMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: Text(AppLocalizations.premiumMemberDeviceRemoveConfirm),
              ),
            ],
          ),
    ).then((confirmed) {
      if (confirmed != true || !context.mounted) return;
      _removeDevice(context, ref, device.deviceId);
    });
  }

  Future<void> _removeDevice(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final service = ref.read(stripePaymentServiceProvider);
    try {
      await service.removeDevice(deviceId);
      ref.invalidate(devicesProvider);
      ref.invalidate(licenseInfoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.premiumMemberDeviceRemoveSuccess),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.premiumMemberDeviceRemoveError),
          ),
        );
      }
    }
  }

  static String _currentDeviceName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Desktop';
  }

  static IconData _currentDeviceIcon() {
    if (Platform.isMacOS) return Icons.laptop_mac_rounded;
    if (Platform.isWindows) return Icons.laptop_windows_rounded;
    if (Platform.isLinux) return Icons.computer_rounded;
    return Icons.devices_rounded;
  }

  /// OS-aware device icon from server metadata.
  static IconData _deviceIcon(String? os) {
    return switch (os?.toLowerCase()) {
      'macos' || 'darwin' => Icons.laptop_mac_rounded,
      'windows' => Icons.laptop_windows_rounded,
      'linux' => Icons.computer_rounded,
      _ => _currentDeviceIcon(), // Fallback to current platform
    };
  }
}

/// Read current device ID from secure storage (for comparing with device list).
final _currentDeviceIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final credentials = ref.watch(secureCredentialStoreProvider);
  return credentials.read(PrefKeys.deviceId);
});

/// Single device row in the device management card.
class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String subtitle;
  final bool isCurrentDevice;
  final VoidCallback? onRemove;

  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.isCurrentDevice,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: AppOpacity.scrim),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isCurrentDevice)
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withValues(
                      alpha: AppOpacity.pressed,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.successGreen,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(width: 6, height: 6),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          AppLocalizations.premiumMemberDeviceActive,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.compact.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.successGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              tooltip: AppLocalizations.premiumMemberDeviceRemoveTitle,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

// ==================== TIER SELECTOR ====================

class _TierSelectorSection extends ConsumerWidget {
  final PremiumLicense license;
  const _TierSelectorSection({required this.license});

  BillingCycle? get currentCycle => license.billingCycle;

  String _cycleLabel(BillingCycle cycle) => switch (cycle) {
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
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final usesPdfConvCatalog = BrandConfig.current.hasPdfConvPayPalCheckout;
    final AsyncValue<List<PricingPlan>> plansAsync =
        usesPdfConvCatalog
            ? const AsyncValue.data(<PricingPlan>[])
            : ref.watch(pricingPlansProvider);
    final cycles =
        (usesPdfConvCatalog
            ? null
            : plansAsync.whenOrNull(
              data:
                  (plans) =>
                      plans
                          .map((p) => BillingCycle.fromString(p.billingCycle))
                          .toList(),
            )) ??
        _brandDefaultCycles();

    PricingPlan? planFor(BillingCycle cycle) {
      return plansAsync.whenOrNull(
        data:
            (plans) => plans.cast<PricingPlan?>().firstWhere(
              (p) => p?.billingCycle == cycle.name,
              orElse: () => null,
            ),
      );
    }

    Widget buildCard(BillingCycle cycle) {
      final plan = planFor(cycle);
      return _TierCard(
        label: _cycleLabel(cycle),
        price: plan?.displayPrice ?? _fallbackPrice(cycle),
        suffix: _priceSuffix(cycle),
        isCurrent: cycle == currentCycle,
        isLifetime: cycle.isLifetime,
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(
                    alpha: AppOpacity.medium,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  AppLocalizations.premiumMemberAvailableTiers,
                  style: tt.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth < 560
                      ? 1
                      : cycles.length > 3 && constraints.maxWidth < 1040
                      ? 2
                      : cycles.length.clamp(1, 5);
              final gap = AppSpacing.smMd;
              final cardWidth =
                  columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - gap * (columns - 1)) / columns;
              final cardHeight = columns == 1 ? 124.0 : 132.0;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cycle in cycles)
                    SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: buildCard(cycle),
                    ),
                ],
              );
            },
          ),

          // Manage Subscription button (Stripe users only)
          const SizedBox(height: AppSpacing.lg),
          _ManageSubscriptionButton(license: license),
        ],
      ),
    );
  }

  /// Fallback prices when backend is unreachable.
  String _fallbackPrice(BillingCycle cycle) => switch (cycle) {
    BillingCycle.p7 => '\$10',
    BillingCycle.p30 => '\$15',
    BillingCycle.p90 => '\$25',
    BillingCycle.monthly => '\$7.99',
    BillingCycle.semiannual => '\$29.34',
    BillingCycle.yearly => '\$29.99',
    BillingCycle.lifetime =>
      BrandConfig.current.hasPdfConvPayPalCheckout ? '\$42' : '\$9.90',
    BillingCycle.lifetime1 => '\$49.99',
    BillingCycle.lifetime2 => '\$79.99',
    BillingCycle.lifetime3 => '\$99',
  };

  String _priceSuffix(BillingCycle cycle) => switch (cycle) {
    BillingCycle.monthly => AppLocalizations.premiumMemberPriceSuffixMonth,
    BillingCycle.yearly => AppLocalizations.premiumMemberPriceSuffixYear,
    _ => '',
  };
}

class _TierCard extends StatelessWidget {
  final String label;
  final String price;
  final String suffix;
  final bool isCurrent;
  final bool isLifetime;

  const _TierCard({
    required this.label,
    required this.price,
    required this.suffix,
    required this.isCurrent,
    required this.isLifetime,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color:
                  isCurrent
                      ? cs.surfaceContainerHighest.withValues(
                        alpha: AppOpacity.overlay,
                      )
                      : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    isCurrent
                        ? cs.primary.withValues(alpha: AppOpacity.medium)
                        : isLifetime
                        ? cs.primary.withValues(alpha: AppOpacity.divider)
                        : Colors.transparent,
              ),
              boxShadow:
                  isCurrent
                      ? [
                        BoxShadow(
                          color: AppColors.brand.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          blurRadius: 30,
                        ),
                      ]
                      : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTypography.statusBadge.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: tt.headlineSmall?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLifetime ? cs.primary : cs.onSurface,
                        ),
                      ),
                      if (suffix.isNotEmpty)
                        TextSpan(
                          text: suffix,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent)
            Positioned(
              top: -10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppLocalizations.premiumMemberCurrentPlanBadge,
                    style: AppTypography.mini.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                      letterSpacing: 0,
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

// ==================== MANAGE SUBSCRIPTION BUTTON ====================

class _ManageSubscriptionButton extends ConsumerStatefulWidget {
  final PremiumLicense license;
  const _ManageSubscriptionButton({required this.license});

  @override
  ConsumerState<_ManageSubscriptionButton> createState() =>
      _ManageSubscriptionButtonState();
}

class _ManageSubscriptionButtonState
    extends ConsumerState<_ManageSubscriptionButton>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _portalOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from Stripe portal, refresh license data automatically.
    if (state == AppLifecycleState.resumed && _portalOpened) {
      _portalOpened = false;
      ref.invalidate(licenseInfoProvider);
      ref.invalidate(devicesProvider);
    }
  }

  Future<void> _openPortal() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(stripePaymentServiceProvider);
      final opened = await service.openCustomerPortal();
      if (opened) {
        _portalOpened = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.premiumMemberPortalOpenError),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.premiumMemberPortalNotAvailable),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isStripe = widget.license.paymentMethod == 'stripe';
    final isPdfConvPayPal = widget.license.paymentMethod == 'paypal_pdfconv';
    final isLifetime = widget.license.billingCycle?.isLifetime ?? false;

    // Don't show for lifetime plans (nothing to manage)
    if (isLifetime || isPdfConvPayPal) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isStripe)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _openPortal,
              icon:
                  _isLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(AppLocalizations.premiumMemberManageSubscriptionBtn),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.smMd,
                  horizontal: AppSpacing.md,
                ),
                side: BorderSide(
                  color: cs.primary.withValues(alpha: AppOpacity.medium),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              AppLocalizations.premiumMemberPortalNotAvailable,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (isStripe)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              AppLocalizations.premiumMemberManageSubscriptionDesc,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// ==================== VERIFICATION FOOTER ====================

class _VerificationFooter extends StatelessWidget {
  final PremiumLicense license;
  const _VerificationFooter({required this.license});

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return AppLocalizations.premiumMemberJustNow;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLifetime = license.billingCycle?.isLifetime ?? false;

    // Real verification data
    final verifiedLabel =
        license.lastVerified != null
            ? AppLocalizations.premiumMemberLastVerified(
              _formatTimeAgo(license.lastVerified!),
            )
            : AppLocalizations.premiumMemberNeverVerified;

    final daysLabel =
        isLifetime
            ? AppLocalizations.premiumMemberLifetime
            : license.daysRemaining >= 0
            ? AppLocalizations.premiumMemberDaysRemaining(license.daysRemaining)
            : '—';

    final statusLabel =
        license.isCancelled
            ? AppLocalizations.premiumCancelled
            : AppLocalizations.premiumMemberLicenseActive;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: AppOpacity.nearOpaque),
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: AppOpacity.pressed),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth:
                    MediaQuery.sizeOf(context).width - (AppSpacing.lg * 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FooterItem(
                    icon: Icons.verified_rounded,
                    label: verifiedLabel,
                    iconColor: license.lastVerified != null ? cs.primary : null,
                  ),
                  const _FooterSeparator(),
                  _FooterItem(
                    icon:
                        isLifetime
                            ? Icons.all_inclusive_rounded
                            : Icons.schedule_rounded,
                    label: daysLabel,
                  ),
                  const _FooterSeparator(),
                  _FooterItem(
                    icon: Icons.laptop_mac_rounded,
                    label: statusLabel,
                    iconColor: license.isCancelled ? Colors.orange : cs.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _FooterItem({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? cs.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _FooterSeparator extends StatelessWidget {
  const _FooterSeparator();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: AppOpacity.medium),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
