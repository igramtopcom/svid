import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/backend_providers.dart';
import '../../data/services/pdfconv_paypal_service.dart';
import '../../data/services/pdfconv_pending_checkout_store.dart';
import '../../domain/entities/pdfconv_paypal_plan.dart';
import '../../domain/entities/pdfconv_purchase_intent.dart';
import '../../domain/entities/premium_license.dart';
import 'pdfconv_paypal_rollout_provider.dart';
import 'premium_providers.dart';

final pdfConvPayPalServiceProvider = Provider<PdfConvPayPalService>((ref) {
  return PdfConvPayPalService(ref.watch(backendClientProvider));
});

final pdfConvPendingCheckoutStoreProvider =
    Provider<PdfConvPendingCheckoutStore>((ref) {
      return PdfConvPendingCheckoutStore(
        ref.watch(secureCredentialStoreProvider),
      );
    });

enum PdfConvCheckoutPhase {
  idle,
  creating,
  openingBrowser,
  waitingForApproval,
  capturing,
  waitingForEntitlement,
  manualReview,
  completed,
  terminal,
}

class PdfConvPayPalState {
  final PdfConvCheckoutPhase phase;
  final PdfConvPendingCheckout? pendingCheckout;
  final PdfConvPurchaseIntent? intent;
  final String? error;
  final String? activationError;

  const PdfConvPayPalState({
    this.phase = PdfConvCheckoutPhase.idle,
    this.pendingCheckout,
    this.intent,
    this.error,
    this.activationError,
  });

  static const initial = PdfConvPayPalState();

  bool get isLoading =>
      phase == PdfConvCheckoutPhase.creating ||
      phase == PdfConvCheckoutPhase.openingBrowser ||
      phase == PdfConvCheckoutPhase.capturing;

  bool get isWaiting =>
      phase == PdfConvCheckoutPhase.waitingForApproval ||
      phase == PdfConvCheckoutPhase.waitingForEntitlement ||
      phase == PdfConvCheckoutPhase.manualReview;

  bool get isActivationSuccess => phase == PdfConvCheckoutPhase.completed;

  PdfConvPayPalState copyWith({
    PdfConvCheckoutPhase? phase,
    PdfConvPendingCheckout? pendingCheckout,
    PdfConvPurchaseIntent? intent,
    String? error,
    String? activationError,
    bool clearPendingCheckout = false,
    bool clearIntent = false,
    bool clearError = false,
    bool clearActivationError = false,
  }) {
    return PdfConvPayPalState(
      phase: phase ?? this.phase,
      pendingCheckout:
          clearPendingCheckout
              ? null
              : (pendingCheckout ?? this.pendingCheckout),
      intent: clearIntent ? null : (intent ?? this.intent),
      error: clearError ? null : (error ?? this.error),
      activationError:
          clearActivationError
              ? null
              : (activationError ?? this.activationError),
    );
  }
}

typedef PdfConvLicenseActivator =
    Future<void> Function(PdfConvPurchaseIntent intent);

/// Owns one recoverable PDFConv PayPal purchase at a time.
///
/// Browser returns only wake this notifier. Every grant decision comes from
/// SnakeLoader's authenticated status response.
class PdfConvPayPalNotifier extends StateNotifier<PdfConvPayPalState> {
  static const _checkoutDisabled =
      'PayPal checkout is temporarily unavailable.';
  static const _pendingSelectionConflict =
      'A different PayPal checkout is still pending. Continue that payment '
      'before changing the plan or email.';

  final PdfConvPayPalService _service;
  final PdfConvPendingCheckoutStore _store;
  final PdfConvLicenseActivator _activateLicense;
  final bool Function() _canCreateIntent;
  final Future<void> Function(Duration) _delay;

  Future<void> _checkoutGate = Future<void>.value();
  Future<void>? _reconcileInFlight;
  Future<bool>? _refreshInFlight;
  int _pollEpoch = 0;

  PdfConvPayPalNotifier({
    required PdfConvPayPalService service,
    required PdfConvPendingCheckoutStore store,
    required PdfConvLicenseActivator activateLicense,
    bool Function()? canCreateIntent,
    Future<void> Function(Duration)? delay,
  }) : _service = service,
       _store = store,
       _activateLicense = activateLicense,
       _canCreateIntent = canCreateIntent ?? _allowCreateIntent,
       _delay = delay ?? Future<void>.delayed,
       super(PdfConvPayPalState.initial);

  Future<void> startCheckout({
    required PdfConvPlanId planId,
    required String buyerEmail,
    int maxPollAttempts = 60,
    Duration initialPollDelay = const Duration(seconds: 2),
    Duration maxPollDelay = const Duration(seconds: 10),
  }) async {
    cancelPolling();
    final epoch = _pollEpoch;

    try {
      final shouldPoll = await _withCheckoutGate(
        () => _startCheckout(
          planId: planId,
          buyerEmail: PdfConvPayPalService.canonicalizeBuyerEmail(buyerEmail),
        ),
      );
      if (!mounted || !shouldPoll) return;

      await pollPending(
        maxAttempts: maxPollAttempts,
        initialDelay: initialPollDelay,
        maxDelay: maxPollDelay,
        pollEpoch: epoch,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.idle,
        error: _displayError(error),
      );
    }
  }

  Future<bool> _startCheckout({
    required PdfConvPlanId planId,
    required String buyerEmail,
  }) async {
    if (!mounted) return false;

    var marker = await _store.read();
    final selectionChanged =
        marker != null &&
        (marker.planId != planId || marker.buyerEmail != buyerEmail);

    if (selectionChanged) {
      final existingMarker = marker;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.creating,
        pendingCheckout: existingMarker,
        clearError: true,
      );

      // Reconcile the persisted purchase before deciding whether a new request
      // may be created. A transport failure leaves the marker in place.
      await _refresh(existingMarker, allowCapture: true);
      if (!mounted) return false;

      final remainingMarker = await _store.read();
      if (remainingMarker != null) {
        state = state.copyWith(
          phase: _waitingPhase(state.intent),
          pendingCheckout: remainingMarker,
          error: _pendingSelectionConflict,
        );
        return false;
      }
      if (state.phase != PdfConvCheckoutPhase.terminal) {
        // A granted purchase also clears its marker after local activation. Do
        // not turn that successful reconciliation into an immediate new order.
        return false;
      }
      marker = null;
    }

    if (marker == null && !_canCreateIntent()) {
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.idle,
        error: _checkoutDisabled,
        clearActivationError: true,
      );
      return false;
    }

    final shouldPersistMarker = marker == null;
    marker ??= PdfConvPendingCheckout(
      idempotencyKey: _service.newIdempotencyKey(),
      planId: planId,
      buyerEmail: buyerEmail,
      createdAt: DateTime.now().toUtc(),
    );
    if (shouldPersistMarker) {
      // Persist the full request identity before the first network call.
      await _store.write(marker);
    }
    if (!mounted) return false;
    state = state.copyWith(
      phase: PdfConvCheckoutPhase.creating,
      pendingCheckout: marker,
      clearIntent: shouldPersistMarker || selectionChanged,
      clearError: true,
      clearActivationError: true,
    );

    final done = await _refresh(marker, allowCapture: true);
    if (!mounted || done) return false;

    final currentMarker = state.pendingCheckout ?? marker;
    final approvalUrl = _approvalUrlForMarker(currentMarker);
    if (approvalUrl != null) {
      state = state.copyWith(phase: PdfConvCheckoutPhase.openingBrowser);
      final opened = await _service.openApprovalPage(approvalUrl);
      if (!mounted) return false;
      if (!opened) {
        state = state.copyWith(
          phase: PdfConvCheckoutPhase.waitingForApproval,
          error: 'Could not open the PayPal payment page',
        );
        return false;
      }
    }

    return true;
  }

  Future<T> _withCheckoutGate<T>(Future<T> Function() operation) async {
    final predecessor = _checkoutGate;
    final release = Completer<void>();
    _checkoutGate = release.future;
    await predecessor;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  /// Replays a draft with the original idempotency key or refreshes its intent.
  /// It never opens the browser during startup recovery.
  Future<void> recoverPendingCheckout({
    int maxPollAttempts = 60,
    Duration initialPollDelay = const Duration(seconds: 2),
    Duration maxPollDelay = const Duration(seconds: 10),
  }) {
    return _reconcilePendingCheckout(
      maxPollAttempts: maxPollAttempts,
      initialPollDelay: initialPollDelay,
      maxPollDelay: maxPollDelay,
    );
  }

  /// Called by deep-link wake events and the in-app "already paid" action.
  Future<void> refreshPendingCheckout({
    int maxPollAttempts = 60,
    Duration initialPollDelay = const Duration(seconds: 2),
    Duration maxPollDelay = const Duration(seconds: 10),
  }) {
    return _reconcilePendingCheckout(
      maxPollAttempts: maxPollAttempts,
      initialPollDelay: initialPollDelay,
      maxPollDelay: maxPollDelay,
    );
  }

  Future<void> _reconcilePendingCheckout({
    required int maxPollAttempts,
    required Duration initialPollDelay,
    required Duration maxPollDelay,
  }) {
    final inFlight = _reconcileInFlight;
    if (inFlight != null) return inFlight;

    final operation = _reconcilePendingCheckoutOnce(
      maxPollAttempts: maxPollAttempts,
      initialPollDelay: initialPollDelay,
      maxPollDelay: maxPollDelay,
    );
    _reconcileInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_reconcileInFlight, operation)) {
        _reconcileInFlight = null;
      }
    });
  }

  Future<void> _reconcilePendingCheckoutOnce({
    required int maxPollAttempts,
    required Duration initialPollDelay,
    required Duration maxPollDelay,
  }) async {
    final epoch = _pollEpoch;
    try {
      final marker = state.pendingCheckout ?? await _store.read();
      if (marker == null || !mounted) return;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.creating,
        pendingCheckout: marker,
        clearError: true,
      );

      final done = await _refresh(marker, allowCapture: true);
      if (!mounted || done || epoch != _pollEpoch) return;

      final remainingMarker = state.pendingCheckout ?? await _store.read();
      if (remainingMarker == null) return;
      if (remainingMarker.purchaseIntentId == null && !_canCreateIntent()) {
        return;
      }
      if (maxPollAttempts <= 0) return;

      await pollPending(
        maxAttempts: maxPollAttempts,
        initialDelay: initialPollDelay,
        maxDelay: maxPollDelay,
        pollEpoch: epoch,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        phase: _waitingPhase(state.intent),
        error: _displayError(error),
      );
    }
  }

  Future<void> pollPending({
    int maxAttempts = 60,
    Duration initialDelay = const Duration(seconds: 2),
    Duration maxDelay = const Duration(seconds: 10),
    int? pollEpoch,
  }) async {
    final epoch = pollEpoch ?? _pollEpoch;
    var delay = initialDelay;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || epoch != _pollEpoch) return;
      await _delay(delay);
      if (!mounted || epoch != _pollEpoch) return;

      final marker = state.pendingCheckout ?? await _store.read();
      if (marker == null) return;
      final done = await _refresh(marker, allowCapture: true);
      if (done || !mounted) return;

      final nextMs = (delay.inMilliseconds * 2).clamp(
        initialDelay.inMilliseconds,
        maxDelay.inMilliseconds,
      );
      delay = Duration(milliseconds: nextMs.toInt());
    }

    if (mounted && epoch == _pollEpoch) {
      state = state.copyWith(phase: _waitingPhase(state.intent));
    }
  }

  Future<bool> _refresh(
    PdfConvPendingCheckout marker, {
    required bool allowCapture,
  }) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final operation = _refreshOnce(marker, allowCapture: allowCapture);
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _refreshOnce(
    PdfConvPendingCheckout marker, {
    required bool allowCapture,
  }) async {
    try {
      var currentMarker = marker;
      late PdfConvPurchaseIntent intent;
      if (currentMarker.purchaseIntentId == null) {
        if (!_canCreateIntent()) {
          state = state.copyWith(
            phase: PdfConvCheckoutPhase.idle,
            pendingCheckout: currentMarker,
            error: _checkoutDisabled,
          );
          return false;
        }
        intent = await _service.createIntent(
          planId: currentMarker.planId,
          buyerEmail: currentMarker.buyerEmail,
          idempotencyKey: currentMarker.idempotencyKey,
        );
      } else {
        intent = await _service.getIntentStatus(
          currentMarker.purchaseIntentId!,
        );
      }
      if (!mounted) return false;

      _requireMatchingIntent(currentMarker, intent);

      if (currentMarker.purchaseIntentId == null ||
          intent.approvalUrl != null) {
        currentMarker = currentMarker.bindPurchaseIntent(
          intent.purchaseIntentId,
          approvalUrl: intent.approvalUrl,
        );
        await _store.write(currentMarker);
      }
      if (!mounted) return false;
      state = state.copyWith(
        pendingCheckout: currentMarker,
        intent: intent,
        phase: _waitingPhase(intent),
        clearError: true,
      );

      if (_isRevokedOrReversed(intent)) {
        await _store.clear();
        if (!mounted) return true;
        state = state.copyWith(
          phase: PdfConvCheckoutPhase.terminal,
          clearPendingCheckout: true,
          error: 'This PayPal entitlement is no longer active',
        );
        return true;
      }

      if (intent.isActivatable) {
        try {
          await _activateLicense(intent);
          await _store.clear();
          if (!mounted) return true;
          state = state.copyWith(
            phase: PdfConvCheckoutPhase.completed,
            clearPendingCheckout: true,
            clearError: true,
            clearActivationError: true,
          );
        } catch (error) {
          if (!mounted) return false;
          state = state.copyWith(
            phase: PdfConvCheckoutPhase.waitingForEntitlement,
            activationError: _displayError(error),
          );
        }
        return true;
      }

      if (intent.entitlementStatus == PdfConvEntitlementStatus.granted) {
        // The strict response model normally prevents this branch. Keep the
        // marker if a future backend response cannot yet be activated.
        state = state.copyWith(
          phase: PdfConvCheckoutPhase.waitingForEntitlement,
          activationError: 'The license is not ready for local activation',
        );
        return true;
      }

      if (intent.billingStatus.isDefinitiveFailure) {
        await _store.clear();
        if (!mounted) return true;
        state = state.copyWith(
          phase: PdfConvCheckoutPhase.terminal,
          clearPendingCheckout: true,
        );
        return true;
      }

      if (intent.billingStatus == PdfConvBillingStatus.manualReview) {
        state = state.copyWith(phase: PdfConvCheckoutPhase.manualReview);
        return true;
      }

      if (allowCapture && intent.requiresCapture) {
        state = state.copyWith(phase: PdfConvCheckoutPhase.capturing);
        intent = await _service.captureIntent(intent.purchaseIntentId);
        if (!mounted) return false;
        _requireMatchingIntent(currentMarker, intent);
        state = state.copyWith(intent: intent, phase: _waitingPhase(intent));
        return _processCaptureResult(intent);
      }

      return false;
    } catch (error) {
      if (!mounted) return false;
      // Transport/auth/upstream errors never delete a purchase marker.
      state = state.copyWith(
        phase: _waitingPhase(state.intent),
        error: _displayError(error),
      );
      // Identity/schema failures cannot converge by polling the same intent.
      return error is FormatException;
    }
  }

  Future<bool> _processCaptureResult(PdfConvPurchaseIntent intent) async {
    if (_isRevokedOrReversed(intent)) {
      await _store.clear();
      if (!mounted) return true;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.terminal,
        clearPendingCheckout: true,
        error: 'This PayPal entitlement is no longer active',
      );
      return true;
    }
    if (intent.billingStatus.isDefinitiveFailure) {
      await _store.clear();
      if (!mounted) return true;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.terminal,
        clearPendingCheckout: true,
      );
      return true;
    }
    if (!intent.isActivatable) return false;

    try {
      await _activateLicense(intent);
      await _store.clear();
      if (!mounted) return true;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.completed,
        clearPendingCheckout: true,
        clearError: true,
        clearActivationError: true,
      );
      return true;
    } catch (error) {
      if (!mounted) return true;
      state = state.copyWith(
        phase: PdfConvCheckoutPhase.waitingForEntitlement,
        activationError: _displayError(error),
      );
      return true;
    }
  }

  Future<bool> reopenApprovalPage() async {
    try {
      var marker = state.pendingCheckout ?? await _store.read();
      if (marker == null) return false;
      if (marker.approvalUrl == null) {
        await _refresh(marker, allowCapture: false);
        marker = state.pendingCheckout ?? marker;
      }
      final approvalUrl = _approvalUrlForMarker(marker);
      if (approvalUrl == null) return false;
      return await _service.openApprovalPage(approvalUrl);
    } catch (error) {
      if (mounted) state = state.copyWith(error: _displayError(error));
      return false;
    }
  }

  void cancelPolling() {
    _pollEpoch++;
  }

  Uri? _approvalUrlForMarker(PdfConvPendingCheckout marker) {
    if (marker.approvalUrl != null) return marker.approvalUrl;

    final intent = state.intent;
    if (marker.purchaseIntentId != null &&
        intent?.purchaseIntentId == marker.purchaseIntentId) {
      return intent?.approvalUrl;
    }
    return null;
  }

  void resetPresentationState() {
    cancelPolling();
    state = PdfConvPayPalState.initial;
  }

  @override
  void dispose() {
    cancelPolling();
    super.dispose();
  }
}

PdfConvCheckoutPhase _waitingPhase(PdfConvPurchaseIntent? intent) {
  if (intent == null) return PdfConvCheckoutPhase.waitingForApproval;
  if (intent.billingStatus == PdfConvBillingStatus.manualReview) {
    return PdfConvCheckoutPhase.manualReview;
  }
  if (intent.isAwaitingSettlement) {
    return PdfConvCheckoutPhase.waitingForEntitlement;
  }
  return PdfConvCheckoutPhase.waitingForApproval;
}

bool _isRevokedOrReversed(PdfConvPurchaseIntent intent) {
  return intent.entitlementStatus == PdfConvEntitlementStatus.revoked ||
      intent.billingStatus == PdfConvBillingStatus.refunded ||
      intent.billingStatus == PdfConvBillingStatus.reversed;
}

void _requireMatchingIntent(
  PdfConvPendingCheckout marker,
  PdfConvPurchaseIntent intent,
) {
  if (intent.planId != marker.planId ||
      (marker.purchaseIntentId != null &&
          intent.purchaseIntentId != marker.purchaseIntentId)) {
    throw const FormatException(
      'PDFConv response does not match the persisted purchase identity',
    );
  }
}

String _displayError(Object error) {
  final value = error.toString();
  return value.length <= 300 ? value : '${value.substring(0, 300)}...';
}

BillingCycle _billingCycleFor(PdfConvPlanId planId) => switch (planId) {
  PdfConvPlanId.p7 => BillingCycle.p7,
  PdfConvPlanId.p30 => BillingCycle.p30,
  PdfConvPlanId.p90 => BillingCycle.p90,
  PdfConvPlanId.lifetime => BillingCycle.lifetime,
};

bool _allowCreateIntent() => true;

final pdfConvPayPalProvider =
    StateNotifierProvider<PdfConvPayPalNotifier, PdfConvPayPalState>((ref) {
      final premiumNotifier = ref.watch(premiumLicenseProvider.notifier);
      return PdfConvPayPalNotifier(
        service: ref.watch(pdfConvPayPalServiceProvider),
        store: ref.watch(pdfConvPendingCheckoutStoreProvider),
        canCreateIntent: () => ref.read(pdfConvPayPalCheckoutEnabledProvider),
        activateLicense: (intent) async {
          await premiumNotifier.activateLicense(
            intent.licenseKey!,
            paymentMethod: 'paypal_pdfconv',
            transactionId: intent.purchaseIntentId,
            billingCycle: _billingCycleFor(intent.planId),
            expiresAt: intent.licenseExpiresAt,
            isAutoRenew: false,
          );
        },
      );
    });
