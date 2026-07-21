import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/payment_result.dart';
import 'package:svid/features/premium/domain/entities/payment_status.dart';

void main() {
  group('PaymentResult', () {
    test('isSuccess returns true when completed', () {
      final result = PaymentResult(
        status: PaymentStatus.completed,
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
      );
      expect(result.isSuccess, true);
      expect(result.isPending, false);
      expect(result.isFailed, false);
    });

    test(
      'completed without license key is awaiting license, not activatable',
      () {
        final result = PaymentResult(
          status: PaymentStatus.completed,
          paymentMethod: 'stripe',
          createdAt: DateTime(2026, 2, 28),
        );

        expect(result.isSuccess, true);
        expect(result.isAwaitingLicense, true);
        expect(result.isActivatable, false);
      },
    );

    test('isPending returns true when pending', () {
      final result = PaymentResult(
        status: PaymentStatus.pending,
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
      );
      expect(result.isPending, true);
      expect(result.isSuccess, false);
    });

    test('isFailed returns true when failed', () {
      final result = PaymentResult(
        status: PaymentStatus.failed,
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
        errorMessage: 'Card declined',
      );
      expect(result.isFailed, true);
    });

    test('fromJson creates correct instance', () {
      final json = {
        'status': 'completed',
        'sessionId': 'cs_test_123',
        'transactionId': 'pi_456',
        'licenseKey': 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        'paymentMethod': 'stripe',
        'createdAt': '2026-02-28T10:00:00.000Z',
      };

      final result = PaymentResult.fromJson(json);
      expect(result.status, PaymentStatus.completed);
      expect(result.sessionId, 'cs_test_123');
      expect(result.transactionId, 'pi_456');
      expect(
        result.licenseKey,
        'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(result.paymentMethod, 'stripe');
    });

    test('fromJson handles missing fields', () {
      final json = <String, dynamic>{'status': 'pending'};

      final result = PaymentResult.fromJson(json);
      expect(result.status, PaymentStatus.pending);
      expect(result.sessionId, isNull);
      expect(result.transactionId, isNull);
      expect(result.licenseKey, isNull);
      expect(result.paymentMethod, 'stripe'); // default
    });

    test('toJson produces correct map', () {
      final result = PaymentResult(
        status: PaymentStatus.completed,
        sessionId: 'cs_123',
        transactionId: 'pi_456',
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        paymentMethod: 'stripe',
        createdAt: DateTime.utc(2026, 2, 28, 10),
      );

      final json = result.toJson();
      expect(json['status'], 'completed');
      expect(json['sessionId'], 'cs_123');
      expect(json['transactionId'], 'pi_456');
      expect(
        json['licenseKey'],
        'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(json['paymentMethod'], 'stripe');
      expect(json['createdAt'], '2026-02-28T10:00:00.000Z');
    });

    test('toJson omits null fields', () {
      final result = PaymentResult(
        status: PaymentStatus.pending,
        paymentMethod: 'stripe',
        createdAt: DateTime.utc(2026, 2, 28),
      );

      final json = result.toJson();
      expect(json.containsKey('sessionId'), false);
      expect(json.containsKey('transactionId'), false);
      expect(json.containsKey('licenseKey'), false);
      expect(json.containsKey('errorMessage'), false);
    });

    test('equality works', () {
      final a = PaymentResult(
        status: PaymentStatus.completed,
        sessionId: 'cs_123',
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
      );
      final b = PaymentResult(
        status: PaymentStatus.completed,
        sessionId: 'cs_123',
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString is readable', () {
      final result = PaymentResult(
        status: PaymentStatus.pending,
        sessionId: 'cs_123',
        paymentMethod: 'stripe',
        createdAt: DateTime(2026, 2, 28),
      );
      expect(result.toString(), contains('pending'));
      expect(result.toString(), contains('stripe'));
      expect(result.toString(), contains('cs_123'));
    });
  });
}
