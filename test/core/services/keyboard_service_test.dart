import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/keyboard_service.dart';

void main() {
  setUp(() {
    // Reset all callbacks before each test
    KeyboardService.onSearchShortcut = null;
    KeyboardService.onNewDownloadShortcut = null;
    KeyboardService.onSettingsShortcut = null;
    KeyboardService.onPasteAndStartShortcut = null;
    KeyboardService.onPauseAllShortcut = null;
    KeyboardService.onResumeAllShortcut = null;
    KeyboardService.onOpenPlayerShortcut = null;
    KeyboardService.onTogglePipShortcut = null;
    KeyboardService.onCloseOrMinimize = null;
    KeyboardService.onQuitShortcut = null;
    KeyboardService.onShowAndNewDownload = null;
    KeyboardService.onDownloadFromClipboardGlobal = null;
    KeyboardService.onToggleVisibility = null;
  });

  group('KeyboardService callbacks', () {
    test('all callbacks are null by default after reset', () {
      expect(KeyboardService.onSearchShortcut, isNull);
      expect(KeyboardService.onNewDownloadShortcut, isNull);
      expect(KeyboardService.onSettingsShortcut, isNull);
      expect(KeyboardService.onPasteAndStartShortcut, isNull);
      expect(KeyboardService.onPauseAllShortcut, isNull);
      expect(KeyboardService.onResumeAllShortcut, isNull);
      expect(KeyboardService.onOpenPlayerShortcut, isNull);
      expect(KeyboardService.onTogglePipShortcut, isNull);
      expect(KeyboardService.onCloseOrMinimize, isNull);
      expect(KeyboardService.onQuitShortcut, isNull);
      expect(KeyboardService.onShowAndNewDownload, isNull);
      expect(KeyboardService.onDownloadFromClipboardGlobal, isNull);
      expect(KeyboardService.onToggleVisibility, isNull);
    });

    test('onShowAndNewDownload can be set and called', () {
      var called = false;
      KeyboardService.onShowAndNewDownload = () => called = true;
      KeyboardService.onShowAndNewDownload?.call();
      expect(called, isTrue);
    });

    test('onDownloadFromClipboardGlobal can be set and called', () async {
      var called = false;
      KeyboardService.onDownloadFromClipboardGlobal = () async => called = true;
      await KeyboardService.onDownloadFromClipboardGlobal?.call();
      expect(called, isTrue);
    });

    test('onToggleVisibility can be set and called', () {
      var called = false;
      KeyboardService.onToggleVisibility = () => called = true;
      KeyboardService.onToggleVisibility?.call();
      expect(called, isTrue);
    });

    test('onPasteAndStartShortcut can be set and called', () {
      var called = false;
      KeyboardService.onPasteAndStartShortcut = () => called = true;
      KeyboardService.onPasteAndStartShortcut?.call();
      expect(called, isTrue);
    });

    test('onPauseAllShortcut can be set and called', () {
      var called = false;
      KeyboardService.onPauseAllShortcut = () => called = true;
      KeyboardService.onPauseAllShortcut?.call();
      expect(called, isTrue);
    });

    test('onResumeAllShortcut can be set and called', () {
      var called = false;
      KeyboardService.onResumeAllShortcut = () => called = true;
      KeyboardService.onResumeAllShortcut?.call();
      expect(called, isTrue);
    });

    test('onOpenPlayerShortcut can be set and called', () {
      var called = false;
      KeyboardService.onOpenPlayerShortcut = () => called = true;
      KeyboardService.onOpenPlayerShortcut?.call();
      expect(called, isTrue);
    });

    test('callbacks are independent — setting one does not affect others', () {
      var pauseAllCalled = false;
      var resumeAllCalled = false;
      KeyboardService.onPauseAllShortcut = () => pauseAllCalled = true;
      KeyboardService.onResumeAllShortcut = () => resumeAllCalled = true;

      KeyboardService.onPauseAllShortcut?.call();

      expect(pauseAllCalled, isTrue);
      expect(resumeAllCalled, isFalse);
    });

    test('callback can be replaced', () {
      var count = 0;
      KeyboardService.onPasteAndStartShortcut = () => count += 1;
      KeyboardService.onPasteAndStartShortcut = () => count += 10;
      KeyboardService.onPasteAndStartShortcut?.call();
      expect(count, equals(10));
    });

    test('null callback is safe to call via ?. operator', () {
      KeyboardService.onPasteAndStartShortcut = null;
      expect(
        () => KeyboardService.onPasteAndStartShortcut?.call(),
        returnsNormally,
      );
    });
  });

  group('KeyboardService.platformModifierName', () {
    test('returns a non-empty string', () {
      expect(KeyboardService.platformModifierName, isNotEmpty);
    });
  });

  group('KeyboardService.getShortcutText', () {
    test('returns modifier + key format', () {
      final result = KeyboardService.getShortcutText('Shift+V');
      expect(result, contains('Shift+V'));
      expect(result, contains(KeyboardService.platformModifierName));
    });

    test('pause all shortcut text includes Shift+P', () {
      final result = KeyboardService.getShortcutText('Shift+P');
      expect(result, equals('${KeyboardService.platformModifierName}+Shift+P'));
    });

    test('resume all shortcut text includes Shift+R', () {
      final result = KeyboardService.getShortcutText('Shift+R');
      expect(result, equals('${KeyboardService.platformModifierName}+Shift+R'));
    });

    test('open player shortcut text includes P', () {
      final result = KeyboardService.getShortcutText('P');
      expect(result, equals('${KeyboardService.platformModifierName}+P'));
    });
  });

  group('callback isolation', () {
    test('all 4 new callbacks fire independently', () {
      final fired = <String>[];
      KeyboardService.onPasteAndStartShortcut = () => fired.add('paste');
      KeyboardService.onPauseAllShortcut = () => fired.add('pause');
      KeyboardService.onResumeAllShortcut = () => fired.add('resume');
      KeyboardService.onOpenPlayerShortcut = () => fired.add('player');

      KeyboardService.onPasteAndStartShortcut?.call();
      KeyboardService.onPauseAllShortcut?.call();
      KeyboardService.onResumeAllShortcut?.call();
      KeyboardService.onOpenPlayerShortcut?.call();

      expect(fired, equals(['paste', 'pause', 'resume', 'player']));
    });

    test('resetting one callback does not reset others', () {
      KeyboardService.onPauseAllShortcut = () {};
      KeyboardService.onResumeAllShortcut = () {};
      KeyboardService.onPauseAllShortcut = null;

      expect(KeyboardService.onPauseAllShortcut, isNull);
      expect(KeyboardService.onResumeAllShortcut, isNotNull);
    });
  });
}
