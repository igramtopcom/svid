/// Pricing plan info from backend.
///
/// Used to display prices on the billing cycle selector before checkout.
/// Falls back to hardcoded values when the backend is unreachable.
class PricingPlan {
  final String billingCycle;
  final int amountCents;
  final String currency;
  final String interval;
  final int maxDevices;
  final bool isLifetime;

  const PricingPlan({
    required this.billingCycle,
    required this.amountCents,
    required this.currency,
    required this.interval,
    required this.maxDevices,
    required this.isLifetime,
  });

  String get displayPrice {
    final amount = amountCents / 100;
    final symbol = currencySymbol;
    if (amount == amount.roundToDouble()) {
      return '$symbol${amount.toInt()}';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  /// Currency symbol derived from the currency code.
  String get currencySymbol => switch (currency.toLowerCase()) {
        'usd' => '\$',
        'eur' => '€',
        'gbp' => '£',
        'jpy' || 'cny' => '¥',
        'krw' => '₩',
        'inr' => '₹',
        'brl' => 'R\$',
        'vnd' => '₫',
        _ => '${currency.toUpperCase()} ',
      };

  String get priceLabel {
    switch (interval) {
      case 'month':
        return '$displayPrice/mo';
      case 'six_months':
        return '$displayPrice/6mo';
      case 'year':
        return '$displayPrice/yr';
      default:
        return displayPrice;
    }
  }

  factory PricingPlan.fromJson(Map<String, dynamic> json) {
    return PricingPlan(
      billingCycle: json['billingCycle'] as String,
      amountCents: json['amountCents'] as int,
      currency: json['currency'] as String? ?? 'usd',
      interval: json['interval'] as String,
      maxDevices: json['maxDevices'] as int,
      isLifetime: json['isLifetime'] as bool? ?? false,
    );
  }
}
