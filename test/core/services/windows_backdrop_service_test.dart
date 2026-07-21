import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/windows_backdrop_service.dart';

void main() {
  test('resolves light theme to light backdrop', () {
    expect(
      WindowsBackdropService.instance.resolveBackdropTheme(ThemeMode.light),
      'light',
    );
  });

  test('resolves dark theme to dark backdrop', () {
    expect(
      WindowsBackdropService.instance.resolveBackdropTheme(ThemeMode.dark),
      'dark',
    );
  });

  test('resolves system theme from platform brightness', () {
    expect(
      WindowsBackdropService.instance.resolveBackdropTheme(
        ThemeMode.system,
        platformBrightness: Brightness.light,
      ),
      'light',
    );
    expect(
      WindowsBackdropService.instance.resolveBackdropTheme(
        ThemeMode.system,
        platformBrightness: Brightness.dark,
      ),
      'dark',
    );
  });
}
