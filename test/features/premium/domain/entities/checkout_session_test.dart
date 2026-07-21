import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/premium/domain/entities/checkout_session.dart';

void main() {
  group('CheckoutSession', () {
    test('fromJson creates correct instance', () {
      final json = {
        'sessionId': 'cs_test_abc123',
        'checkoutUrl': 'https://checkout.stripe.com/pay/cs_test_abc123',
        'expiresAt': '2026-02-28T11:00:00.000Z',
      };

      final session = CheckoutSession.fromJson(json);
      expect(session.sessionId, 'cs_test_abc123');
      expect(session.checkoutUrl,
          'https://checkout.stripe.com/pay/cs_test_abc123');
      expect(session.expiresAt, DateTime.utc(2026, 2, 28, 11));
    });

    test('isExpired returns true for past dates', () {
      final session = CheckoutSession(
        sessionId: 'cs_old',
        checkoutUrl: 'https://example.com',
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(session.isExpired, true);
    });

    test('isExpired returns false for future dates', () {
      final session = CheckoutSession(
        sessionId: 'cs_new',
        checkoutUrl: 'https://example.com',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(session.isExpired, false);
    });

    test('toString is readable', () {
      final session = CheckoutSession(
        sessionId: 'cs_test_123',
        checkoutUrl: 'https://example.com',
        expiresAt: DateTime(2020, 1, 1),
      );
      expect(session.toString(), contains('cs_test_123'));
    });
  });
}
