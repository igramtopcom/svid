import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/premium/domain/entities/payment_status.dart';

void main() {
  group('PaymentStatus', () {
    test('has 4 values', () {
      expect(PaymentStatus.values.length, 4);
    });

    test('fromString returns correct status', () {
      expect(PaymentStatus.fromString('pending'), PaymentStatus.pending);
      expect(PaymentStatus.fromString('completed'), PaymentStatus.completed);
      expect(PaymentStatus.fromString('failed'), PaymentStatus.failed);
      expect(PaymentStatus.fromString('cancelled'), PaymentStatus.cancelled);
    });

    test('fromString returns pending for unknown values', () {
      expect(PaymentStatus.fromString('unknown'), PaymentStatus.pending);
      expect(PaymentStatus.fromString(null), PaymentStatus.pending);
      expect(PaymentStatus.fromString(''), PaymentStatus.pending);
    });
  });
}
