/// Stable plan identifiers from the PDFConv PayPal catalog.
enum PdfConvPlanId {
  p7('p7'),
  p30('p30'),
  p90('p90'),
  lifetime('lifetime');

  const PdfConvPlanId(this.wireValue);

  final String wireValue;

  static PdfConvPlanId fromWireValue(String value) {
    return PdfConvPlanId.values.firstWhere(
      (plan) => plan.wireValue == value,
      orElse: () => throw FormatException('Unknown PDFConv plan ID: $value'),
    );
  }
}

/// Immutable client snapshot of the PDFConv PayPal V1 catalog.
class PdfConvPayPalPlan {
  static const catalogVersion = 'vidcombo-paypal-v1';
  static const currencyUsd = 'USD';

  final PdfConvPlanId id;
  final String productName;
  final int amountMinor;
  final String currency;
  final int? entitlementDays;

  const PdfConvPayPalPlan({
    required this.id,
    required this.productName,
    required this.amountMinor,
    this.currency = currencyUsd,
    required this.entitlementDays,
  });

  bool get isLifetime => entitlementDays == null;

  static const plans = <PdfConvPayPalPlan>[
    PdfConvPayPalPlan(
      id: PdfConvPlanId.p7,
      productName: 'VidCombo Premium 7 Days',
      amountMinor: 1000,
      entitlementDays: 7,
    ),
    PdfConvPayPalPlan(
      id: PdfConvPlanId.p30,
      productName: 'VidCombo Premium 30 Days',
      amountMinor: 1500,
      entitlementDays: 30,
    ),
    PdfConvPayPalPlan(
      id: PdfConvPlanId.p90,
      productName: 'VidCombo Premium 90 Days',
      amountMinor: 2500,
      entitlementDays: 90,
    ),
    PdfConvPayPalPlan(
      id: PdfConvPlanId.lifetime,
      productName: 'VidCombo Premium Lifetime',
      amountMinor: 4200,
      entitlementDays: null,
    ),
  ];

  static PdfConvPayPalPlan forId(PdfConvPlanId id) {
    return plans.firstWhere((plan) => plan.id == id);
  }
}
