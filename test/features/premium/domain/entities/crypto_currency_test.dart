import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/crypto_currency.dart';

void main() {
  group('CryptoCurrency', () {
    test('has correct symbols', () {
      expect(CryptoCurrency.btc.symbol, 'BTC');
      expect(CryptoCurrency.ltc.symbol, 'LTC');
      expect(CryptoCurrency.xmr.symbol, 'XMR');
    });

    test('has correct display names', () {
      expect(CryptoCurrency.btc.displayName, 'Bitcoin');
      expect(CryptoCurrency.ltc.displayName, 'Litecoin');
      expect(CryptoCurrency.xmr.displayName, 'Monero');
    });

    test('has correct required confirmations', () {
      expect(CryptoCurrency.btc.requiredConfirmations, 1);
      expect(CryptoCurrency.ltc.requiredConfirmations, 3);
      expect(CryptoCurrency.xmr.requiredConfirmations, 10);
    });

    test('fromString parses uppercase symbol', () {
      expect(CryptoCurrency.fromString('BTC'), CryptoCurrency.btc);
      expect(CryptoCurrency.fromString('LTC'), CryptoCurrency.ltc);
      expect(CryptoCurrency.fromString('XMR'), CryptoCurrency.xmr);
    });

    test('fromString parses lowercase symbol', () {
      expect(CryptoCurrency.fromString('btc'), CryptoCurrency.btc);
      expect(CryptoCurrency.fromString('ltc'), CryptoCurrency.ltc);
      expect(CryptoCurrency.fromString('xmr'), CryptoCurrency.xmr);
    });

    test('fromString parses enum name', () {
      expect(CryptoCurrency.fromString('btc'), CryptoCurrency.btc);
    });

    test('fromString defaults to BTC for null', () {
      expect(CryptoCurrency.fromString(null), CryptoCurrency.btc);
    });

    test('fromString defaults to BTC for unknown', () {
      expect(CryptoCurrency.fromString('DOGE'), CryptoCurrency.btc);
    });
  });
}
