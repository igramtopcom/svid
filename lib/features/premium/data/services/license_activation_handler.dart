import 'dart:async';
import 'package:flutter/services.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/vidcombo/vidcombo_backend_adapter.dart';
import '../../domain/entities/premium_license.dart';
import '../../domain/services/premium_license_service.dart';
import 'license_verification_service.dart';

/// Signature for activation routed through PremiumNotifier. Injected by the
/// provider so this data-layer service never imports presentation; the
/// callback wraps PremiumNotifier.activateLicense and therefore updates
/// Riverpod state + fires the success-callback chain (tombstone clear, etc.).
typedef ActivateViaNotifier =
    Future<void> Function(
      String key, {
      String? paymentMethod,
      BillingCycle? billingCycle,
      DateTime? expiresAt,
    });

typedef VerifyPhpLicenseKey =
    Future<LicenseVerificationResponse> Function(String key);

/// Wake-up hook for a browser return from hosted payment.
///
/// The callback intentionally receives no URI payload: browser return values
/// are correlation hints only. The payment flow must re-check its persisted
/// purchase intent with the backend before changing entitlement.
typedef PaymentCompleteCallback = Future<void> Function();

/// Routes incoming brand deep links.
///
/// License activation links are verified before activation. Payment-complete
/// links only invoke a wake-up callback; they never prove payment or grant
/// entitlement.
class LicenseActivationHandler {
  final LicenseVerificationService _verificationService;
  final ActivateViaNotifier _activateViaNotifier;
  final VerifyPhpLicenseKey _verifyPhpLicenseKey;
  final PaymentCompleteCallback? _onPaymentComplete;
  final MethodChannel _channel;

  final _activationController =
      StreamController<LicenseActivationResult>.broadcast();

  /// Stream of activation results (for UI to listen to).
  Stream<LicenseActivationResult> get activationResults =>
      _activationController.stream;

  LicenseActivationHandler({
    required LicenseVerificationService verificationService,
    required ActivateViaNotifier activateViaNotifier,
    VerifyPhpLicenseKey? verifyPhpLicenseKey,
    PaymentCompleteCallback? onPaymentComplete,
    MethodChannel? channel,
  }) : _verificationService = verificationService,
       _activateViaNotifier = activateViaNotifier,
       _verifyPhpLicenseKey =
           verifyPhpLicenseKey ?? _verifyVidComboPhpLicenseKey,
       _onPaymentComplete = onPaymentComplete,
       _channel =
           channel ??
           MethodChannel(
             '${BrandConfig.current.methodChannelPrefix}/uri_scheme',
           ) {
    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_announceReady());
  }

  Future<void> _announceReady() async {
    try {
      await _channel.invokeMethod<void>('uriHandlerReady');
    } on MissingPluginException {
      // Windows/Linux route launch URIs through argv instead of this channel.
    } catch (e) {
      appLogger.debug('URI handler readiness signal failed: $e');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'handleUri') {
      final uriString = call.arguments as String?;
      if (uriString != null) {
        await handleUri(Uri.tryParse(uriString));
      }
    }
  }

  /// Parse and handle an incoming URI.
  Future<void> handleUri(Uri? uri) async {
    if (uri == null) return;

    if (uri.scheme.toLowerCase() !=
        BrandConfig.current.urlScheme.toLowerCase()) {
      return;
    }

    final host = uri.host.toLowerCase();
    if (host == 'payment-complete') {
      appLogger.info('Payment return received; requesting status refresh');
      try {
        await _onPaymentComplete?.call();
      } catch (e) {
        appLogger.warning('Payment return refresh failed (non-critical): $e');
      }
      return;
    }

    if (host != 'activate') return;

    final key = uri.queryParameters['key'];
    if (key == null || key.isEmpty) {
      appLogger.warning('Deep link missing license key');
      _activationController.add(LicenseActivationResult.invalidKey);
      return;
    }

    // Validate format
    if (!PremiumLicenseService.isValidLicenseKey(key)) {
      appLogger.warning('Deep link has invalid license key format');
      _activationController.add(LicenseActivationResult.invalidKey);
      return;
    }

    appLogger.info('Processing license activation from deep link');
    await activateFromDeepLink(key);
  }

  /// Activate a license key received from a deep link.
  ///
  /// Attempts to verify with backend first. If server is unreachable,
  /// activates locally anyway (will verify on next periodic check).
  Future<void> activateFromDeepLink(String key) async {
    final usePhpVerification =
        BrandConfig.current.backendType == BackendType.php &&
        !PremiumLicenseService.isGoBackendLicenseKey(key);
    try {
      if (usePhpVerification) {
        final response = await _verifyPhpLicenseKey(key);
        if (!response.isValid) {
          appLogger.warning(
            'VidCombo PHP rejected deep link license: ${response.reason}',
          );
          _activationController.add(
            LicenseActivationResult(
              status: ActivationStatus.rejected,
              reason: response.reason,
            ),
          );
          return;
        }
        final billingCycle =
            response.billingCycle != null
                ? BillingCycle.fromString(response.billingCycle!)
                : null;
        await _activateViaNotifier(
          key,
          paymentMethod: 'deep_link',
          billingCycle: billingCycle,
          expiresAt: response.expiresAt,
        );
        _activationController.add(LicenseActivationResult.success);
        appLogger.info('License activated via deep link (PHP verified)');
        return;
      }

      // Try to verify with Go backend first
      final response = await _verificationService.verifyKey(key);

      if (response.isValid) {
        final billingCycle =
            response.billingCycle != null
                ? BillingCycle.fromString(response.billingCycle!)
                : null;
        await _activateViaNotifier(
          key,
          paymentMethod: 'deep_link',
          billingCycle: billingCycle,
          expiresAt: response.expiresAt,
        );
        appLogger.info('License activated via deep link (server verified)');
        _activationController.add(LicenseActivationResult.success);
      } else {
        appLogger.warning('License rejected by server: ${response.reason}');
        _activationController.add(
          LicenseActivationResult(
            status: ActivationStatus.rejected,
            reason: response.reason,
          ),
        );
      }
    } catch (e) {
      if (usePhpVerification) {
        appLogger.warning(
          'VidCombo PHP deep link activation could not be verified: $e',
        );
        try {
          await _activateViaNotifier(key, paymentMethod: 'deep_link');
          _activationController.add(LicenseActivationResult.successOffline);
        } catch (formatError) {
          _activationController.add(LicenseActivationResult.invalidKey);
        }
        return;
      }
      if (e is! NetworkException) {
        appLogger.warning(
          'Go deep link activation failed before server verification: $e',
        );
        _activationController.add(
          const LicenseActivationResult(status: ActivationStatus.rejected),
        );
        return;
      }

      // A 4xx from the Go backend is a DEFINITIVE server rejection (forged /
      // revoked / unknown key returns 404 from /premium/licenses/verify), not a
      // transport failure. Offline-activating on a 4xx would grant premium with
      // zero server confirmation (only the format regex gating it) — the
      // fail-open leak. Treat 4xx as rejected; ONLY a true transport failure
      // (AppException.network with no statusCode) may offline-activate. This
      // mirrors the manual-entry path, which is already not fail-open.
      final status = e.statusCode;
      if (status != null && status >= 400 && status < 500) {
        appLogger.warning(
          'Go backend rejected deep link license (HTTP $status) — '
          'refusing offline activation',
        );
        _activationController.add(
          const LicenseActivationResult(status: ActivationStatus.rejected),
        );
        return;
      }

      // Server unreachable — activate locally, will verify later
      appLogger.info(
        'Server unreachable during deep link activation, activating locally',
      );
      try {
        await _activateViaNotifier(key, paymentMethod: 'deep_link');
        _activationController.add(LicenseActivationResult.successOffline);
      } catch (formatError) {
        _activationController.add(LicenseActivationResult.invalidKey);
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    _activationController.close();
  }
}

Future<LicenseVerificationResponse> _verifyVidComboPhpLicenseKey(
  String key,
) async {
  final adapter = VidComboBackendAdapter();
  final result = await adapter.checkKey(licenseKey: key);
  return adapter.toLicenseVerification(result);
}

/// Status of a license activation attempt.
enum ActivationStatus { success, successOffline, invalidKey, rejected }

/// Result of a license activation from deep link.
class LicenseActivationResult {
  final ActivationStatus status;
  final String? reason;

  const LicenseActivationResult({required this.status, this.reason});

  static const success = LicenseActivationResult(
    status: ActivationStatus.success,
  );
  static const successOffline = LicenseActivationResult(
    status: ActivationStatus.successOffline,
  );
  static const invalidKey = LicenseActivationResult(
    status: ActivationStatus.invalidKey,
  );

  bool get isSuccess =>
      status == ActivationStatus.success ||
      status == ActivationStatus.successOffline;
}
