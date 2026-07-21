/// Status of a payment transaction.
enum PaymentStatus {
  /// Payment session created, awaiting user action.
  pending,

  /// Payment completed successfully.
  completed,

  /// Payment failed (declined, expired, etc.).
  failed,

  /// Payment was cancelled by the user.
  cancelled;

  /// Parse from string, defaults to [pending].
  static PaymentStatus fromString(String? value) {
    return PaymentStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => PaymentStatus.pending,
    );
  }
}
