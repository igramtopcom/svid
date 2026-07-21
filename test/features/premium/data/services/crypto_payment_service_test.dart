import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/crypto_currency.dart';
import 'package:svid/features/premium/domain/entities/crypto_invoice.dart';
import 'package:svid/features/premium/domain/entities/payment_result.dart';
import 'package:svid/features/premium/domain/entities/payment_status.dart';

void main() {
  group('CryptoPaymentService integration', () {
    group('CryptoInvoice fromJson (simulates backend response)', () {
      test('parses BTC invoice from backend', () {
        final json = {
          'invoiceId': 'inv_btc_123',
          'currency': 'BTC',
          'amount': '0.00045',
          'address': 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          'paymentUri':
              'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4?amount=0.00045',
          'confirmations': 0,
          'expiresAt': '2026-02-28T12:00:00.000Z',
          'createdAt': '2026-02-28T11:45:00.000Z',
        };

        final invoice = CryptoInvoice.fromJson(json);
        expect(invoice.invoiceId, 'inv_btc_123');
        expect(invoice.currency, CryptoCurrency.btc);
        expect(invoice.amount, '0.00045');
        expect(invoice.address,
            'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
        expect(invoice.confirmations, 0);
        expect(invoice.isConfirmed, false);
      });

      test('parses LTC invoice from backend', () {
        final json = {
          'invoiceId': 'inv_ltc_456',
          'currency': 'LTC',
          'amount': '0.15',
          'address': 'ltc1qtest789',
          'paymentUri': 'litecoin:ltc1qtest789?amount=0.15',
          'expiresAt': '2026-02-28T12:00:00.000Z',
        };

        final invoice = CryptoInvoice.fromJson(json);
        expect(invoice.currency, CryptoCurrency.ltc);
        expect(invoice.confirmations, 0); // default
        expect(invoice.isConfirmed, false);
      });

      test('parses XMR invoice from backend', () {
        final json = {
          'invoiceId': 'inv_xmr_789',
          'currency': 'XMR',
          'amount': '0.5',
          'address': '4xmraddresstest',
          'paymentUri': 'monero:4xmraddresstest?tx_amount=0.5',
          'expiresAt': '2026-02-28T12:00:00.000Z',
        };

        final invoice = CryptoInvoice.fromJson(json);
        expect(invoice.currency, CryptoCurrency.xmr);
        expect(invoice.isConfirmed, false);
      });
    });

    group('PaymentResult for crypto (simulates status check)', () {
      test('pending result for unconfirmed crypto', () {
        final json = {
          'status': 'pending',
          'paymentMethod': 'crypto',
          'createdAt': '2026-02-28T12:00:00.000Z',
        };

        final result = PaymentResult.fromJson(json);
        expect(result.isPending, true);
        expect(result.isSuccess, false);
        expect(result.paymentMethod, 'crypto');
        expect(result.licenseKey, isNull);
      });

      test('completed result with license key', () {
        final json = {
          'status': 'completed',
          'transactionId': 'tx_btc_abc123',
          'licenseKey': 'SVID-c4f0-1234-5678-9abc-def0-1234-5678-9abc',
          'paymentMethod': 'crypto',
          'createdAt': '2026-02-28T12:00:00.000Z',
        };

        final result = PaymentResult.fromJson(json);
        expect(result.isSuccess, true);
        expect(result.transactionId, 'tx_btc_abc123');
        expect(result.licenseKey, 'SVID-c4f0-1234-5678-9abc-def0-1234-5678-9abc');
        expect(result.paymentMethod, 'crypto');
      });

      test('failed result for expired invoice', () {
        final json = {
          'status': 'failed',
          'errorMessage': 'Invoice expired',
          'paymentMethod': 'crypto',
          'createdAt': '2026-02-28T12:00:00.000Z',
        };

        final result = PaymentResult.fromJson(json);
        expect(result.isFailed, true);
        expect(result.errorMessage, 'Invoice expired');
      });

      test('timeout result from polling', () {
        final result = PaymentResult(
          status: PaymentStatus.pending,
          transactionId: 'inv_timeout',
          paymentMethod: 'crypto',
          createdAt: DateTime.now(),
          errorMessage: 'Payment confirmation timed out',
        );

        expect(result.isPending, true);
        expect(result.errorMessage, contains('timed out'));
        expect(result.paymentMethod, 'crypto');
      });
    });

    group('Invoice expiry tracking', () {
      test('invoice expiry countdown', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_test',
          currency: CryptoCurrency.btc,
          amount: '0.00045',
          address: 'bc1qtest',
          paymentUri: 'bitcoin:bc1qtest?amount=0.00045',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );

        expect(invoice.isExpired, false);
        expect(invoice.timeRemaining.inMinutes, greaterThanOrEqualTo(14));
      });

      test('expired invoice', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_expired',
          currency: CryptoCurrency.btc,
          amount: '0.00045',
          address: 'bc1qtest',
          paymentUri: 'bitcoin:bc1qtest?amount=0.00045',
          expiresAt: DateTime(2020, 1, 1),
          createdAt: DateTime(2020, 1, 1),
        );

        expect(invoice.isExpired, true);
        expect(invoice.timeRemaining, Duration.zero);
      });
    });

    group('Confirmation tracking', () {
      test('BTC: 0/1 confirmations = not confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_btc',
          currency: CryptoCurrency.btc,
          amount: '0.00045',
          address: 'bc1qtest',
          paymentUri: 'bitcoin:bc1qtest?amount=0.00045',
          confirmations: 0,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, false);
      });

      test('BTC: 1/1 confirmations = confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_btc',
          currency: CryptoCurrency.btc,
          amount: '0.00045',
          address: 'bc1qtest',
          paymentUri: 'bitcoin:bc1qtest?amount=0.00045',
          confirmations: 1,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, true);
      });

      test('LTC: 2/3 confirmations = not confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_ltc',
          currency: CryptoCurrency.ltc,
          amount: '0.15',
          address: 'ltc1qtest',
          paymentUri: 'litecoin:ltc1qtest?amount=0.15',
          confirmations: 2,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, false);
      });

      test('LTC: 3/3 confirmations = confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_ltc',
          currency: CryptoCurrency.ltc,
          amount: '0.15',
          address: 'ltc1qtest',
          paymentUri: 'litecoin:ltc1qtest?amount=0.15',
          confirmations: 3,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, true);
      });

      test('XMR: 9/10 confirmations = not confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_xmr',
          currency: CryptoCurrency.xmr,
          amount: '0.5',
          address: '4xmrtest',
          paymentUri: 'monero:4xmrtest?tx_amount=0.5',
          confirmations: 9,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, false);
      });

      test('XMR: 10/10 confirmations = confirmed', () {
        final invoice = CryptoInvoice(
          invoiceId: 'inv_xmr',
          currency: CryptoCurrency.xmr,
          amount: '0.5',
          address: '4xmrtest',
          paymentUri: 'monero:4xmrtest?tx_amount=0.5',
          confirmations: 10,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          createdAt: DateTime.now(),
        );
        expect(invoice.isConfirmed, true);
      });
    });

    group('Invoice serialization round-trip', () {
      test('toJson → fromJson preserves all fields', () {
        final original = CryptoInvoice(
          invoiceId: 'inv_round_trip',
          currency: CryptoCurrency.ltc,
          amount: '0.15',
          address: 'ltc1qroundtrip',
          paymentUri: 'litecoin:ltc1qroundtrip?amount=0.15',
          confirmations: 2,
          expiresAt: DateTime.utc(2026, 3, 1, 12),
          createdAt: DateTime.utc(2026, 3, 1, 11, 45),
        );

        final json = original.toJson();
        final restored = CryptoInvoice.fromJson(json);

        expect(restored.invoiceId, original.invoiceId);
        expect(restored.currency, original.currency);
        expect(restored.amount, original.amount);
        expect(restored.address, original.address);
        expect(restored.paymentUri, original.paymentUri);
        expect(restored.confirmations, original.confirmations);
        expect(restored.expiresAt, original.expiresAt);
        expect(restored.createdAt, original.createdAt);
      });
    });
  });
}
