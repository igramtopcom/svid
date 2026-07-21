/// A completed payment transaction from the backend.
///
/// Returned by `GET /api/v1/premium/transactions`.
class PaymentTransaction {
  final String id;
  final String paymentMethod;
  final String billingCycle;
  final int amountCents;
  final String currency;
  final String status;
  final DateTime? completedAt;
  final DateTime createdAt;

  const PaymentTransaction({
    required this.id,
    required this.paymentMethod,
    required this.billingCycle,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.completedAt,
    required this.createdAt,
  });

  /// Format amount for display (e.g. "$7.99").
  String get displayAmount {
    final amount = amountCents / 100;
    final symbol = _currencySymbol;
    if (amount == amount.roundToDouble()) {
      return '$symbol${amount.toInt()}';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  String get _currencySymbol => switch (currency.toLowerCase()) {
        'usd' => '\$',
        'eur' => '\u20AC',
        'gbp' => '\u00A3',
        'jpy' || 'cny' => '\u00A5',
        _ => '${currency.toUpperCase()} ',
      };

  bool get isCompleted => status == 'completed';

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'] as String? ?? '',
      paymentMethod: json['payment_method'] as String? ?? 'stripe',
      billingCycle: json['billing_cycle'] as String? ?? '',
      amountCents: json['amount_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'usd',
      status: json['status'] as String? ?? 'pending',
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  static List<PaymentTransaction> listFromJson(dynamic json) {
    if (json is! List) return [];
    return json
        .map((e) => PaymentTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
