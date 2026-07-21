import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/presentation/providers/player_providers.dart';

void main() {
  group('subtitleFontSizeProvider', () {
    test('initial value is 32.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(subtitleFontSizeProvider), 32.0);
    });

    test('can be set to a custom value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleFontSizeProvider.notifier).state = 24.0;
      expect(container.read(subtitleFontSizeProvider), 24.0);
    });

    test('can be set to minimum 16.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleFontSizeProvider.notifier).state = 16.0;
      expect(container.read(subtitleFontSizeProvider), 16.0);
    });
  });

  group('subtitleTextColorProvider', () {
    test('initial value is white', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(subtitleTextColorProvider), const Color(0xFFFFFFFF));
    });

    test('can be set to yellow', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleTextColorProvider.notifier).state =
          const Color(0xFFFFFF00);
      expect(
          container.read(subtitleTextColorProvider), const Color(0xFFFFFF00));
    });
  });

  group('subtitleBackgroundColorProvider', () {
    test('initial value is semi-transparent black', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(subtitleBackgroundColorProvider),
          const Color(0xAA000000));
    });

    test('can be set to custom color', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final customColor = Color.fromRGBO(0, 0, 0, 0.5);
      container.read(subtitleBackgroundColorProvider.notifier).state =
          customColor;
      expect(container.read(subtitleBackgroundColorProvider), customColor);
    });
  });

  group('subtitleBackgroundEnabledProvider', () {
    test('initial value is true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(subtitleBackgroundEnabledProvider), true);
    });

    test('can be toggled to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleBackgroundEnabledProvider.notifier).state = false;
      expect(container.read(subtitleBackgroundEnabledProvider), false);
    });
  });

  group('subtitleBottomPaddingProvider', () {
    test('initial value is 24.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(subtitleBottomPaddingProvider), 24.0);
    });

    test('can be set to custom value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleBottomPaddingProvider.notifier).state = 60.0;
      expect(container.read(subtitleBottomPaddingProvider), 60.0);
    });
  });

  group('subtitleViewConfigProvider', () {
    test('default config has expected values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.fontSize, 32.0);
      expect(config.style.color, const Color(0xFFFFFFFF));
      expect(config.style.backgroundColor, const Color(0xAA000000));
      expect(config.textAlign, TextAlign.center);
      expect(config.padding, const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0));
    });

    test('reacts to font size change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleFontSizeProvider.notifier).state = 48.0;
      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.fontSize, 48.0);
    });

    test('reacts to text color change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleTextColorProvider.notifier).state =
          const Color(0xFFFFFF00);
      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.color, const Color(0xFFFFFF00));
    });

    test('reacts to background toggle off — uses transparent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleBackgroundEnabledProvider.notifier).state = false;
      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.backgroundColor, Colors.transparent);
    });

    test('reacts to background color change when enabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final customBg = Color.fromRGBO(0, 0, 0, 0.75);
      container.read(subtitleBackgroundColorProvider.notifier).state = customBg;
      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.backgroundColor, customBg);
    });

    test('reacts to bottom padding change', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subtitleBottomPaddingProvider.notifier).state = 80.0;
      final config = container.read(subtitleViewConfigProvider);
      expect(
          config.padding, const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 80.0));
    });

    test('reset to defaults restores all values', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Change everything
      container.read(subtitleFontSizeProvider.notifier).state = 48.0;
      container.read(subtitleTextColorProvider.notifier).state =
          const Color(0xFFFF0000);
      container.read(subtitleBackgroundEnabledProvider.notifier).state = false;
      container.read(subtitleBottomPaddingProvider.notifier).state = 80.0;

      // Reset
      container.read(subtitleFontSizeProvider.notifier).state = 32.0;
      container.read(subtitleTextColorProvider.notifier).state =
          const Color(0xFFFFFFFF);
      container.read(subtitleBackgroundColorProvider.notifier).state =
          const Color(0xAA000000);
      container.read(subtitleBackgroundEnabledProvider.notifier).state = true;
      container.read(subtitleBottomPaddingProvider.notifier).state = 24.0;

      final config = container.read(subtitleViewConfigProvider);
      expect(config.style.fontSize, 32.0);
      expect(config.style.color, const Color(0xFFFFFFFF));
      expect(config.style.backgroundColor, const Color(0xAA000000));
      expect(config.padding, const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0));
    });
  });
}
