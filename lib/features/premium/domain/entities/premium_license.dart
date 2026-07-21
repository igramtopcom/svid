import 'premium_tier.dart';

/// Billing cycle for premium subscriptions
enum BillingCycle {
  monthly,
  semiannual,
  yearly,
  p7,
  p30,
  p90,
  lifetime,
  lifetime1,
  lifetime2,
  lifetime3;

  static BillingCycle fromString(String value) {
    return BillingCycle.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BillingCycle.monthly,
    );
  }

  bool get isLifetime =>
      this == lifetime ||
      this == lifetime1 ||
      this == lifetime2 ||
      this == lifetime3;
}

/// Represents a user's premium license state (subscription-based)
class PremiumLicense {
  final PremiumTier tier;
  final String? licenseKey;
  final DateTime? purchaseDate;
  final DateTime? lastVerified;
  final String? paymentMethod; // 'stripe' | 'crypto'
  final String? transactionId;
  final BillingCycle? billingCycle;
  final DateTime? expiresAt;
  final bool isAutoRenew;
  final DateTime? cancelledAt;

  const PremiumLicense({
    this.tier = PremiumTier.free,
    this.licenseKey,
    this.purchaseDate,
    this.lastVerified,
    this.paymentMethod,
    this.transactionId,
    this.billingCycle,
    this.expiresAt,
    this.isAutoRenew = true,
    this.cancelledAt,
  });

  /// Free license (default)
  static const free = PremiumLicense();

  bool get isPremium => tier == PremiumTier.premium;
  bool get isFree => tier == PremiumTier.free;

  /// Whether the subscription has expired (lifetime plans never expire)
  bool get isExpired {
    if (isFree || expiresAt == null) return false;
    if (billingCycle?.isLifetime ?? false) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Whether the subscription has been cancelled (will expire at end of period)
  bool get isCancelled => cancelledAt != null;

  /// Days remaining until expiration (-1 if no expiry)
  int get daysRemaining {
    if (expiresAt == null) return -1;
    final remaining = expiresAt!.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  /// Whether subscription is active (premium + not expired)
  bool get isActiveSubscription => isPremium && !isExpired;

  /// Whether server verification is needed (> 7 days since last check)
  bool needsVerification({DateTime? now}) {
    if (isFree) return false;
    if (lastVerified == null) return true;
    final current = now ?? DateTime.now();
    return current.difference(lastVerified!).inDays >= 7;
  }

  /// Whether still within grace period (30 days from last verification)
  bool isWithinGracePeriod({DateTime? now}) {
    if (isFree) return false;
    if (lastVerified == null) return false;
    final current = now ?? DateTime.now();
    return current.difference(lastVerified!).inDays < 30;
  }

  PremiumLicense copyWith({
    PremiumTier? tier,
    String? licenseKey,
    DateTime? purchaseDate,
    DateTime? lastVerified,
    String? paymentMethod,
    String? transactionId,
    BillingCycle? billingCycle,
    DateTime? expiresAt,
    bool? isAutoRenew,
    DateTime? cancelledAt,
    bool clearLicenseKey = false,
    bool clearPurchaseDate = false,
    bool clearLastVerified = false,
    bool clearPaymentMethod = false,
    bool clearTransactionId = false,
    bool clearBillingCycle = false,
    bool clearExpiresAt = false,
    bool clearCancelledAt = false,
  }) {
    return PremiumLicense(
      tier: tier ?? this.tier,
      licenseKey: clearLicenseKey ? null : (licenseKey ?? this.licenseKey),
      purchaseDate:
          clearPurchaseDate ? null : (purchaseDate ?? this.purchaseDate),
      lastVerified:
          clearLastVerified ? null : (lastVerified ?? this.lastVerified),
      paymentMethod:
          clearPaymentMethod ? null : (paymentMethod ?? this.paymentMethod),
      transactionId:
          clearTransactionId ? null : (transactionId ?? this.transactionId),
      billingCycle:
          clearBillingCycle ? null : (billingCycle ?? this.billingCycle),
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      isAutoRenew: isAutoRenew ?? this.isAutoRenew,
      cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
    );
  }

  /// Serialize to JSON map (for SharedPreferences storage)
  Map<String, dynamic> toJson() => {
    'tier': tier.name,
    if (purchaseDate != null) 'purchaseDate': purchaseDate!.toIso8601String(),
    if (lastVerified != null) 'lastVerified': lastVerified!.toIso8601String(),
    if (paymentMethod != null) 'paymentMethod': paymentMethod,
    if (transactionId != null) 'transactionId': transactionId,
    if (billingCycle != null) 'billingCycle': billingCycle!.name,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    'isAutoRenew': isAutoRenew,
    if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
  };

  /// Deserialize from JSON map
  factory PremiumLicense.fromJson(Map<String, dynamic> json) {
    return PremiumLicense(
      tier: PremiumTier.fromString(json['tier'] as String? ?? 'free'),
      purchaseDate:
          json['purchaseDate'] != null
              ? DateTime.tryParse(json['purchaseDate'] as String)
              : null,
      lastVerified:
          json['lastVerified'] != null
              ? DateTime.tryParse(json['lastVerified'] as String)
              : null,
      paymentMethod: json['paymentMethod'] as String?,
      transactionId: json['transactionId'] as String?,
      billingCycle:
          json['billingCycle'] != null
              ? BillingCycle.fromString(json['billingCycle'] as String)
              : null,
      expiresAt:
          json['expiresAt'] != null
              ? DateTime.tryParse(json['expiresAt'] as String)
              : null,
      isAutoRenew: json['isAutoRenew'] as bool? ?? true,
      cancelledAt:
          json['cancelledAt'] != null
              ? DateTime.tryParse(json['cancelledAt'] as String)
              : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PremiumLicense &&
          runtimeType == other.runtimeType &&
          tier == other.tier &&
          licenseKey == other.licenseKey &&
          purchaseDate == other.purchaseDate &&
          lastVerified == other.lastVerified &&
          paymentMethod == other.paymentMethod &&
          transactionId == other.transactionId &&
          billingCycle == other.billingCycle &&
          expiresAt == other.expiresAt &&
          isAutoRenew == other.isAutoRenew &&
          cancelledAt == other.cancelledAt;

  @override
  int get hashCode => Object.hash(
    tier,
    licenseKey,
    purchaseDate,
    lastVerified,
    paymentMethod,
    transactionId,
    billingCycle,
    expiresAt,
    isAutoRenew,
    cancelledAt,
  );

  @override
  String toString() =>
      'PremiumLicense(tier: $tier, cycle: ${billingCycle?.name}, '
      'expires: ${expiresAt != null ? "${daysRemaining}d" : "n/a"}, '
      'key: ${licenseKey != null ? "***" : "null"})';
}
