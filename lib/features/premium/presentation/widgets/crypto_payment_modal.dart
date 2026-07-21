import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/services/clipboard_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/crypto_currency.dart';
import '../../domain/entities/crypto_invoice.dart';
import '../../domain/entities/payment_result.dart';
import '../../domain/entities/premium_license.dart';
import '../providers/payment_providers.dart';

/// Nocturne Cinematic crypto payment modal — "The Vault".
///
/// Full-screen overlay with blurred backdrop and a two-column glass panel.
/// Left column: plan details + network (BTC/LTC/XMR) selector.
/// Right column: countdown timer + QR code + wallet address + heartbeat tracker.
///
/// Design ref: Stitch `5a9661b3` — docs/design-specs/premium-crypto-payment.md
class CryptoPaymentModal extends ConsumerStatefulWidget {
  final BillingCycle billingCycle;
  final String? planPrice;

  const CryptoPaymentModal({
    required this.billingCycle,
    this.planPrice,
    super.key,
  });

  /// Show the crypto payment modal as a full-screen transparent route.
  static Future<void> show(
    BuildContext context, {
    required BillingCycle billingCycle,
    String? planPrice,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder:
            (_, __, ___) => CryptoPaymentModal(
              billingCycle: billingCycle,
              planPrice: planPrice,
            ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<CryptoPaymentModal> createState() => _CryptoPaymentModalState();
}

class _CryptoPaymentModalState extends ConsumerState<CryptoPaymentModal>
    with TickerProviderStateMixin {
  CryptoCurrency _selectedCurrency = CryptoCurrency.btc;
  bool _invoiceRequested = false;
  Timer? _countdownTimer;
  bool _copied = false;
  bool _qrHovered = false;

  late final AnimationController _heartbeatController;
  late final Animation<double> _heartbeatAnimation;

  @override
  void initState() {
    super.initState();
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _heartbeatAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _heartbeatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _heartbeatController.dispose();
    super.dispose();
  }

  void _startCountdown(CryptoInvoice invoice) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (invoice.isExpired) _countdownTimer?.cancel();
    });
  }

  void _handlePayNow() {
    setState(() => _invoiceRequested = true);
    ref
        .read(paymentProvider.notifier)
        .startCryptoCheckout(_selectedCurrency, widget.billingCycle);
  }

  void _handleClose() {
    final state = ref.read(paymentProvider);

    // If waiting for payment, show confirmation dialog
    if (state.invoice != null && !state.isSuccess && !state.isFailed) {
      showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(AppLocalizations.premiumCryptoLeaveTitle),
              content: Text(AppLocalizations.premiumCryptoLeaveMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(AppLocalizations.premiumCryptoStay),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(AppLocalizations.premiumCryptoLeave),
                ),
              ],
            ),
      ).then((leave) {
        if (leave == true && mounted) {
          ref.read(paymentProvider.notifier).reset();
          Navigator.of(context).pop();
        }
      });
      return;
    }

    ref.read(paymentProvider.notifier).reset();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paymentState = ref.watch(paymentProvider);

    // Start countdown when invoice arrives
    if (paymentState.invoice != null && _countdownTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startCountdown(paymentState.invoice!);
      });
    }

    // Auto-close on success after brief delay
    if (paymentState.isSuccess) {
      final nav = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) nav.pop();
        });
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Layer 0: Blurred backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: AppOpacity.overlay),
              ),
            ),
          ),

          // Layer 1: Modal glass panel
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < 780 ||
                        constraints.maxHeight < 620;
                    final maxHeight =
                        constraints.maxHeight - (AppSpacing.md * 2);
                    final rightWidth =
                        constraints.maxWidth < 860 ? 360.0 : 400.0;

                    Widget modalContent;
                    if (compact) {
                      modalContent = SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LeftColumn(
                              billingCycle: widget.billingCycle,
                              planPrice: widget.planPrice,
                              invoice: paymentState.invoice,
                              selectedCurrency: _selectedCurrency,
                              isLocked: _invoiceRequested,
                              isLoading: paymentState.isLoading,
                              compact: true,
                              onCurrencyChanged:
                                  (c) => setState(() => _selectedCurrency = c),
                              onPayNow: _handlePayNow,
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: cs.outlineVariant.withValues(
                                alpha: AppOpacity.pressed,
                              ),
                            ),
                            _RightColumn(
                              invoice: paymentState.invoice,
                              paymentState: paymentState,
                              qrHovered: _qrHovered,
                              copied: _copied,
                              heartbeatAnimation: _heartbeatAnimation,
                              compact: true,
                              onQrHover: (h) => setState(() => _qrHovered = h),
                              onCopy: () async {
                                if (paymentState.invoice == null) return;
                                await ClipboardService.setText(
                                  paymentState.invoice!.address,
                                );
                                setState(() => _copied = true);
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (mounted) setState(() => _copied = false);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    } else {
                      modalContent = Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _LeftColumn(
                              billingCycle: widget.billingCycle,
                              planPrice: widget.planPrice,
                              invoice: paymentState.invoice,
                              selectedCurrency: _selectedCurrency,
                              isLocked: _invoiceRequested,
                              isLoading: paymentState.isLoading,
                              onCurrencyChanged:
                                  (c) => setState(() => _selectedCurrency = c),
                              onPayNow: _handlePayNow,
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: cs.outlineVariant.withValues(
                              alpha: AppOpacity.pressed,
                            ),
                          ),
                          SizedBox(
                            width: rightWidth,
                            child: _RightColumn(
                              invoice: paymentState.invoice,
                              paymentState: paymentState,
                              qrHovered: _qrHovered,
                              copied: _copied,
                              heartbeatAnimation: _heartbeatAnimation,
                              onQrHover: (h) => setState(() => _qrHovered = h),
                              onCopy: () async {
                                if (paymentState.invoice == null) return;
                                await ClipboardService.setText(
                                  paymentState.invoice!.address,
                                );
                                setState(() => _copied = true);
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (mounted) setState(() => _copied = false);
                                });
                              },
                            ),
                          ),
                        ],
                      );
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 896,
                        maxHeight: maxHeight > 360 ? maxHeight : 360,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xE60E0E0E),
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              border: Border.all(
                                color: AppColors.accentHighlight.withValues(
                                  alpha: AppOpacity.subtle,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: AppOpacity.overlay,
                                  ),
                                  blurRadius: 36,
                                  offset: const Offset(0, 24),
                                ),
                              ],
                            ),
                            child: modalContent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Layer 2: Close button
          if (!paymentState.isLoading || paymentState.invoice != null)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final panelWidth =
                          constraints.maxWidth < 896
                              ? constraints.maxWidth
                              : 896.0;

                      return Center(
                        child: SizedBox(
                          width: panelWidth,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.smMd),
                              child: _CloseButton(onClose: _handleClose),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== LEFT COLUMN ====================

class _LeftColumn extends StatelessWidget {
  final BillingCycle billingCycle;
  final String? planPrice;
  final CryptoInvoice? invoice;
  final CryptoCurrency selectedCurrency;
  final bool isLocked;
  final bool isLoading;
  final bool compact;
  final ValueChanged<CryptoCurrency> onCurrencyChanged;
  final VoidCallback onPayNow;

  const _LeftColumn({
    required this.billingCycle,
    this.planPrice,
    this.invoice,
    required this.selectedCurrency,
    required this.isLocked,
    required this.isLoading,
    this.compact = false,
    required this.onCurrencyChanged,
    required this.onPayNow,
  });

  String _planTitle(BillingCycle cycle) => switch (cycle) {
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

  String _confirmationDetail(CryptoCurrency c) => switch (c) {
    CryptoCurrency.btc => AppLocalizations.premiumCryptoConfirmBtc,
    CryptoCurrency.ltc => AppLocalizations.premiumCryptoConfirmLtc,
    CryptoCurrency.xmr => AppLocalizations.premiumCryptoConfirmXmr,
  };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + label
          Row(
            children: [
              Icon(
                Icons.stars_rounded,
                color: AppColors.accentHighlight,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppLocalizations.premiumCryptoActivation.toUpperCase(),
                style: tt.labelMedium?.copyWith(
                  color: AppColors.accentHighlight,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xs),

          // Plan title
          Text(
            _planTitle(billingCycle),
            style: tt.headlineLarge?.copyWith(
              fontSize: compact ? 30 : 36,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Crypto amount
          Text(
            invoice != null
                ? '${invoice!.amount} ${invoice!.currency.symbol}'
                : '—',
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w300,
              color: AppColors.accentHighlight,
            ),
          ),

          const SizedBox(height: AppSpacing.xxs),

          // USD price
          Text(
            planPrice ?? '',
            style: tt.labelLarge?.copyWith(color: Colors.white70),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Network selector label
          Text(
            AppLocalizations.premiumCryptoSelectNetwork.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: Colors.white38,
              letterSpacing: 3.0,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Network radio cards
          for (final currency in CryptoCurrency.values)
            _NetworkCard(
              currency: currency,
              isSelected: selectedCurrency == currency,
              isEnabled: !isLocked,
              confirmationDetail: _confirmationDetail(currency),
              onTap: () => onCurrencyChanged(currency),
            ),

          // Pay button (only when idle)
          if (!isLocked) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.premium,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: [AppGradients.glowCta],
                ),
                child: MaterialButton(
                  onPressed: onPayNow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    AppLocalizations.premiumCryptoPayWith(
                      selectedCurrency.symbol,
                    ),
                    style: AppTypography.fileName.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],

          if (isLoading && invoice == null) ...[
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentHighlight,
                ),
              ),
            ),
          ],

          if (compact)
            const SizedBox(height: AppSpacing.lg)
          else
            const Spacer(),

          // Status quote
          const _StatusQuote(),
        ],
      ),
    );
  }
}

// ==================== RIGHT COLUMN ====================

class _RightColumn extends StatelessWidget {
  final CryptoInvoice? invoice;
  final PaymentState paymentState;
  final bool qrHovered;
  final bool copied;
  final Animation<double> heartbeatAnimation;
  final bool compact;
  final ValueChanged<bool> onQrHover;
  final VoidCallback onCopy;

  const _RightColumn({
    this.invoice,
    required this.paymentState,
    required this.qrHovered,
    required this.copied,
    required this.heartbeatAnimation,
    this.compact = false,
    required this.onQrHover,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      color: AppColors.darkBase,
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // Countdown chip
          if (invoice != null) ...[
            _CountdownChip(invoice: invoice!),
            const SizedBox(height: AppSpacing.lg),
          ],

          // QR code or placeholder
          if (paymentState.isSuccess) ...[
            // Confirmed state — checkmark
            if (!compact) const Spacer(),
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.accentHighlight,
              size: 80,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppLocalizations.premiumCryptoConfirmed,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.accentHighlight,
              ),
            ),
            if (!compact) const Spacer(),
          ] else if (invoice != null) ...[
            // QR container
            _QrContainer(
              invoice: invoice!,
              isHovered: qrHovered,
              onHover: onQrHover,
            ),
            const SizedBox(height: AppSpacing.md),

            // Wallet address block
            _WalletAddressBlock(address: invoice!.address),
            const SizedBox(height: AppSpacing.smMd),

            // Copy button
            _CopyAddressButton(copied: copied, onCopy: onCopy),
            const SizedBox(height: AppSpacing.mdLg),

            // Heartbeat tracker
            _HeartbeatTracker(
              heartbeatAnimation: heartbeatAnimation,
              invoice: invoice!,
              result: paymentState.result,
            ),
          ] else ...[
            // Placeholder when no invoice
            if (!compact) const Spacer(),
            Icon(
              Icons.qr_code_2_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: AppOpacity.pressed),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppLocalizations.premiumCryptoSelectPrompt,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: AppOpacity.scrim),
              ),
            ),
            if (!compact) const Spacer(),
          ],
        ],
      ),
    );
  }
}

// ==================== NETWORK CARD ====================

class _NetworkCard extends StatefulWidget {
  final CryptoCurrency currency;
  final bool isSelected;
  final bool isEnabled;
  final String confirmationDetail;
  final VoidCallback onTap;

  const _NetworkCard({
    required this.currency,
    required this.isSelected,
    required this.isEnabled,
    required this.confirmationDetail,
    required this.onTap,
  });

  @override
  State<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends State<_NetworkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          onTap: widget.isEnabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            height: 64,
            decoration: BoxDecoration(
              color:
                  widget.isSelected
                      ? AppColors.brand.withValues(alpha: AppOpacity.quarter)
                      : _hovered
                      ? AppColors.darkElevated.withValues(
                        alpha: AppOpacity.secondary,
                      )
                      : AppColors.darkElevated.withValues(
                        alpha: AppOpacity.medium,
                      ),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    widget.isSelected
                        ? AppColors.brand.withValues(alpha: AppOpacity.scrim)
                        : _hovered
                        ? cs.outlineVariant.withValues(
                          alpha: AppOpacity.quarter,
                        )
                        : Colors.transparent,
              ),
              boxShadow:
                  widget.isSelected
                      ? [
                        BoxShadow(
                          color: AppColors.brand.withValues(
                            alpha: AppOpacity.medium,
                          ),
                          blurRadius: 40,
                          spreadRadius: -10,
                        ),
                      ]
                      : [],
            ),
            child: Row(
              children: [
                Icon(
                  widget.isSelected
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color:
                      widget.isSelected
                          ? AppColors.accentHighlight
                          : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.smMd),
                Text(
                  widget.currency.symbol,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.currency.displayName,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        widget.confirmationDetail,
                        style: tt.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== STATUS QUOTE ====================

class _StatusQuote extends StatelessWidget {
  const _StatusQuote();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.mdLg),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.overlay),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border(left: BorderSide(color: AppColors.brand, width: 2)),
      ),
      child: Text(
        AppLocalizations.premiumCryptoStatusQuote,
        style: tt.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.white70,
        ),
      ),
    );
  }
}

// ==================== COUNTDOWN CHIP ====================

class _CountdownChip extends StatelessWidget {
  final CryptoInvoice invoice;

  const _CountdownChip({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final remaining = invoice.timeRemaining;
    final isExpired = invoice.isExpired;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkSurface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: AppOpacity.pressed),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isExpired)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentHighlight,
              ),
            )
          else
            Icon(Icons.timer_off, size: 14, color: cs.error),
          const SizedBox(width: AppSpacing.sm),
          Text(
            isExpired
                ? AppLocalizations.premiumCryptoInvoiceExpired
                : AppLocalizations.premiumCryptoInvoiceExpires(
                  remaining.inMinutes.remainder(60).toString().padLeft(2, '0'),
                  remaining.inSeconds.remainder(60).toString().padLeft(2, '0'),
                ),
            style: tt.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: isExpired ? cs.error : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== QR CONTAINER ====================

class _QrContainer extends StatelessWidget {
  final CryptoInvoice invoice;
  final bool isHovered;
  final ValueChanged<bool> onHover;

  const _QrContainer({
    required this.invoice,
    required this.isHovered,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedScale(
        scale: isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Hover glow background
            AnimatedOpacity(
              opacity: isHovered ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.pressed,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),

            // QR container
            Container(
              width: 192,
              height: 192,
              padding: const EdgeInsets.all(AppSpacing.smMd),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(
                      alpha: AppOpacity.quarter,
                    ),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: QrImageView(
                data: invoice.paymentUri,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== WALLET ADDRESS BLOCK ====================

class _WalletAddressBlock extends StatelessWidget {
  final String address;

  const _WalletAddressBlock({required this.address});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: AppOpacity.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.premiumCryptoWalletAddress.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              letterSpacing: 3.0,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            address,
            style: tt.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== COPY ADDRESS BUTTON ====================

class _CopyAddressButton extends StatelessWidget {
  final bool copied;
  final VoidCallback onCopy;

  const _CopyAddressButton({required this.copied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onCopy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: copied ? null : AppGradients.premium,
          color: copied ? AppColors.darkSurface1 : null,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Text(
          copied
              ? AppLocalizations.premiumCryptoAddressCopied
              : AppLocalizations.premiumCryptoCopyAddress,
          textAlign: TextAlign.center,
          style: tt.labelSmall?.copyWith(
            color: Colors.white,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ==================== HEARTBEAT TRACKER ====================

class _HeartbeatTracker extends StatelessWidget {
  final Animation<double> heartbeatAnimation;
  final CryptoInvoice invoice;
  final PaymentResult? result;

  const _HeartbeatTracker({
    required this.heartbeatAnimation,
    required this.invoice,
    this.result,
  });

  String _statusText() {
    if (result != null && result!.isSuccess) {
      return AppLocalizations.premiumCryptoStatusConfirmed;
    }
    final confirmations = invoice.confirmations;
    final required = invoice.currency.requiredConfirmations;
    if (confirmations > 0) {
      return AppLocalizations.premiumCryptoStatusConfirmations(
        confirmations,
        required,
      );
    }
    return AppLocalizations.premiumCryptoStatusScanning;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer static ring
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentHighlight.withValues(
                      alpha: AppOpacity.quarter,
                    ),
                  ),
                ),
              ),

              // Inner animated ring
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.secondary,
                  ),
                ),
              ),

              // Heart icon: pulsing
              ScaleTransition(
                scale: heartbeatAnimation,
                child: Icon(
                  Icons.monitor_heart,
                  color: AppColors.accentHighlight,
                  size: 24,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.smMd),

        Text(
          AppLocalizations.premiumCryptoWaitingConfirmation,
          style: tt.labelSmall?.copyWith(color: Colors.white70),
        ),

        const SizedBox(height: AppSpacing.xxs),

        Text(
          _statusText(),
          style: AppTypography.mini.copyWith(
            color: Colors.white70,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ==================== CLOSE BUTTON ====================

class _CloseButton extends StatelessWidget {
  final VoidCallback onClose;

  const _CloseButton({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onClose,
      icon: const Icon(Icons.close, color: Colors.white70, size: 24),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: AppOpacity.scrim),
        shape: const CircleBorder(),
      ),
    );
  }
}
