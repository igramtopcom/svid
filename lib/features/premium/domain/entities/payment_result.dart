import 'payment_status.dart';

/// Result of a payment transaction (Stripe or Crypto).
class PaymentResult {
  final PaymentStatus status;
  final String? sessionId;
  final String? transactionId;
  final String? licenseKey;
  final String? errorMessage;
  final String paymentMethod; // 'stripe' | 'crypto'
  final DateTime createdAt;
  final String? billingCycle; // 'monthly' | 'yearly'
  final DateTime? expiresAt;

  const PaymentResult({
    required this.status,
    this.sessionId,
    this.transactionId,
    this.licenseKey,
    this.errorMessage,
    required this.paymentMethod,
    required this.createdAt,
    this.billingCycle,
    this.expiresAt,
  });

  bool get isSuccess => status == PaymentStatus.completed;
  bool get isPending => status == PaymentStatus.pending;
  bool get isFailed => status == PaymentStatus.failed;
  bool get hasLicenseKey => licenseKey != null && licenseKey!.isNotEmpty;
  bool get isActivatable => isSuccess && hasLicenseKey;

  /// Stripe can be paid before the backend can resolve/link the license row.
  /// Treat completed-without-key as still awaiting a license, not as a dead
  /// session, so the recovery marker survives and the user can re-check later.
  bool get isAwaitingLicense => isSuccess && !hasLicenseKey;

  /// Create from backend JSON response.
  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    return PaymentResult(
      status: PaymentStatus.fromString(json['status'] as String?),
      sessionId: json['sessionId'] as String?,
      transactionId: json['transactionId'] as String?,
      licenseKey: json['licenseKey'] as String?,
      errorMessage: json['errorMessage'] as String?,
      paymentMethod: json['paymentMethod'] as String? ?? 'stripe',
      createdAt:
          json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.now(),
      billingCycle: json['billingCycle'] as String?,
      expiresAt:
          json['expiresAt'] != null
              ? DateTime.tryParse(json['expiresAt'] as String)
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (sessionId != null) 'sessionId': sessionId,
    if (transactionId != null) 'transactionId': transactionId,
    if (licenseKey != null) 'licenseKey': licenseKey,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'paymentMethod': paymentMethod,
    'createdAt': createdAt.toIso8601String(),
    if (billingCycle != null) 'billingCycle': billingCycle,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          sessionId == other.sessionId &&
          transactionId == other.transactionId &&
          licenseKey == other.licenseKey &&
          paymentMethod == other.paymentMethod &&
          billingCycle == other.billingCycle &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(
    status,
    sessionId,
    transactionId,
    licenseKey,
    paymentMethod,
    billingCycle,
    expiresAt,
  );

  @override
  String toString() =>
      'PaymentResult(status: $status, method: $paymentMethod, '
      'cycle: ${billingCycle ?? "n/a"}, '
      'session: ${sessionId ?? "none"})';
}
