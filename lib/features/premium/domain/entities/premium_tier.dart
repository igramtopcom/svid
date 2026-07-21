/// Premium subscription tier
enum PremiumTier {
  /// Free tier — basic downloading, no feature restrictions on core
  free,

  /// Premium tier — all advanced features unlocked
  premium;

  /// Parse from stored string, defaults to [free]
  static PremiumTier fromString(String value) {
    return PremiumTier.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PremiumTier.free,
    );
  }
}
