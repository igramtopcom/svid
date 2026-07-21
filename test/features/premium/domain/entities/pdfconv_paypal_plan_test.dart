import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_paypal_plan.dart';

void main() {
  test('catalog matches PDFConv PayPal V1 contract', () {
    expect(PdfConvPayPalPlan.catalogVersion, 'vidcombo-paypal-v1');
    expect(
      PdfConvPayPalPlan.plans
          .map(
            (plan) => (
              plan.id,
              plan.productName,
              plan.amountMinor,
              plan.currency,
              plan.entitlementDays,
            ),
          )
          .toList(),
      const [
        (PdfConvPlanId.p7, 'VidCombo Premium 7 Days', 1000, 'USD', 7),
        (PdfConvPlanId.p30, 'VidCombo Premium 30 Days', 1500, 'USD', 30),
        (PdfConvPlanId.p90, 'VidCombo Premium 90 Days', 2500, 'USD', 90),
        (
          PdfConvPlanId.lifetime,
          'VidCombo Premium Lifetime',
          4200,
          'USD',
          null,
        ),
      ],
    );
  });

  test('plan identifiers parse strictly', () {
    for (final plan in PdfConvPlanId.values) {
      expect(PdfConvPlanId.fromWireValue(plan.wireValue), plan);
    }

    expect(() => PdfConvPlanId.fromWireValue('monthly'), throwsFormatException);
    expect(() => PdfConvPlanId.fromWireValue('P7'), throwsFormatException);
  });

  test('lifetime is derived only from missing entitlement days', () {
    expect(PdfConvPayPalPlan.forId(PdfConvPlanId.p90).isLifetime, isFalse);
    expect(PdfConvPayPalPlan.forId(PdfConvPlanId.lifetime).isLifetime, isTrue);
  });
}
