import 'crypto_currency.dart';

/// Represents a BTCPay Server invoice for crypto payment.
class CryptoInvoice {
  /// BTCPay invoice ID.
  final String invoiceId;

  /// Selected cryptocurrency.
  final CryptoCurrency currency;

  /// Crypto amount to pay (e.g., 0.00045 BTC).
  final String amount;

  /// Wallet address to send payment to.
  final String address;

  /// Payment URI for QR code (e.g., bitcoin:addr?amount=0.00045).
  final String paymentUri;

  /// Current blockchain confirmations (0 = unconfirmed).
  final int confirmations;

  /// When this invoice expires (typically 15-30 minutes).
  final DateTime expiresAt;

  /// When this invoice was created.
  final DateTime createdAt;

  const CryptoInvoice({
    required this.invoiceId,
    required this.currency,
    required this.amount,
    required this.address,
    required this.paymentUri,
    this.confirmations = 0,
    required this.expiresAt,
    required this.createdAt,
  });

  /// Whether the invoice has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Whether the invoice has enough confirmations.
  bool get isConfirmed => confirmations >= currency.requiredConfirmations;

  /// Remaining time until expiry.
  Duration get timeRemaining {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Create from backend JSON response.
  factory CryptoInvoice.fromJson(Map<String, dynamic> json) {
    return CryptoInvoice(
      invoiceId: json['invoiceId'] as String,
      currency: CryptoCurrency.fromString(json['currency'] as String?),
      amount: json['amount'] as String,
      address: json['address'] as String,
      paymentUri: json['paymentUri'] as String,
      confirmations: json['confirmations'] as int? ?? 0,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'invoiceId': invoiceId,
        'currency': currency.symbol,
        'amount': amount,
        'address': address,
        'paymentUri': paymentUri,
        'confirmations': confirmations,
        'expiresAt': expiresAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptoInvoice &&
          runtimeType == other.runtimeType &&
          invoiceId == other.invoiceId &&
          currency == other.currency &&
          address == other.address;

  @override
  int get hashCode => Object.hash(invoiceId, currency, address);

  @override
  String toString() =>
      'CryptoInvoice(id: $invoiceId, ${currency.symbol} $amount, '
      'confirmations: $confirmations/${currency.requiredConfirmations})';
}
