import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/floating_window_main.dart';

void main() {
  group('shouldSkipTaskbarForFloatingCapture', () {
    test('keeps macOS app visible in Dock/sidebar', () {
      expect(
        shouldSkipTaskbarForFloatingCapture(operatingSystem: 'macos'),
        isFalse,
      );
    });

    test('keeps Windows popup out of taskbar and Alt-Tab', () {
      expect(
        shouldSkipTaskbarForFloatingCapture(operatingSystem: 'windows'),
        isTrue,
      );
    });

    test('continues hiding taskbar entry on Linux', () {
      expect(
        shouldSkipTaskbarForFloatingCapture(operatingSystem: 'linux'),
        isTrue,
      );
    });
  });
}
