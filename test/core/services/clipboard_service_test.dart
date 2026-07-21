import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/clipboard_service.dart';

/// Unit tests for [ClipboardService] — verifies it swallows Windows
/// PlatformException and never propagates errors to callers, mirroring the
/// contract referenced in the production telemetry note:
/// `PlatformException(Clipboard error, Unable to open clipboard, 5, null)`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void mockClipboard({
    PlatformException? throwOnGet,
    PlatformException? throwOnSet,
    String? returnText,
    List<String>? captureSet,
  }) {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        if (throwOnGet != null) throw throwOnGet;
        return returnText == null ? null : <String, dynamic>{'text': returnText};
      }
      if (call.method == 'Clipboard.setData') {
        if (throwOnSet != null) throw throwOnSet;
        final args = call.arguments as Map?;
        final text = args?['text'] as String?;
        if (text != null) captureSet?.add(text);
        return null;
      }
      return null;
    });
  }

  group('ClipboardService.setText', () {
    test('returns true on platform success and writes payload', () async {
      final captured = <String>[];
      mockClipboard(captureSet: captured);
      final result = await ClipboardService.setText('hello');
      expect(result, isTrue);
      expect(captured, ['hello']);
    });

    test(
      'returns false on Windows clipboard-lock PlatformException',
      () async {
        mockClipboard(
          throwOnSet: PlatformException(
            code: 'Clipboard error',
            message: 'Unable to open clipboard',
            details: 5,
          ),
        );
        final result = await ClipboardService.setText('hello');
        expect(result, isFalse);
      },
    );

    test('returns false on unexpected (non-platform) error', () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          throw StateError('something else went wrong');
        }
        return null;
      });
      final result = await ClipboardService.setText('hello');
      expect(result, isFalse);
    });

    test('handles empty string without throwing', () async {
      final captured = <String>[];
      mockClipboard(captureSet: captured);
      final result = await ClipboardService.setText('');
      expect(result, isTrue);
      expect(captured, ['']);
    });
  });

  group('ClipboardService.getText', () {
    test('returns text when clipboard contains data', () async {
      mockClipboard(returnText: 'copied url');
      final result = await ClipboardService.getText();
      expect(result, 'copied url');
    });

    test('returns null when clipboard is empty', () async {
      mockClipboard(returnText: null);
      final result = await ClipboardService.getText();
      expect(result, isNull);
    });

    test(
      'returns null on Windows clipboard-lock PlatformException',
      () async {
        mockClipboard(
          throwOnGet: PlatformException(
            code: 'Clipboard error',
            message: 'Unable to open clipboard',
            details: 5,
          ),
        );
        final result = await ClipboardService.getText();
        expect(result, isNull);
      },
    );

    test('returns null on unexpected error', () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          throw StateError('boom');
        }
        return null;
      });
      final result = await ClipboardService.getText();
      expect(result, isNull);
    });
  });
}
