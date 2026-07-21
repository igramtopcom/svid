import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/vidcombo/vidcombo_backend_adapter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_transitions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../domain/entities/pdfconv_paypal_plan.dart';
import '../../domain/entities/premium_feature.dart';
import '../../domain/entities/premium_license.dart';
import '../../domain/services/premium_license_service.dart';
import '../providers/license_verification_providers.dart';
import '../providers/pdfconv_paypal_providers.dart';
import '../providers/pdfconv_paypal_rollout_provider.dart';
import '../providers/payment_providers.dart';
import '../providers/premium_providers.dart';
import '../widgets/upgrade_prompt_dialog.dart';
import 'premium_members_screen.dart';
import 'premium_welcome_screen.dart';

// ==================== TOP-LEVEL HELPERS ====================

Color _premiumAccent(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.accentHighlight : colors.brand;
}

Color _premiumPageBg(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.darkBase : colors.lightBase;
}

Color _premiumCardBg(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.darkElevated : colors.lightElevated;
}

Color _premiumCardHover(bool isDark) {
  final colors = BrandConfig.current.colors;
  if (isDark) return colors.homeDarkCardHover;
  return Color.alphaBlend(
    colors.accentHighlight.withValues(alpha: 0.035),
    colors.lightElevated,
  );
}

Future<void> _activateLicenseForCurrentBackend(
  WidgetRef ref,
  String key,
) async {
  final notifier = ref.read(premiumLicenseProvider.notifier);
  if (BrandConfig.current.backendType == BackendType.go ||
      PremiumLicenseService.isGoBackendLicenseKey(key)) {
    await notifier.activateLicense(
      key,
      verificationService: ref.read(licenseVerificationServiceProvider),
    );
    return;
  }

  final adapter = VidComboBackendAdapter();
  final result = await adapter.checkKey(licenseKey: key);
  final verification = adapter.toLicenseVerification(result);
  if (!verification.isValid) {
    throw FormatException(verification.reason ?? 'License key is not active');
  }
  await notifier.activateLicenseFromBackend(
    result.licenseKey ?? key,
    billingCycle: verification.billingCycle,
    expiresAt: verification.expiresAt,
  );
}

Color _premiumSelected(bool isDark) {
  return Color.alphaBlend(
    _premiumAccent(isDark).withValues(alpha: isDark ? 0.18 : 0.08),
    _premiumCardBg(isDark),
  );
}

Color _premiumAccentSoft(bool isDark) {
  return Color.alphaBlend(
    _premiumAccent(isDark).withValues(alpha: isDark ? 0.16 : 0.07),
    _premiumCardBg(isDark),
  );
}

Color _premiumBorderSubtle(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.homeDarkBorderSubtle : colors.lightMuted;
}

Color _premiumBorderStrong(bool isDark) {
  final colors = BrandConfig.current.colors;
  if (isDark) return colors.homeDarkBorderStrong;
  return Color.alphaBlend(
    colors.brand.withValues(alpha: 0.42),
    colors.lightMuted,
  );
}

Color _premiumTextPrimary(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.darkLightText : const Color(0xFF15171A);
}

Color _premiumTextSecondary(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.darkMetaText : colors.lightMetaText;
}

Color _premiumTextMuted(bool isDark) {
  final colors = BrandConfig.current.colors;
  return isDark ? colors.homeDarkTextMuted : colors.lightMetaText;
}

double _premiumHorizontalPadding(double width) {
  if (width < 720) return AppSpacing.md;
  if (width < 1180) return AppSpacing.lg;
  return AppSpacing.xl;
}

List<BoxShadow> _premiumSurfaceShadow(bool isDark) {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.05),
      blurRadius: isDark ? 20 : 24,
      offset: const Offset(0, 12),
    ),
  ];
}

String _cycleLabel(BillingCycle cycle) {
  switch (cycle) {
    case BillingCycle.monthly:
      return AppLocalizations.premiumMonthly;
    case BillingCycle.semiannual:
      return AppLocalizations.premiumSemiannual;
    case BillingCycle.yearly:
      return AppLocalizations.premiumYearly;
    case BillingCycle.p7:
      return AppLocalizations.premiumMemberDurationDays(7);
    case BillingCycle.p30:
      return AppLocalizations.premiumMemberDurationDays(30);
    case BillingCycle.p90:
      return AppLocalizations.premiumMemberDurationDays(90);
    case BillingCycle.lifetime:
      return AppLocalizations.premiumLifetime;
    case BillingCycle.lifetime1:
      return AppLocalizations.premiumLifetime1;
    case BillingCycle.lifetime2:
      return AppLocalizations.premiumLifetime2;
    case BillingCycle.lifetime3:
      return AppLocalizations.premiumLifetime3;
  }
}

String _billingNote(BillingCycle cycle) {
  switch (cycle) {
    case BillingCycle.monthly:
      return AppLocalizations.premiumScreenPerMonth;
    case BillingCycle.semiannual:
      return AppLocalizations.premiumScreenPerSixMonths;
    case BillingCycle.yearly:
      return AppLocalizations.premiumScreenPerYear;
    case BillingCycle.p7:
      return AppLocalizations.premiumMemberDurationDays(7);
    case BillingCycle.p30:
      return AppLocalizations.premiumMemberDurationDays(30);
    case BillingCycle.p90:
      return AppLocalizations.premiumMemberDurationDays(90);
    case BillingCycle.lifetime:
    case BillingCycle.lifetime1:
    case BillingCycle.lifetime2:
    case BillingCycle.lifetime3:
      return AppLocalizations.premiumScreenOneTimePayment;
  }
}

/// Returns the default billing cycles for the current brand.
/// Used as fallback before the API response arrives.
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

BillingCycle _billingCycleForPdfConvPlan(PdfConvPlanId planId) =>
    switch (planId) {
      PdfConvPlanId.p7 => BillingCycle.p7,
      PdfConvPlanId.p30 => BillingCycle.p30,
      PdfConvPlanId.p90 => BillingCycle.p90,
      PdfConvPlanId.lifetime => BillingCycle.lifetime,
    };

PdfConvPlanId _pdfConvPlanForBillingCycle(BillingCycle cycle) =>
    switch (cycle) {
      BillingCycle.p7 => PdfConvPlanId.p7,
      BillingCycle.p30 => PdfConvPlanId.p30,
      BillingCycle.p90 => PdfConvPlanId.p90,
      BillingCycle.lifetime => PdfConvPlanId.lifetime,
      _ => throw ArgumentError.value(cycle, 'cycle', 'Not a PDFConv plan'),
    };

List<PricingPlan> _pdfConvPricingPlans() {
  return PdfConvPayPalPlan.plans
      .map(
        (plan) => PricingPlan(
          billingCycle: _billingCycleForPdfConvPlan(plan.id).name,
          amountCents: plan.amountMinor,
          currency: plan.currency,
          interval: plan.isLifetime ? 'lifetime' : 'fixed_days',
          maxDevices: 1,
          isLifetime: plan.isLifetime,
        ),
      )
      .toList(growable: false);
}

bool isRestoreLicenseNotFoundException(Exception exception) {
  if (exception is! AppException) return false;
  return exception.when(
    network:
        (_, __, data) => data?.toString().toUpperCase() == 'LICENSE_NOT_FOUND',
    download: (_, __, ___) => false,
    storage: (_, __, ___) => false,
    permission: (_, __) => false,
    validation: (_, __) => false,
    unknown: (_, __, ___) => false,
    rust: (_, __) => false,
  );
}

/// Secure-storage keys for the pending Stripe checkout session (crash +
/// in-session recovery). Shared between the checkout launcher and the payment
/// status overlay.
const _pendingSessionKey = 'pending_payment_session';
const _pendingSessionTimestampKey = 'pending_payment_session_ts';

// ==================== MAIN WIDGET ====================

/// Premium upgrade screen — "The Grand Invitation".
///
/// Nocturne Cinematic full-page pricing experience with atmospheric hero,
/// 5-column pricing grid, 3-column features grid, side-by-side payment cards.
/// Active premium users are redirected to the Members Lounge dashboard.
///
/// Design ref: Stitch `5ead0daf` — docs/design-specs/premium-grand-invitation.md
class PremiumUpgradeScreen extends ConsumerWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final license = ref.watch(premiumLicenseProvider);
    final isActive = license.isActiveSubscription;

    // Expired Stripe subscribers route to the Members Lounge too — the
    // dashboard already exposes "Manage Subscription" which deep-links
    // into the Stripe customer portal where the user can update their
    // payment method and reactivate the same subscription. Falling
    // through to the upgrade funnel would force a brand-new checkout
    // (Stripe creates a separate subscription rather than reactivating
    // the expired one), risking a double charge plus a UX dead-end for
    // users whose only real intent is to swap a declined card. Crypto
    // and lifetime-expired users fall through to the standard upgrade
    // funnel since they have no portal to manage.
    final isExpiredStripe =
        license.isPremium &&
        license.isExpired &&
        license.paymentMethod == 'stripe';

    // Active premium users → Members Lounge dashboard
    if (isActive || isExpiredStripe) {
      return const PremiumMembersScreen();
    }

    // Show targeted "Activation Failed — Retry" dialog when payment succeeded
    // but Keychain/storage write failed. This is distinct from payment errors.
    ref.listen<PaymentState>(paymentProvider, (previous, next) {
      if (next.activationError != null &&
          previous?.activationError != next.activationError) {
        _showActivationErrorDialog(context, ref, next);
      }
      // Activation success — show celebratory dialog
      if (next.isActivationSuccess && previous?.isActivationSuccess != true) {
        _showActivationSuccessDialog(context, ref);
      }
    });
    if (BrandConfig.current.hasPdfConvPayPalCheckout) {
      ref.listen<PdfConvPayPalState>(pdfConvPayPalProvider, (previous, next) {
        if (next.activationError != null &&
            previous?.activationError != next.activationError) {
          _showPdfConvActivationErrorDialog(context, ref);
        }
        if (next.isActivationSuccess && previous?.isActivationSuccess != true) {
          _showActivationSuccessDialog(context, ref);
        }
      });
    }

    return Scaffold(
      backgroundColor: _premiumPageBg(isDark),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: _premiumPageBg(isDark))),
          Column(
            children: [
              // Top bar
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: _premiumPageBg(isDark),
                  border: Border(
                    bottom: BorderSide(color: _premiumBorderSubtle(isDark)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 20,
                      color: _premiumAccent(isDark),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      AppLocalizations.premiumTitle,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _premiumTextPrimary(isDark),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const _HeroSection(),
                      _buildUpgradeFunnel(context, ref),
                      _buildTrustSignals(context),
                      const SizedBox(height: AppSpacing.xl),
                      _buildLicenseActivation(context, ref),

                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== NEW SECTION BUILDERS ====================

  /// Revenue funnel — plans and unlocked value inside one coherent surface.
  ///
  /// The old screen rendered pricing and features as separate islands. That made
  /// VidCombo's three-card pricing row feel detached from the feature cards
  /// below it. This surface keeps the purchase decision and value proof in one
  /// visual rhythm while staying brand-aware for Svid and VidCombo.
  Widget _buildUpgradeFunnel(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPdfConvPayPalCapability =
        BrandConfig.current.hasPdfConvPayPalCheckout;
    final usePdfConvPayPal =
        hasPdfConvPayPalCapability &&
        ref.watch(pdfConvPayPalCheckoutEnabledProvider);
    final useStripeCheckout =
        !hasPdfConvPayPalCapability && BrandConfig.current.hasStripeCheckout;
    final selectedCycle = ref.watch(selectedBillingCycleProvider);
    final AsyncValue<List<PricingPlan>> pricingAsync =
        usePdfConvPayPal
            ? AsyncValue.data(_pdfConvPricingPlans())
            : useStripeCheckout
            ? ref.watch(pricingPlansProvider)
            : const AsyncValue.data([]);
    final paymentState = ref.watch(paymentProvider);
    final pdfConvState = ref.watch(pdfConvPayPalProvider);

    // Derive available cycles from the API plans (falls back to brand-aware defaults)
    final resolvedCycles = pricingAsync.whenOrNull(
      data:
          (plans) =>
              plans
                  .map((p) => BillingCycle.fromString(p.billingCycle))
                  .toList(),
    );
    final availableCycles =
        resolvedCycles == null || resolvedCycles.isEmpty
            ? _brandDefaultCycles()
            : resolvedCycles;
    final effectiveSelectedCycle =
        availableCycles.contains(selectedCycle)
            ? selectedCycle
            : availableCycles.first;

    final featureColumns = [
      (
        AppLocalizations.premiumScreenCategoryDownloadPower,
        Icons.rocket_launch_rounded,
        [
          PremiumFeature.unlimitedDownloads,
          PremiumFeature.highQuality4K,
          PremiumFeature.extendedConcurrent,
          PremiumFeature.batchDownload,
        ],
      ),
      (
        AppLocalizations.premiumScreenCategoryAdvancedTools,
        Icons.tune_rounded,
        [
          PremiumFeature.advancedPlayer,
          PremiumFeature.browserShield,
          PremiumFeature.scheduledDownloads,
          PremiumFeature.bandwidthControl,
        ],
      ),
      (
        AppLocalizations.premiumScreenCategoryOrganizationInsights,
        Icons.insights_rounded,
        [
          PremiumFeature.smartCollections,
          PremiumFeature.advancedAnalytics,
          PremiumFeature.batchImport,
          PremiumFeature.prioritySupport,
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final horizontal = _premiumHorizontalPadding(pageConstraints.maxWidth);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.md,
            horizontal,
            AppSpacing.lg,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: _premiumCardBg(isDark),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: _premiumBorderSubtle(isDark)),
                  boxShadow: _premiumSurfaceShadow(isDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FunnelSectionHeader(
                      icon: Icons.workspace_premium_rounded,
                      title: AppLocalizations.premiumChoosePlan,
                      subtitle: AppLocalizations.premiumUpgradeSubtitle,
                    ),
                    if (usePdfConvPayPal || useStripeCheckout) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _PricingGrid(
                        cycles: availableCycles,
                        selectedCycle: effectiveSelectedCycle,
                        pricingAsync: pricingAsync,
                        checkoutInProgress:
                            usePdfConvPayPal
                                ? pdfConvState.isLoading
                                : paymentState.isLoading,
                        checkoutDisabled:
                            usePdfConvPayPal &&
                            pdfConvState.pendingCheckout != null,
                        checkoutLabel:
                            usePdfConvPayPal
                                ? AppLocalizations.premiumPaymentPayPalCheckout
                                : AppLocalizations.premiumUpgrade,
                        heroCycle:
                            usePdfConvPayPal ? null : BillingCycle.yearly,
                        onSelect:
                            (cycle) =>
                                ref
                                    .read(selectedBillingCycleProvider.notifier)
                                    .state = cycle,
                        onCheckout:
                            (cycle) =>
                                usePdfConvPayPal
                                    ? _startPdfConvCheckout(context, ref, cycle)
                                    : _startCheckout(context, ref, cycle),
                      ),
                    ],
                    if (hasPdfConvPayPalCapability)
                      _buildInlinePdfConvFeedback(context, ref, pdfConvState)
                    else if (useStripeCheckout)
                      _buildInlinePaymentFeedback(context, paymentState),
                    const SizedBox(height: AppSpacing.lg),
                    Divider(height: 1, color: _premiumBorderSubtle(isDark)),
                    const SizedBox(height: AppSpacing.lg),
                    _FunnelSectionHeader(
                      icon: Icons.auto_awesome_rounded,
                      title: AppLocalizations.premiumFeatures,
                      subtitle: AppLocalizations.premiumUpgradeSubtitle,
                      compact: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 760) {
                          return Column(
                            children: [
                              for (
                                int i = 0;
                                i < featureColumns.length;
                                i++
                              ) ...[
                                if (i > 0)
                                  const SizedBox(height: AppSpacing.smMd),
                                _FeatureColumn(
                                  title: featureColumns[i].$1,
                                  icon: featureColumns[i].$2,
                                  features: featureColumns[i].$3,
                                ),
                              ],
                            ],
                          );
                        }

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                int i = 0;
                                i < featureColumns.length;
                                i++
                              ) ...[
                                if (i > 0)
                                  const SizedBox(width: AppSpacing.smMd),
                                Expanded(
                                  child: _FeatureColumn(
                                    title: featureColumns[i].$1,
                                    icon: featureColumns[i].$2,
                                    features: featureColumns[i].$3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlinePaymentFeedback(
    BuildContext context,
    PaymentState paymentState,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final feedback = <Widget>[];

    if (paymentState.isLoading) {
      feedback.add(_buildPaymentStatus(context, paymentState));
    }

    if (paymentState.error != null) {
      feedback.add(
        Container(
          padding: const EdgeInsets.all(AppSpacing.smMd),
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: AppOpacity.hover),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: cs.error.withValues(alpha: AppOpacity.quarter),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: cs.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  paymentState.error ?? '',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (paymentState.isSuccess) {
      feedback.add(
        Container(
          padding: const EdgeInsets.all(AppSpacing.smMd),
          decoration: BoxDecoration(
            color: AppColors.success(
              context,
            ).withValues(alpha: AppOpacity.hover),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.success(
                context,
              ).withValues(alpha: AppOpacity.quarter),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: AppColors.success(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.premiumPaymentSuccess,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.success(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (feedback.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < feedback.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            feedback[i],
          ],
        ],
      ),
    );
  }

  Widget _buildInlinePdfConvFeedback(
    BuildContext context,
    WidgetRef ref,
    PdfConvPayPalState paymentState,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final messages = <Widget>[];

    if (paymentState.isLoading || paymentState.isWaiting) {
      messages.add(
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _premiumAccent(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                paymentState.phase == PdfConvCheckoutPhase.manualReview
                    ? AppLocalizations.premiumPaymentDoNotPayAgain
                    : AppLocalizations.premiumPaymentWaiting,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final error = paymentState.activationError ?? paymentState.error;
    if (error != null) {
      messages.add(
        Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                error,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          ],
        ),
      );
    }

    final hasPendingCheckout = paymentState.pendingCheckout != null;
    if (messages.isEmpty && !hasPendingCheckout) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: _premiumAccentSoft(
          Theme.of(context).brightness == Brightness.dark,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: _premiumBorderSubtle(
            Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            messages[i],
          ],
          if (hasPendingCheckout) ...[
            if (messages.isNotEmpty) const SizedBox(height: AppSpacing.smMd),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const Key('pdfconv_reopen_pending_payment'),
                  onPressed:
                      paymentState.isLoading
                          ? null
                          : () =>
                              ref
                                  .read(pdfConvPayPalProvider.notifier)
                                  .reopenApprovalPage(),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(AppLocalizations.premiumReopenPaymentPage),
                ),
                FilledButton.icon(
                  key: const Key('pdfconv_recheck_pending_payment'),
                  onPressed:
                      paymentState.isLoading
                          ? null
                          : () =>
                              ref
                                  .read(pdfConvPayPalProvider.notifier)
                                  .refreshPendingCheckout(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(AppLocalizations.premiumPaymentIAlreadyPaid),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 4-column trust signals row.
  Widget _buildTrustSignals(BuildContext context) {
    final signals = [
      (
        Icons.verified_user_rounded,
        AppLocalizations.premiumTrustSecure,
        AppLocalizations.premiumTrustSecureDesc,
      ),
      (
        Icons.lock_rounded,
        AppLocalizations.premiumTrustPrivate,
        AppLocalizations.premiumTrustPrivateDesc,
      ),
      (
        Icons.support_agent_rounded,
        AppLocalizations.premiumTrustSupport,
        AppLocalizations.premiumTrustSupportDesc,
      ),
      (
        Icons.cloud_done_rounded,
        AppLocalizations.premiumTrustReliable,
        AppLocalizations.premiumTrustReliableDesc,
      ),
    ];

    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final horizontal = _premiumHorizontalPadding(pageConstraints.maxWidth);
        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: AppSpacing.xl,
            horizontal: horizontal,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth < 560
                          ? 1
                          : constraints.maxWidth < 900
                          ? 2
                          : 4;
                  final gap = AppSpacing.md;
                  final itemWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;

                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final signal in signals)
                        SizedBox(
                          width: itemWidth,
                          child: _TrustSignalItem(
                            icon: signal.$1,
                            label: signal.$2,
                            description: signal.$3,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// License activation section with direct key entry + restore action.
  Widget _buildLicenseActivation(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final horizontal = _premiumHorizontalPadding(pageConstraints.maxWidth);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _LicenseActivationPanel(
                onActivationSuccess:
                    () => _showActivationSuccessDialog(context, ref),
                onRestoreLicense: () => _showRestoreLicenseDialog(context, ref),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== CHECKOUT FLOW ====================

  Future<void> _startPdfConvCheckout(
    BuildContext context,
    WidgetRef ref,
    BillingCycle billingCycle,
  ) async {
    final email = await _requestPayPalEmail(context);
    if (email == null || !context.mounted) return;

    var overlayDismissedByCancel = false;
    _showPdfConvStatusOverlay(
      context,
      ref,
      onCancel: () {
        overlayDismissedByCancel = true;
      },
    );

    await ref
        .read(pdfConvPayPalProvider.notifier)
        .startCheckout(
          planId: _pdfConvPlanForBillingCycle(billingCycle),
          buyerEmail: email,
        );

    final paymentState = ref.read(pdfConvPayPalProvider);
    if (context.mounted &&
        !overlayDismissedByCancel &&
        !paymentState.isLoading &&
        !paymentState.isWaiting) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<String?> _requestPayPalEmail(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        String? errorText;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              backgroundColor: _premiumCardBg(isDark),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                side: BorderSide(color: _premiumBorderStrong(isDark)),
              ),
              title: _PremiumDialogTitle(
                icon: Icons.account_balance_wallet_outlined,
                title: AppLocalizations.premiumPaymentPayPalCheckout,
                accent: _premiumAccent(isDark),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.premiumPaymentPayPalEmailDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _premiumTextSecondary(isDark),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.smMd),
                    TextField(
                      key: const Key('pdfconv_paypal_email'),
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      maxLines: 1,
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.premiumPaymentPayPalEmailLabel,
                        hintText: 'email@example.com',
                        errorText: errorText,
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      ),
                      onSubmitted: (_) {
                        final email = controller.text.trim();
                        if (!Validators.isValidEmail(email)) {
                          setState(
                            () =>
                                errorText =
                                    AppLocalizations.premiumInvalidEmail,
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(email.toLowerCase());
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                FilledButton.icon(
                  key: const Key('pdfconv_paypal_continue'),
                  onPressed: () {
                    final email = controller.text.trim();
                    if (!Validators.isValidEmail(email)) {
                      setState(
                        () => errorText = AppLocalizations.premiumInvalidEmail,
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(email.toLowerCase());
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(AppLocalizations.premiumPaymentPayPalCheckout),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showPdfConvStatusOverlay(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onCancel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.64 : 0.42),
      builder: (_) => PdfConvPaymentStatusOverlay(onCancel: onCancel),
    );
  }

  /// Start Stripe checkout in system browser (unified for all brands).
  ///
  /// 1. Creates checkout session via backend
  /// 2. Persists session ID (crash recovery)
  /// 3. Opens system browser with Stripe hosted page
  /// 4. Shows payment status overlay while polling
  /// 5. On success: verifies + activates license
  ///
  /// Option B re-check safety net (no deep link): in-app polling, the in-session
  /// "I already paid" re-check via checkPendingSession, and startup recovery.
  Future<void> _startCheckout(
    BuildContext context,
    WidgetRef ref,
    BillingCycle billingCycle,
  ) async {
    final notifier = ref.read(paymentProvider.notifier);
    final credentials = ref.read(secureCredentialStoreProvider);

    var overlayDismissedByCancel = false;

    if (context.mounted) {
      _showPaymentStatusOverlay(
        context,
        ref,
        onCancel: () {
          overlayDismissedByCancel = true;
        },
      );
    }

    await notifier.startStripeCheckout(
      billingCycle,
      onPersistSession: (sessionId) async {
        await credentials.write(_pendingSessionKey, sessionId);
        await credentials.write(
          _pendingSessionTimestampKey,
          DateTime.now().toIso8601String(),
        );
      },
      onClearSession: () async {
        await credentials.delete(_pendingSessionKey);
        await credentials.delete(_pendingSessionTimestampKey);
      },
    );

    final paymentState = ref.read(paymentProvider);
    final shouldKeepOverlayOpen =
        paymentState.isLoading ||
        paymentState.isPending ||
        paymentState.isAwaitingLicense;
    if (context.mounted &&
        !overlayDismissedByCancel &&
        !shouldKeepOverlayOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Overlay shown while waiting for payment confirmation in system browser.
  ///
  /// Shows progress indicator + helpful actions:
  /// - "Reopen Payment Page" — if user accidentally closed browser
  /// - "I Already Paid" — triggers immediate verification
  /// - "Cancel" — aborts the checkout flow
  void _showPaymentStatusOverlay(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onCancel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.64 : 0.42),
      builder: (ctx) => PaymentStatusOverlay(onCancel: onCancel),
    );
  }

  // ==================== PRESERVED METHODS ====================

  Widget _buildPaymentStatus(BuildContext context, PaymentState state) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    String message;
    if (state.session != null && state.result == null) {
      // Creating session or waiting for in-app checkout
      message = AppLocalizations.premiumPaymentProcessing;
    } else if (state.session != null && state.result != null) {
      // Verifying payment after checkout completed
      message = AppLocalizations.premiumPaymentVerifying;
    } else if (state.invoice != null) {
      message = AppLocalizations.premiumCryptoWaitingConfirmation;
    } else {
      message = AppLocalizations.premiumPaymentProcessing;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: AppOpacity.divider),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: cs.primary.withValues(alpha: AppOpacity.subtle),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Text(
              message,
              style: tt.bodySmall?.copyWith(color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog: paste license key to activate manually.
  void _showActivateKeyDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final accent = _premiumAccent(isDark);
        String? errorText;
        bool isLoading = false;

        return StatefulBuilder(
          builder:
              (ctx, setState) => AlertDialog(
                scrollable: true,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                backgroundColor: _premiumCardBg(isDark),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.dialog),
                  side: BorderSide(color: _premiumBorderStrong(isDark)),
                ),
                actionsOverflowAlignment: OverflowBarAlignment.end,
                actionsOverflowDirection: VerticalDirection.down,
                title: _PremiumDialogTitle(
                  icon: Icons.key_rounded,
                  title: AppLocalizations.premiumActivateKey,
                  accent: accent,
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.premiumActivateKeyDesc,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.secondary,
                          ),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.smMd),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _premiumPageBg(isDark),
                          hintText: BrandConfig.current.licenseKeyHint,
                          hintStyle: AppTypography.metadata.copyWith(
                            color: cs.onSurface.withValues(
                              alpha: AppOpacity.scrim,
                            ),
                          ),
                          errorText: errorText,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                            borderSide: BorderSide(
                              color: _premiumBorderSubtle(isDark),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                            borderSide: BorderSide(color: accent, width: 1.4),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.smMd,
                            vertical: AppSpacing.smMd,
                          ),
                        ),
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        autofocus: true,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      MaterialLocalizations.of(ctx).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    onPressed:
                        isLoading
                            ? null
                            : () async {
                              final key = controller.text.trim();
                              if (!PremiumLicenseService.isValidLicenseKey(
                                key,
                              )) {
                                setState(
                                  () =>
                                      errorText =
                                          AppLocalizations.premiumInvalidKeyFormat(
                                            BrandConfig
                                                .current
                                                .licenseKeyFormatExample,
                                          ),
                                );
                                return;
                              }
                              setState(() {
                                isLoading = true;
                                errorText = null;
                              });
                              try {
                                await _activateLicenseForCurrentBackend(
                                  ref,
                                  key,
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                if (context.mounted) {
                                  _showActivationSuccessDialog(context, ref);
                                }
                              } catch (e) {
                                setState(() {
                                  isLoading = false;
                                  errorText = e.toString();
                                });
                              }
                            },
                    child:
                        isLoading
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(AppLocalizations.premiumActivate),
                  ),
                ],
              ),
        );
      },
    );
  }

  /// Dialog: restore license by email used during purchase.
  void _showRestoreLicenseDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final accent = _premiumAccent(isDark);
        String? errorText;
        bool isLoading = false;
        bool emailSent = false;
        String? sentToEmail;

        return StatefulBuilder(
          builder:
              (ctx, setState) => AlertDialog(
                scrollable: true,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                backgroundColor: _premiumCardBg(isDark),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.dialog),
                  side: BorderSide(color: _premiumBorderStrong(isDark)),
                ),
                actionsOverflowAlignment: OverflowBarAlignment.end,
                actionsOverflowDirection: VerticalDirection.down,
                title: _PremiumDialogTitle(
                  icon: Icons.restore_rounded,
                  title: AppLocalizations.premiumRestoreLicense,
                  accent: accent,
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Magic-link flow (W1.2/W1.3): the server no longer
                        // returns the secret over an API key + email. Explain
                        // the new flow.
                        emailSent
                            ? 'We sent a one-time sign-in link to ${sentToEmail ?? "your email"}. '
                                'Open the email, click the link, copy the license key shown on the website, '
                                'then come back and use "Activate License Key" to enter it.'
                            : 'Enter your purchase email. We will send a single-use sign-in link to that '
                                'address. Open the link to view your license key on the website, then paste '
                                'it into the "Activate License Key" dialog here.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.secondary,
                          ),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.smMd),
                      if (!emailSent)
                        TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _premiumPageBg(isDark),
                            hintText: 'email@example.com',
                            errorText: errorText,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                              borderSide: BorderSide(
                                color: _premiumBorderSubtle(isDark),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                              borderSide: BorderSide(color: accent, width: 1.4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.smMd,
                              vertical: AppSpacing.smMd,
                            ),
                            prefixIcon: const Icon(
                              Icons.email_outlined,
                              size: 20,
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          maxLines: 1,
                          autofocus: true,
                        ),
                      if (emailSent) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.smMd),
                          decoration: BoxDecoration(
                            color: AppColors.success(
                              ctx,
                            ).withValues(alpha: AppOpacity.hover),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(
                              color: AppColors.success(
                                ctx,
                              ).withValues(alpha: AppOpacity.quarter),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.mark_email_read_outlined,
                                size: 16,
                                color: AppColors.success(ctx),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Email sent. The link expires in 10 minutes.',
                                  style: Theme.of(ctx).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.success(ctx)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      MaterialLocalizations.of(ctx).closeButtonTooltip,
                    ),
                  ),
                  if (emailSent)
                    // Shortcut into the existing "Activate License Key" dialog
                    // so the user doesn't have to hunt for it after copying
                    // from email.
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showActivateKeyDialog(context, ref);
                      },
                      child: Text(AppLocalizations.premiumIHaveMyKey),
                    )
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      onPressed:
                          isLoading
                              ? null
                              : () async {
                                final email = controller.text.trim();
                                if (email.isEmpty || !email.contains('@')) {
                                  setState(
                                    () =>
                                        errorText =
                                            AppLocalizations
                                                .premiumInvalidEmail,
                                  );
                                  return;
                                }
                                setState(() {
                                  isLoading = true;
                                  errorText = null;
                                });
                                try {
                                  final backendService = ref.read(
                                    backendServiceProvider,
                                  );
                                  final result = await backendService
                                      .requestRestoreEmail(email: email);
                                  result.when(
                                    success: (_) {
                                      // Server returns {sent: true} regardless
                                      // of whether the email matched a license
                                      // — that's the enumeration-resistance
                                      // invariant. UI always shows the same
                                      // success state.
                                      if (!ctx.mounted) return;
                                      setState(() {
                                        isLoading = false;
                                        emailSent = true;
                                        sentToEmail = email;
                                      });
                                    },
                                    failure: (e) {
                                      if (!ctx.mounted) return;
                                      setState(() {
                                        isLoading = false;
                                        errorText = e.toString();
                                      });
                                    },
                                  );
                                } catch (e) {
                                  setState(() {
                                    isLoading = false;
                                    errorText = e.toString();
                                  });
                                }
                              },
                      child:
                          isLoading
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(AppLocalizations.premiumSendLink),
                    ),
                ],
              ),
        );
      },
    );
  }

  /// Navigate to the celebratory Welcome Home screen.
  void _showActivationSuccessDialog(BuildContext context, WidgetRef ref) {
    Navigator.of(
      context,
    ).push(AppTransitions.pageRoute(const PremiumWelcomeScreen()));
  }

  /// Show a targeted "Activation Failed — Retry" dialog.
  ///
  /// Shown when payment succeeded but Keychain/storage write failed. Gives the
  /// user up to [PaymentNotifier.maxActivationRetries] retry attempts before
  /// suggesting they contact support with their transaction ID.
  void _showActivationErrorDialog(
    BuildContext context,
    WidgetRef ref,
    PaymentState paymentState,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isMaxRetries =
        paymentState.activationRetryCount >=
        PaymentNotifier.maxActivationRetries;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            backgroundColor: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            actionsOverflowAlignment: OverflowBarAlignment.end,
            actionsOverflowDirection: VerticalDirection.down,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: AppOpacity.pressed),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Text(
                    AppLocalizations.premiumPaymentActivationFailed,
                    style: AppTypography.appBarTitle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMaxRetries
                        ? AppLocalizations.premiumPaymentActivationMaxRetries
                        : AppLocalizations
                            .premiumPaymentActivationFailedMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (paymentState.activationRetryCount > 0) ...[
                    const SizedBox(height: AppSpacing.smMd),
                    Text(
                      AppLocalizations.premiumPaymentActivationAttempt(
                        paymentState.activationRetryCount,
                        PaymentNotifier.maxActivationRetries,
                      ),
                      style: AppTypography.sectionHeader.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.premiumPaymentContactSupport),
              ),
              if (!isMaxRetries)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref.read(paymentProvider.notifier).retryActivation();
                  },
                  child: Text(AppLocalizations.premiumPaymentRetryActivation),
                ),
            ],
          ),
    );
  }

  void _showPdfConvActivationErrorDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(AppLocalizations.premiumPaymentActivationFailed),
            content: Text(
              AppLocalizations.premiumPaymentActivationFailedMessage,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(AppLocalizations.premiumPaymentContactSupport),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  ref
                      .read(pdfConvPayPalProvider.notifier)
                      .refreshPendingCheckout();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(AppLocalizations.premiumPaymentRetryActivation),
              ),
            ],
          ),
    );
  }
}

// ==================== PAYMENT STATUS OVERLAY ====================

class PdfConvPaymentStatusOverlay extends ConsumerWidget {
  final VoidCallback? onCancel;

  const PdfConvPaymentStatusOverlay({super.key, this.onCancel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfConvPayPalProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _premiumAccent(isDark);

    ref.listen<PdfConvPayPalState>(pdfConvPayPalProvider, (previous, next) {
      if (next.phase == PdfConvCheckoutPhase.completed ||
          next.phase == PdfConvCheckoutPhase.terminal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: _premiumCardBg(isDark),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: _premiumBorderStrong(isDark)),
        ),
        title: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
            ),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Text(
                state.phase == PdfConvCheckoutPhase.manualReview
                    ? AppLocalizations.premiumPaymentStillProcessingTitle
                    : AppLocalizations.premiumPaymentVerifying,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.premiumPaymentDoNotPayAgain,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _premiumTextSecondary(isDark),
                  height: 1.45,
                ),
              ),
              if (state.error != null || state.activationError != null) ...[
                const SizedBox(height: AppSpacing.smMd),
                Text(
                  state.activationError ?? state.error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(pdfConvPayPalProvider.notifier).cancelPolling();
              Navigator.of(context).pop();
              onCancel?.call();
            },
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          OutlinedButton.icon(
            onPressed:
                state.isLoading
                    ? null
                    : () =>
                        ref
                            .read(pdfConvPayPalProvider.notifier)
                            .reopenApprovalPage(),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(AppLocalizations.premiumReopenPaymentPage),
          ),
          FilledButton.icon(
            key: const Key('pdfconv_payment_already_paid'),
            onPressed:
                state.isLoading
                    ? null
                    : () =>
                        ref
                            .read(pdfConvPayPalProvider.notifier)
                            .refreshPendingCheckout(),
            icon: const Icon(Icons.verified_rounded, size: 16),
            label: Text(AppLocalizations.premiumPaymentIAlreadyPaid),
          ),
        ],
      ),
    );
  }
}

/// Blocking overlay shown while waiting for Stripe payment confirmation.
///
/// Public so the PAY-3 blocker behavior is widget-testable. While the payment
/// is loading/pending/awaiting-license the overlay stays open (canPop: false);
/// the "I already paid" button drives an in-session re-check via
/// [PaymentNotifier.checkPendingSession], and the overlay auto-dismisses once
/// the payment reaches an activatable / failed / cancelled terminal state.
class PaymentStatusOverlay extends ConsumerWidget {
  final VoidCallback? onCancel;

  const PaymentStatusOverlay({super.key, this.onCancel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _premiumAccent(isDark);

    final paymentState = ref.watch(paymentProvider);
    final isWaitingAfterPoll =
        !paymentState.isLoading &&
        (paymentState.isPending || paymentState.isAwaitingLicense);
    final title =
        isWaitingAfterPoll
            ? AppLocalizations.premiumPaymentStillProcessingTitle
            : AppLocalizations.premiumPaymentVerifying;
    final body =
        isWaitingAfterPoll
            ? AppLocalizations.premiumPaymentDoNotPayAgain
            : AppLocalizations.premiumPaymentProcessing;

    Future<void> checkPendingSession() async {
      final credentials = ref.read(secureCredentialStoreProvider);
      final sessionId =
          await credentials.read(_pendingSessionKey) ??
          ref.read(paymentProvider).session?.sessionId;
      if (sessionId == null || sessionId.isEmpty) return;
      await ref
          .read(paymentProvider.notifier)
          .checkPendingSession(
            sessionId,
            onClearSession: () async {
              await credentials.delete(_pendingSessionKey);
              await credentials.delete(_pendingSessionTimestampKey);
            },
          );
      final updated = ref.read(paymentProvider);
      if (!context.mounted) return;
      if (!updated.isLoading &&
          !updated.isPending &&
          !updated.isAwaitingLicense) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: _premiumCardBg(isDark),
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                border: Border.all(color: _premiumBorderStrong(isDark)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated progress
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: accent,
                            backgroundColor: _premiumBorderSubtle(isDark),
                          ),
                        ),
                        Icon(
                          Icons.open_in_browser_rounded,
                          size: 24,
                          color: accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    style: AppTypography.appBarTitle.copyWith(
                      color: _premiumTextPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    body,
                    style: tt.bodyMedium?.copyWith(
                      color: _premiumTextSecondary(isDark),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('payment_overlay_already_paid'),
                      onPressed:
                          paymentState.isLoading ? null : checkPendingSession,
                      icon: const Icon(Icons.verified_rounded, size: 16),
                      label: Text(AppLocalizations.premiumPaymentIAlreadyPaid),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ref.read(paymentProvider.notifier).reopenCheckoutPage();
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(AppLocalizations.premiumReopenPaymentPage),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.55)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        ref.read(paymentProvider.notifier).reset();
                        Navigator.of(context, rootNavigator: true).pop();
                        onCancel?.call();
                      },
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                        style: tt.bodyMedium?.copyWith(
                          color: _premiumTextSecondary(isDark),
                        ),
                      ),
                    ),
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

// ==================== PRIVATE WIDGETS ====================

class _PremiumDialogTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;

  const _PremiumDialogTitle({
    required this.icon,
    required this.title,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _premiumTextPrimary(isDark),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _LicenseActivationPanel extends ConsumerStatefulWidget {
  final VoidCallback onActivationSuccess;
  final VoidCallback onRestoreLicense;

  const _LicenseActivationPanel({
    required this.onActivationSuccess,
    required this.onRestoreLicense,
  });

  @override
  ConsumerState<_LicenseActivationPanel> createState() =>
      _LicenseActivationPanelState();
}

class _LicenseActivationPanelState
    extends ConsumerState<_LicenseActivationPanel> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final key = _controller.text.trim();
    if (!PremiumLicenseService.isValidLicenseKey(key)) {
      setState(
        () =>
            _errorText = AppLocalizations.premiumInvalidKeyFormat(
              BrandConfig.current.licenseKeyFormatExample,
            ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await _activateLicenseForCurrentBackend(ref, key);
      if (!mounted) return;
      widget.onActivationSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _premiumAccent(isDark);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _premiumCardBg(isDark),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _premiumBorderSubtle(isDark)),
        boxShadow: _premiumSurfaceShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _premiumAccentSoft(isDark),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: _premiumBorderSubtle(isDark)),
                ),
                child: Icon(Icons.key_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.premiumHaveLicenseKey,
                      style: tt.titleMedium?.copyWith(
                        color: _premiumTextPrimary(isDark),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AppLocalizations.premiumHaveLicenseKeyDesc,
                      style: tt.bodySmall?.copyWith(
                        color: _premiumTextSecondary(isDark),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 700;
              final field = _buildKeyField(context, isDark, accent);
              final activate = _buildActivateButton(context, accent);

              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    const SizedBox(height: AppSpacing.sm),
                    activate,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: AppSpacing.smMd),
                  SizedBox(width: 170, child: activate),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.smMd),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                AppLocalizations.premiumActivateKeyDesc,
                style: tt.bodySmall?.copyWith(
                  color: _premiumTextMuted(isDark),
                  height: 1.35,
                ),
              ),
              TextButton.icon(
                onPressed: widget.onRestoreLicense,
                icon: const Icon(Icons.restore_rounded, size: 17),
                label: Text(AppLocalizations.premiumRestoreLicense),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyField(BuildContext context, bool isDark, Color accent) {
    return TextField(
      controller: _controller,
      enabled: !_isLoading,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _isLoading ? null : _activate(),
      onChanged: (_) {
        if (_errorText != null) setState(() => _errorText = null);
      },
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        color: _premiumTextPrimary(isDark),
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: _premiumPageBg(isDark),
        prefixIcon: Icon(
          Icons.vpn_key_outlined,
          color: _premiumTextMuted(isDark),
        ),
        suffixIcon:
            _controller.text.isEmpty || _isLoading
                ? null
                : IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                  onPressed:
                      () => setState(() {
                        _controller.clear();
                        _errorText = null;
                      }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        hintText: BrandConfig.current.licenseKeyHint,
        errorText: _errorText,
        helperText: BrandConfig.current.licenseKeyFormatExample,
        helperMaxLines: 1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: _premiumBorderSubtle(isDark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.md,
        ),
      ),
    );
  }

  Widget _buildActivateButton(BuildContext context, Color accent) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : _activate,
        icon:
            _isLoading
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.lock_open_rounded, size: 18),
        label: Text(
          AppLocalizations.premiumActivateKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _premiumCardHover(
            Theme.of(context).brightness == Brightness.dark,
          ),
          disabledForegroundColor: _premiumTextSecondary(
            Theme.of(context).brightness == Brightness.dark,
          ),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
    );
  }
}

class _FunnelSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  const _FunnelSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 34 : 40,
          height: compact ? 34 : 40,
          decoration: BoxDecoration(
            color: _premiumAccentSoft(isDark),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: _premiumBorderSubtle(isDark)),
          ),
          child: Icon(
            icon,
            size: compact ? 18 : 20,
            color: _premiumAccent(isDark),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (compact ? tt.titleMedium : tt.titleLarge)?.copyWith(
                  color: _premiumTextPrimary(isDark),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  color: _premiumTextSecondary(isDark),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact product header for the Premium flow.
class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = _premiumHorizontalPadding(constraints.maxWidth);
        final compact = constraints.maxWidth < 820;

        final title = Text(
          '${BrandConfig.current.appName} Premium',
          style: tt.headlineMedium?.copyWith(
            color: _premiumTextPrimary(isDark),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.1,
          ),
        );

        final subtitle = Text(
          AppLocalizations.premiumUpgradeSubtitle,
          style: tt.bodyMedium?.copyWith(
            color: _premiumTextSecondary(isDark),
            height: 1.45,
          ),
        );

        final badge = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _premiumAccentSoft(isDark),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: _premiumBorderStrong(isDark)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: _premiumAccent(isDark),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.premiumScreenHeroSubtitle,
                style: tt.labelMedium?.copyWith(
                  color: _premiumAccent(isDark),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        );

        final trustChips = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _HeroChip(
              icon: Icons.all_inclusive_rounded,
              label: AppLocalizations.premiumFeatureUnlimitedDownloads,
            ),
            _HeroChip(
              icon: Icons.hd_rounded,
              label: AppLocalizations.premiumFeatureHighQuality4K,
            ),
            _HeroChip(
              icon: Icons.verified_user_rounded,
              label: AppLocalizations.premiumTrustSecure,
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.lg,
            horizontal,
            AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child:
                  compact
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          badge,
                          const SizedBox(height: AppSpacing.smMd),
                          title,
                          const SizedBox(height: AppSpacing.sm),
                          subtitle,
                          const SizedBox(height: AppSpacing.md),
                          trustChips,
                        ],
                      )
                      : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                badge,
                                const SizedBox(height: AppSpacing.smMd),
                                title,
                                const SizedBox(height: AppSpacing.sm),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 620,
                                  ),
                                  child: subtitle,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Flexible(child: trustChips),
                        ],
                      ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _premiumCardBg(isDark),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: _premiumBorderSubtle(isDark)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _premiumAccent(isDark)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: tt.labelMedium?.copyWith(
              color: _premiumTextSecondary(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingGrid extends StatelessWidget {
  final List<BillingCycle> cycles;
  final BillingCycle selectedCycle;
  final AsyncValue<List<PricingPlan>> pricingAsync;
  final bool checkoutInProgress;
  final bool checkoutDisabled;
  final String checkoutLabel;
  final BillingCycle? heroCycle;
  final ValueChanged<BillingCycle> onSelect;
  final ValueChanged<BillingCycle> onCheckout;

  const _PricingGrid({
    required this.cycles,
    required this.selectedCycle,
    required this.pricingAsync,
    required this.checkoutInProgress,
    required this.checkoutDisabled,
    required this.checkoutLabel,
    required this.heroCycle,
    required this.onSelect,
    required this.onCheckout,
  });

  int _columnsFor(double width) {
    if (width < 640) return 1;
    if (width < 920) return 2;
    if (cycles.length > 3 && width < 1160) return 3;
    return cycles.length.clamp(1, 5);
  }

  double _heightFor(int columns) {
    if (columns == 1) return 198;
    if (columns == 2) return 204;
    return 212;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final gap = AppSpacing.smMd;
        final cardWidth =
            columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap * (columns - 1)) / columns;
        final cardHeight = _heightFor(columns);

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cycle in cycles)
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _PricingCard(
                  cycle: cycle,
                  isHero: cycle == heroCycle,
                  isSelected: selectedCycle == cycle,
                  pricingAsync: pricingAsync,
                  checkoutInProgress: checkoutInProgress,
                  checkoutDisabled: checkoutDisabled,
                  checkoutLabel: checkoutLabel,
                  onSelect: () => onSelect(cycle),
                  onCheckout: () => onCheckout(cycle),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pricing card with hover state and animated borders.
class _PricingCard extends StatefulWidget {
  final BillingCycle cycle;
  final bool isHero;
  final bool isSelected;
  final AsyncValue<List<PricingPlan>> pricingAsync;
  final bool checkoutInProgress;
  final bool checkoutDisabled;
  final String checkoutLabel;
  final VoidCallback onSelect;
  final VoidCallback onCheckout;

  const _PricingCard({
    required this.cycle,
    this.isHero = false,
    required this.isSelected,
    required this.pricingAsync,
    required this.checkoutInProgress,
    required this.checkoutDisabled,
    required this.checkoutLabel,
    required this.onSelect,
    required this.onCheckout,
  });

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = cs.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 136),
          padding: const EdgeInsets.all(AppSpacing.mdLg),
          decoration: _decoration(cs),
          child: Stack(
            children: [
              if (widget.isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _premiumAccent(isDark),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _premiumAccentSoft(isDark),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Icon(
                          widget.isHero
                              ? Icons.verified_rounded
                              : Icons.workspace_premium_rounded,
                          size: 16,
                          color: _premiumAccent(isDark),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _cycleLabel(widget.cycle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            color: _premiumTextPrimary(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildPrice(cs),
                  Row(
                    children: [
                      Expanded(child: _buildBadges()),
                      if (widget.isHero)
                        Flexible(
                          child: Text(
                            AppLocalizations.premiumScreenProfessionalChoice,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: tt.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: _premiumTextMuted(isDark),
                            ),
                          ),
                        ),
                    ],
                  ),
                  _buildInlineCheckoutCta(cs),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _decoration(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return BoxDecoration(
      color:
          widget.isSelected
              ? _premiumSelected(isDark)
              : widget.isHero
              ? Color.alphaBlend(
                _premiumAccent(isDark).withValues(alpha: isDark ? 0.12 : 0.055),
                _premiumCardBg(isDark),
              )
              : _hovered
              ? _premiumCardHover(isDark)
              : _premiumCardBg(isDark),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(
        color:
            widget.isSelected
                ? _premiumAccent(isDark)
                : widget.isHero
                ? _premiumBorderStrong(isDark)
                : _hovered
                ? _premiumBorderStrong(isDark)
                : _premiumBorderSubtle(isDark),
        width: widget.isSelected ? 2 : 1,
      ),
      boxShadow:
          widget.isSelected
              ? [
                BoxShadow(
                  color: _premiumAccent(isDark).withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ]
              : null,
    );
  }

  Widget _buildInlineCheckoutCta(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final isDark = cs.brightness == Brightness.dark;

    if (!widget.isSelected) {
      return const SizedBox(height: 38);
    }

    return SizedBox(
      width: double.infinity,
      height: 38,
      child: FilledButton.icon(
        onPressed:
            widget.checkoutInProgress || widget.checkoutDisabled
                ? null
                : widget.onCheckout,
        icon:
            widget.checkoutInProgress
                ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.lock_open_rounded, size: 16),
        label: Text(
          widget.checkoutLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: _premiumAccent(isDark),
          foregroundColor: Colors.white,
          disabledBackgroundColor: _premiumCardHover(isDark),
          disabledForegroundColor: _premiumTextSecondary(isDark),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
          textStyle: tt.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
    );
  }

  Widget _buildPrice(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final isDark = cs.brightness == Brightness.dark;
    return widget.pricingAsync.when(
      data: (plans) {
        final plan =
            plans.where((p) => p.billingCycle == widget.cycle.name).firstOrNull;
        if (plan == null) return const SizedBox(height: 48);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.displayPrice,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.displayMedium?.copyWith(
                fontSize: widget.isHero ? 32 : 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: _premiumTextPrimary(isDark),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _billingNote(widget.cycle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                color: _premiumTextSecondary(isDark),
              ),
            ),
            if (plan.isLifetime) ...[
              const SizedBox(height: 2),
              Text(
                '${plan.maxDevices} device${plan.maxDevices == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                  color: _premiumTextMuted(isDark),
                ),
              ),
            ],
          ],
        );
      },
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      error: (_, __) => const SizedBox(height: 48),
    );
  }

  Widget _buildBadges() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        if (widget.cycle == BillingCycle.yearly) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _premiumAccentSoft(
                Theme.of(context).brightness == Brightness.dark,
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: _premiumBorderStrong(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
            child: Text(
              AppLocalizations.premiumYearlySave,
              style: AppTypography.compact.copyWith(
                fontWeight: FontWeight.w700,
                color: _premiumAccent(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
        ],
        if (widget.cycle.isLifetime) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              gradient: BrandConfig.current.premiumGradient,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              AppLocalizations.premiumLifetimeBadge,
              style: AppTypography.compact.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Feature category column with icon header and feature items.
class _FeatureColumn extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<PremiumFeature> features;

  const _FeatureColumn({
    required this.title,
    required this.icon,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isDark = cs.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _premiumAccent(isDark).withValues(alpha: isDark ? 0.035 : 0.018),
          _premiumCardBg(isDark),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _premiumBorderSubtle(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _premiumAccentSoft(isDark),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(icon, size: 17, color: _premiumAccent(isDark)),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  title,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: _premiumAccent(isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.mdLg),
          // Feature items
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        UpgradePromptDialog.featureIcon(feature),
                        size: 16,
                        color: _premiumAccent(isDark),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          UpgradePromptDialog.featureDisplayName(feature),
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Text(
                      UpgradePromptDialog.featureDescription(feature),
                      style: tt.bodySmall?.copyWith(
                        color: _premiumTextSecondary(isDark),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single trust signal item — icon + label + description.
class _TrustSignalItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _TrustSignalItem({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _premiumCardBg(isDark),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _premiumBorderSubtle(isDark)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _premiumAccentSoft(isDark),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(icon, size: 18, color: _premiumAccent(isDark)),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: _premiumTextPrimary(isDark),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: _premiumTextSecondary(isDark),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
