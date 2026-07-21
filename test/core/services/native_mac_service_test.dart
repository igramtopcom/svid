import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/services/native_mac_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Channel name is brand-stamped at runtime via methodChannelPrefix — must
  // be derived the same way the production service does so the mock binds
  // to the same channel under both BRAND=svid and BRAND=vidcombo.
  final channel = MethodChannel(
      '${BrandConfig.current.methodChannelPrefix}/macos_actions');

  group('NativeMacService.shareFile', () {
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (call) async {
          log.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('invokes shareFile method with correct path on macOS', () async {
      if (!Platform.isMacOS) return; // only relevant on macOS

      await NativeMacService.shareFile('/tmp/video.mp4');

      expect(log, hasLength(1));
      expect(log.first.method, equals('shareFile'));
      expect(log.first.arguments, equals('/tmp/video.mp4'));
    });

    test('does nothing on non-macOS platforms', () async {
      if (Platform.isMacOS) return; // skip on macOS — test is for non-macOS

      await NativeMacService.shareFile('/tmp/video.mp4');

      expect(log, isEmpty);
    });

    test('does not throw on PlatformException', () async {
      if (!Platform.isMacOS) return;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (call) async {
          throw PlatformException(code: 'FILE_NOT_FOUND');
        },
      );

      expect(() => NativeMacService.shareFile('/nonexistent/file.mp4'),
          returnsNormally);
    });
  });
}
