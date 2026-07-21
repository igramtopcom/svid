import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ssvid/core/services/startup_service.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('legacy_key_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<File> writeSettings(
    String dirName,
    String fileName,
    Map<String, dynamic> json,
  ) async {
    final dir = Directory(p.join(tempRoot.path, dirName));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(jsonEncode(json));
    return file;
  }

  group('scanDirsForLegacyKey', () {
    test('finds valid 32-char hex key in settings1.gs', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'A3B9EE755909C2E2836D4ED651834303',
        'statusLisence': 'active',
        'dateLiecence': '2027-06-10',
        'planLv': 1,
        'plan': 'plan1',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, 'A3B9EE755909C2E2836D4ED651834303');
    });

    test('finds key in settings1.bak when settings1.gs missing', () async {
      await writeSettings('app_data', 'settings1.bak', {
        'lisenceKey': 'ABCDEF01234567890ABCDEF012345678',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, 'ABCDEF01234567890ABCDEF012345678');
    });

    test('finds key in settings.json fallback', () async {
      await writeSettings('app_data', 'settings.json', {
        'lisenceKey': '12345678ABCDEF0012345678ABCDEF00',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, '12345678ABCDEF0012345678ABCDEF00');
    });

    test('prefers settings1.gs over settings1.bak', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      });
      await writeSettings('app_data', 'settings1.bak', {
        'lisenceKey': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    });

    test('scans multiple directories, returns first valid key', () async {
      // First dir: no settings file
      await Directory(p.join(tempRoot.path, 'empty_dir')).create();
      // Second dir: has key
      await writeSettings('second_dir', 'settings1.gs', {
        'lisenceKey': 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'empty_dir'),
        p.join(tempRoot.path, 'second_dir'),
      ]);

      expect(key, 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC');
    });

    test('returns null for non-existent directories', () async {
      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'does_not_exist'),
      ]);

      expect(key, isNull);
    });

    test('returns null for empty directory list', () async {
      final key = await StartupService.scanDirsForLegacyKey([]);

      expect(key, isNull);
    });

    test('returns null when lisenceKey field is missing', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'statusLisence': 'active',
        'planLv': 1,
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });

    test('returns null when lisenceKey is not 32 chars', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'SHORT',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });

    test('returns null when lisenceKey is 32 chars but not hex', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });

    test('returns null when file contains invalid JSON', () async {
      final dir = Directory(p.join(tempRoot.path, 'app_data'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'settings1.gs'))
          .writeAsString('not valid json at all');

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });

    test('returns null when file is empty', () async {
      final dir = Directory(p.join(tempRoot.path, 'app_data'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'settings1.gs')).writeAsString('');

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });

    test('accepts lowercase hex key', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'a3b9ee755909c2e2836d4ed651834303',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, 'a3b9ee755909c2e2836d4ed651834303');
    });

    test('accepts mixed-case hex key', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': 'A3b9Ee755909C2e2836D4eD651834303',
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, 'A3b9Ee755909C2e2836D4eD651834303');
    });

    test('skips file with null lisenceKey value', () async {
      await writeSettings('app_data', 'settings1.gs', {
        'lisenceKey': null,
      });

      final key = await StartupService.scanDirsForLegacyKey([
        p.join(tempRoot.path, 'app_data'),
      ]);

      expect(key, isNull);
    });
  });
}
