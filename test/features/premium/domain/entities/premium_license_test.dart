import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';

void main() {
  group('BillingCycle', () {
    test('parses PDFConv plan IDs without falling back to monthly', () {
      expect(BillingCycle.fromString('p7'), BillingCycle.p7);
      expect(BillingCycle.fromString('p30'), BillingCycle.p30);
      expect(BillingCycle.fromString('p90'), BillingCycle.p90);
    });

    test('fixed-day PDFConv plans are not lifetime plans', () {
      expect(BillingCycle.p7.isLifetime, isFalse);
      expect(BillingCycle.p30.isLifetime, isFalse);
      expect(BillingCycle.p90.isLifetime, isFalse);
      expect(BillingCycle.lifetime.isLifetime, isTrue);
    });

    test('PDFConv plan IDs survive license JSON round trip', () {
      for (final cycle in [
        BillingCycle.p7,
        BillingCycle.p30,
        BillingCycle.p90,
      ]) {
        final original = PremiumLicense(
          tier: PremiumTier.premium,
          billingCycle: cycle,
        );

        final restored = PremiumLicense.fromJson(original.toJson());

        expect(restored.billingCycle, cycle);
      }
    });
  });

  group('PremiumLicense', () {
    test('default constructor creates free license', () {
      const license = PremiumLicense();
      expect(license.tier, PremiumTier.free);
      expect(license.licenseKey, isNull);
      expect(license.purchaseDate, isNull);
      expect(license.lastVerified, isNull);
      expect(license.isPremium, false);
      expect(license.isFree, true);
    });

    test('PremiumLicense.free is a free license', () {
      expect(PremiumLicense.free.tier, PremiumTier.free);
      expect(PremiumLicense.free.isPremium, false);
      expect(PremiumLicense.free.isFree, true);
    });

    test('isPremium returns true for premium tier', () {
      final license = PremiumLicense(tier: PremiumTier.premium);
      expect(license.isPremium, true);
      expect(license.isFree, false);
    });

    group('needsVerification', () {
      test('returns false for free tier', () {
        expect(PremiumLicense.free.needsVerification(), false);
      });

      test('returns true for premium without lastVerified', () {
        final license = PremiumLicense(tier: PremiumTier.premium);
        expect(license.needsVerification(), true);
      });

      test('returns false when verified less than 7 days ago', () {
        final now = DateTime(2026, 3, 1);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          lastVerified: DateTime(2026, 2, 25), // 4 days ago
        );
        expect(license.needsVerification(now: now), false);
      });

      test('returns true when verified 7+ days ago', () {
        final now = DateTime(2026, 3, 1);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          lastVerified: DateTime(2026, 2, 20), // 9 days ago
        );
        expect(license.needsVerification(now: now), true);
      });

      test('returns true when verified exactly 7 days ago', () {
        final now = DateTime(2026, 3, 1);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          lastVerified: DateTime(2026, 2, 22), // 7 days
        );
        expect(license.needsVerification(now: now), true);
      });
    });

    group('isWithinGracePeriod', () {
      test('returns false for free tier', () {
        expect(PremiumLicense.free.isWithinGracePeriod(), false);
      });

      test('returns false when lastVerified is null', () {
        final license = PremiumLicense(tier: PremiumTier.premium);
        expect(license.isWithinGracePeriod(), false);
      });

      test('returns true when within 30 days', () {
        final now = DateTime(2026, 3, 1);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          lastVerified: DateTime(2026, 2, 10), // 19 days ago
        );
        expect(license.isWithinGracePeriod(now: now), true);
      });

      test('returns false when beyond 30 days', () {
        final now = DateTime(2026, 3, 1);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          lastVerified: DateTime(2026, 1, 15), // 45 days ago
        );
        expect(license.isWithinGracePeriod(now: now), false);
      });
    });

    group('copyWith', () {
      test('copies with new tier', () {
        final license = PremiumLicense.free.copyWith(tier: PremiumTier.premium);
        expect(license.tier, PremiumTier.premium);
      });

      test('clears nullable fields', () {
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          licenseKey: 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
          paymentMethod: 'stripe',
        );
        final cleared = license.copyWith(
          clearLicenseKey: true,
          clearPaymentMethod: true,
        );
        expect(cleared.licenseKey, isNull);
        expect(cleared.paymentMethod, isNull);
        expect(cleared.tier, PremiumTier.premium);
      });
    });

    group('toJson / fromJson', () {
      test('round-trip serialization for free license', () {
        const original = PremiumLicense();
        final json = original.toJson();
        final restored = PremiumLicense.fromJson(json);
        expect(restored.tier, PremiumTier.free);
      });

      test('round-trip serialization for premium license', () {
        final now = DateTime(2026, 2, 28, 12, 0, 0);
        final original = PremiumLicense(
          tier: PremiumTier.premium,
          purchaseDate: now,
          lastVerified: now,
          paymentMethod: 'stripe',
          transactionId: 'pi_123abc',
        );
        final json = original.toJson();
        final restored = PremiumLicense.fromJson(json);
        expect(restored.tier, PremiumTier.premium);
        expect(restored.purchaseDate, now);
        expect(restored.lastVerified, now);
        expect(restored.paymentMethod, 'stripe');
        expect(restored.transactionId, 'pi_123abc');
      });

      test('fromJson handles empty/null gracefully', () {
        final license = PremiumLicense.fromJson({});
        expect(license.tier, PremiumTier.free);
        expect(license.purchaseDate, isNull);
      });

      test('toJson omits null fields', () {
        final json = PremiumLicense.free.toJson();
        expect(json.containsKey('purchaseDate'), false);
        expect(json.containsKey('lastVerified'), false);
        expect(json.containsKey('paymentMethod'), false);
        expect(json.containsKey('transactionId'), false);
        expect(json['tier'], 'free');
      });
    });

    group('equality', () {
      test('equal licenses are equal', () {
        const a = PremiumLicense();
        const b = PremiumLicense();
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('different tiers are not equal', () {
        const a = PremiumLicense();
        final b = PremiumLicense(tier: PremiumTier.premium);
        expect(a, isNot(b));
      });
    });

    test('toString masks license key', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(license.toString(), contains('***'));
      expect(license.toString(), isNot(contains('1234')));
    });

    test('toString shows null for no key', () {
      const license = PremiumLicense();
      expect(license.toString(), contains('null'));
    });
  });
}
