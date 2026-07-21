import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/backend_client.dart';
import '../../domain/entities/crypto_currency.dart';
import '../../domain/entities/crypto_invoice.dart';
import '../../domain/entities/payment_result.dart';
import '../../domain/entities/payment_status.dart';

/// Service for handling BTCPay Server crypto payment flow.
///
/// Flow:
/// 1. App calls backend → creates BTCPay invoice (BTC/LTC/XMR)
/// 2. Backend returns invoice with wallet address + amount
/// 3. App displays QR code + address for user to pay
/// 4. User sends crypto from their wallet
/// 5. App polls backend for confirmation count
/// 6. Once confirmed (BTC:1, LTC:3, XMR:10), backend issues license key
///
/// Security: NO private keys in Flutter app. BTCPay Server is self-hosted.
class CryptoPaymentService {
  final BackendClient _client;
  final Uuid _uuid;

  /// Injectable for testing. Production uses real [BackendClient].
  CryptoPaymentService(this._client, [Uuid? uuid])
      : _uuid = uuid ?? const Uuid();

  /// Create a BTCPay invoice for the selected cryptocurrency.
  ///
  /// [currency] specifies which crypto to pay with (BTC/LTC/XMR).
  /// [billingCycle] specifies 'monthly' or 'yearly' subscription.
  /// [idempotencyKey] prevents duplicate invoices on retry.
  /// Returns [CryptoInvoice] with wallet address and payment URI.
  Future<CryptoInvoice> createInvoice({
    required CryptoCurrency currency,
    required String billingCycle,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    appLogger.info(
      'Creating ${currency.symbol} invoice '
      '(cycle: $billingCycle, idempotency: $key)',
    );

    final invoice = await _client.post<CryptoInvoice>(
      '/premium/crypto/invoice',
      data: {
        'currency': currency.symbol,
        'billingCycle': billingCycle,
        'idempotencyKey': key,
      },
      fromJson: (json) =>
          CryptoInvoice.fromJson(json as Map<String, dynamic>),
    );

    appLogger.info(
      'Invoice created: ${invoice.invoiceId} '
      '(${invoice.currency.symbol} ${invoice.amount})',
    );
    return invoice;
  }

  /// Check the current status of a crypto invoice.
  ///
  /// Returns [PaymentResult] with confirmation count and license key
  /// when fully confirmed.
  Future<PaymentResult> checkInvoiceStatus(String invoiceId) async {
    appLogger.info('Checking invoice status: $invoiceId');

    final result = await _client.get<PaymentResult>(
      '/premium/crypto/status',
      queryParameters: {'invoiceId': invoiceId},
      fromJson: (json) =>
          PaymentResult.fromJson(json as Map<String, dynamic>),
    );

    if (result.isSuccess) {
      appLogger.info(
        'Invoice confirmed! License: '
        '${result.licenseKey != null ? "***" : "none"}',
      );
    } else if (result.isPending) {
      appLogger.debug('Invoice pending confirmation');
    } else {
      appLogger.warning('Invoice status: ${result.status}');
    }

    return result;
  }

  /// Poll for crypto payment confirmation with exponential backoff.
  ///
  /// Crypto confirmations take longer than card payments:
  /// - BTC: ~10 min per block (1 confirmation)
  /// - LTC: ~2.5 min per block (3 confirmations)
  /// - XMR: ~2 min per block (10 confirmations)
  ///
  /// Polls every [initialDelay], doubling up to [maxDelay].
  /// Stops after [maxAttempts] or when status is no longer pending.
  Future<PaymentResult> pollForConfirmation(
    String invoiceId, {
    Duration initialDelay = const Duration(seconds: 5),
    Duration maxDelay = const Duration(seconds: 30),
    int maxAttempts = 120,
  }) async {
    var delay = initialDelay;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(delay);

      final result = await checkInvoiceStatus(invoiceId);

      if (!result.isPending) {
        return result;
      }

      // Exponential backoff
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 1.5).toInt().clamp(
              initialDelay.inMilliseconds,
              maxDelay.inMilliseconds,
            ),
      );
    }

    // Timed out waiting for confirmation
    return PaymentResult(
      status: PaymentStatus.pending,
      transactionId: invoiceId,
      paymentMethod: 'crypto',
      createdAt: DateTime.now(),
      errorMessage: 'Payment confirmation timed out',
    );
  }
}
