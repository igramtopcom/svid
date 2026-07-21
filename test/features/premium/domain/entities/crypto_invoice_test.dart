import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/crypto_currency.dart';
import 'package:svid/features/premium/domain/entities/crypto_invoice.dart';

void main() {
  group('CryptoInvoice', () {
    CryptoInvoice createInvoice({
      String invoiceId = 'inv_test_123',
      CryptoCurrency currency = CryptoCurrency.btc,
      String amount = '0.00045',
      String address = 'bc1qtest123',
      String paymentUri = 'bitcoin:bc1qtest123?amount=0.00045',
      int confirmations = 0,
      DateTime? expiresAt,
      DateTime? createdAt,
    }) {
      return CryptoInvoice(
        invoiceId: invoiceId,
        currency: currency,
        amount: amount,
        address: address,
        paymentUri: paymentUri,
        confirmations: confirmations,
        expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
        createdAt: createdAt ?? DateTime.now(),
      );
    }

    test('fromJson creates correct instance', () {
      final json = {
        'invoiceId': 'inv_btc_456',
        'currency': 'BTC',
        'amount': '0.00045',
        'address': 'bc1qxyz789',
        'paymentUri': 'bitcoin:bc1qxyz789?amount=0.00045',
        'confirmations': 1,
        'expiresAt': '2026-02-28T12:00:00.000Z',
        'createdAt': '2026-02-28T11:45:00.000Z',
      };

      final invoice = CryptoInvoice.fromJson(json);
      expect(invoice.invoiceId, 'inv_btc_456');
      expect(invoice.currency, CryptoCurrency.btc);
      expect(invoice.amount, '0.00045');
      expect(invoice.address, 'bc1qxyz789');
      expect(invoice.paymentUri, 'bitcoin:bc1qxyz789?amount=0.00045');
      expect(invoice.confirmations, 1);
      expect(invoice.expiresAt, DateTime.utc(2026, 2, 28, 12));
    });

    test('fromJson handles LTC currency', () {
      final json = {
        'invoiceId': 'inv_ltc_789',
        'currency': 'LTC',
        'amount': '0.15',
        'address': 'ltc1qtest',
        'paymentUri': 'litecoin:ltc1qtest?amount=0.15',
        'expiresAt': '2026-02-28T12:00:00.000Z',
      };

      final invoice = CryptoInvoice.fromJson(json);
      expect(invoice.currency, CryptoCurrency.ltc);
      expect(invoice.confirmations, 0); // default
    });

    test('fromJson handles XMR currency', () {
      final json = {
        'invoiceId': 'inv_xmr_abc',
        'currency': 'XMR',
        'amount': '0.5',
        'address': '4xmraddress',
        'paymentUri': 'monero:4xmraddress?tx_amount=0.5',
        'expiresAt': '2026-02-28T12:00:00.000Z',
      };

      final invoice = CryptoInvoice.fromJson(json);
      expect(invoice.currency, CryptoCurrency.xmr);
    });

    test('isExpired returns true for past dates', () {
      final invoice = createInvoice(
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(invoice.isExpired, true);
    });

    test('isExpired returns false for future dates', () {
      final invoice = createInvoice(
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(invoice.isExpired, false);
    });

    test('isConfirmed checks against required confirmations for BTC', () {
      expect(createInvoice(confirmations: 0).isConfirmed, false);
      expect(createInvoice(confirmations: 1).isConfirmed, true);
      expect(createInvoice(confirmations: 3).isConfirmed, true);
    });

    test('isConfirmed checks against required confirmations for LTC', () {
      final ltcInvoice = createInvoice(
        currency: CryptoCurrency.ltc,
        confirmations: 2,
      );
      expect(ltcInvoice.isConfirmed, false);

      final ltcConfirmed = createInvoice(
        currency: CryptoCurrency.ltc,
        confirmations: 3,
      );
      expect(ltcConfirmed.isConfirmed, true);
    });

    test('isConfirmed checks against required confirmations for XMR', () {
      final xmrInvoice = createInvoice(
        currency: CryptoCurrency.xmr,
        confirmations: 9,
      );
      expect(xmrInvoice.isConfirmed, false);

      final xmrConfirmed = createInvoice(
        currency: CryptoCurrency.xmr,
        confirmations: 10,
      );
      expect(xmrConfirmed.isConfirmed, true);
    });

    test('timeRemaining returns positive duration for future expiry', () {
      final invoice = createInvoice(
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      expect(invoice.timeRemaining.inMinutes, greaterThanOrEqualTo(9));
    });

    test('timeRemaining returns zero for past expiry', () {
      final invoice = createInvoice(
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(invoice.timeRemaining, Duration.zero);
    });

    test('toJson produces correct map', () {
      final invoice = CryptoInvoice(
        invoiceId: 'inv_123',
        currency: CryptoCurrency.btc,
        amount: '0.00045',
        address: 'bc1qtest',
        paymentUri: 'bitcoin:bc1qtest?amount=0.00045',
        confirmations: 1,
        expiresAt: DateTime.utc(2026, 2, 28, 12),
        createdAt: DateTime.utc(2026, 2, 28, 11, 45),
      );

      final json = invoice.toJson();
      expect(json['invoiceId'], 'inv_123');
      expect(json['currency'], 'BTC');
      expect(json['amount'], '0.00045');
      expect(json['address'], 'bc1qtest');
      expect(json['paymentUri'], 'bitcoin:bc1qtest?amount=0.00045');
      expect(json['confirmations'], 1);
      expect(json['expiresAt'], '2026-02-28T12:00:00.000Z');
      expect(json['createdAt'], '2026-02-28T11:45:00.000Z');
    });

    test('equality works by invoiceId, currency, address', () {
      final a = createInvoice(
        invoiceId: 'inv_123',
        currency: CryptoCurrency.btc,
        address: 'bc1qtest',
      );
      final b = createInvoice(
        invoiceId: 'inv_123',
        currency: CryptoCurrency.btc,
        address: 'bc1qtest',
        confirmations: 2, // different confirmations
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality for different invoiceId', () {
      final a = createInvoice(invoiceId: 'inv_123');
      final b = createInvoice(invoiceId: 'inv_456');
      expect(a, isNot(equals(b)));
    });

    test('toString is readable', () {
      final invoice = createInvoice(
        invoiceId: 'inv_test',
        amount: '0.00045',
        confirmations: 1,
      );
      expect(invoice.toString(), contains('inv_test'));
      expect(invoice.toString(), contains('BTC'));
      expect(invoice.toString(), contains('0.00045'));
      expect(invoice.toString(), contains('1/1'));
    });
  });
}
