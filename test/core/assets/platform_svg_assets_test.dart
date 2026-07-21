import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_style_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedPlatformAssets = <String>[
    'assets/icons/platforms/facebook.svg',
    'assets/icons/platforms/instagram.svg',
    'assets/icons/platforms/other.svg',
    'assets/icons/platforms/pinterest.svg',
    'assets/icons/platforms/reddit.svg',
    'assets/icons/platforms/tiktok.svg',
    'assets/icons/platforms/x.svg',
    'assets/icons/platforms/youtube.svg',
  ];

  test('popular platform SVG assets exist on disk', () {
    for (final asset in expectedPlatformAssets) {
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: '$asset must exist');
      expect(file.lengthSync(), greaterThan(0), reason: '$asset is empty');
    }
  });

  test('pubspec declares platform icon asset directory', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/icons/platforms/'));
  });

  test('rootBundle can load all popular platform SVG assets', () async {
    for (final asset in expectedPlatformAssets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: '$asset not bundled');
    }
  });

  test('PlatformStyleHelper only returns declared platform SVG assets', () {
    const platforms = <String>[
      'youtube',
      'facebook',
      'instagram',
      'tiktok',
      'x',
      'twitter',
      'reddit',
      'pinterest',
    ];

    final declared = expectedPlatformAssets.toSet();
    for (final platform in platforms) {
      final asset = PlatformStyleHelper.getSvgPathForPlatform(platform);
      expect(asset, isNotNull, reason: '$platform should have an SVG');
      expect(declared, contains(asset));
    }
  });
}
