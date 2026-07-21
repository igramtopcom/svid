import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/premium/domain/entities/premium_tier.dart';

void main() {
  group('PremiumTier', () {
    test('has exactly 2 values', () {
      expect(PremiumTier.values.length, 2);
    });

    test('fromString parses valid values', () {
      expect(PremiumTier.fromString('free'), PremiumTier.free);
      expect(PremiumTier.fromString('premium'), PremiumTier.premium);
    });

    test('fromString defaults to free for unknown values', () {
      expect(PremiumTier.fromString('invalid'), PremiumTier.free);
      expect(PremiumTier.fromString(''), PremiumTier.free);
      expect(PremiumTier.fromString('PREMIUM'), PremiumTier.free);
    });
  });
}
