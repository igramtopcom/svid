/// Supported cryptocurrencies for payment.
enum CryptoCurrency {
  /// Bitcoin — 1 confirmation required.
  btc('BTC', 'Bitcoin', 1),

  /// Litecoin — 3 confirmations required.
  ltc('LTC', 'Litecoin', 3),

  /// Monero — 10 confirmations required.
  xmr('XMR', 'Monero', 10);

  final String symbol;
  final String displayName;
  final int requiredConfirmations;

  const CryptoCurrency(this.symbol, this.displayName, this.requiredConfirmations);

  /// Parse from string (e.g., 'BTC', 'btc').
  static CryptoCurrency fromString(String? value) {
    if (value == null) return CryptoCurrency.btc;
    return CryptoCurrency.values.firstWhere(
      (c) => c.symbol.toLowerCase() == value.toLowerCase() || c.name == value,
      orElse: () => CryptoCurrency.btc,
    );
  }
}
