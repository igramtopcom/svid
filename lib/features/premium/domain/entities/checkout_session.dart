/// Represents a Stripe Checkout session created by the backend.
class CheckoutSession {
  /// Stripe checkout session ID.
  final String sessionId;

  /// URL to redirect user to Stripe hosted payment page.
  final String checkoutUrl;

  /// When this session expires (typically 30 minutes).
  final DateTime expiresAt;

  const CheckoutSession({
    required this.sessionId,
    required this.checkoutUrl,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    return CheckoutSession(
      sessionId: json['sessionId'] as String,
      checkoutUrl: json['checkoutUrl'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }

  @override
  String toString() =>
      'CheckoutSession(id: $sessionId, expired: $isExpired)';
}
