import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/crash_severity_classifier.dart';

void main() {
  group('classifyCrashSeverity', () {
    test('SQLite database is locked → critical', () {
      expect(
        classifyCrashSeverity(
          'SqliteException(5): database is locked',
          '#0 NativeDatabase.execute',
        ),
        'critical',
      );
    });

    test('Database disk image malformed → critical', () {
      expect(
        classifyCrashSeverity('database disk image is malformed', null),
        'critical',
      );
    });

    test('OutOfMemoryError → critical', () {
      expect(classifyCrashSeverity('OutOfMemoryError', null), 'critical');
    });

    test('Player has been disposed assertion → high', () {
      expect(
        classifyCrashSeverity(
          'Assertion failed: "[Player] has been disposed"',
          null,
        ),
        'high',
      );
    });

    test('MissingPluginException → high', () {
      expect(
        classifyCrashSeverity(
          'MissingPluginException(No implementation found)',
          null,
        ),
        'high',
      );
    });

    test('PlatformException → high', () {
      expect(
        classifyCrashSeverity(
          'PlatformException(FWFUnsupportedVersionError, ...)',
          null,
        ),
        'high',
      );
    });

    test('legacy_thumbnails URI parse → high', () {
      expect(
        classifyCrashSeverity(
          'Invalid argument(s): No host specified in URI file:///legacy_thumbnails/12.jpg',
          null,
        ),
        'high',
      );
    });

    test('Rust bridge stack frame → high', () {
      expect(
        classifyCrashSeverity(
          'StateError: bridge call failed',
          '#0 frb_generated.dart\n#1 flutter_rust_bridge_internal.dart',
        ),
        'high',
      );
    });

    test('RenderFlex overflowed → low', () {
      expect(
        classifyCrashSeverity(
          'A RenderFlex overflowed by 336 pixels on the right.',
          null,
        ),
        'low',
      );
    });

    test('deprecated API warning → low', () {
      expect(
        classifyCrashSeverity('the property is deprecated', null),
        'low',
      );
    });

    test('unknown error → medium (default)', () {
      expect(
        classifyCrashSeverity('something weird happened', null),
        'medium',
      );
    });

    test('FormatException UTF-8 → medium (default — already mitigated by allowMalformed)', () {
      expect(
        classifyCrashSeverity(
          'FormatException: Missing extension byte (at offset 81)',
          null,
        ),
        'medium',
      );
    });
  });
}
