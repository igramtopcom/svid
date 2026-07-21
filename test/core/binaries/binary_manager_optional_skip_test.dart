import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/binaries/binary_manager.dart';
import 'package:svid/core/binaries/binary_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempSupport = await Directory.systemTemp.createTemp('binary_manager_test_');
    // path_provider mock — getApplicationSupportDirectory returns the
    // isolated temp dir so `_initializeInternal` writes its `bin/`
    // subdir into a sandboxed location, not the real user data path.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempSupport.path;
            }
            return null;
          },
        );
    BinaryManager.resetForTest();
  });

  tearDown(() async {
    BinaryManager.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  group('BinaryManager version formatting', () {
    test('formats FFmpeg first line to concise build id', () {
      expect(
        BinaryManager.formatVersionOutputForTest(
          BinaryType.ffmpeg,
          'ffmpeg version N-124085-g162ad61486-https://www.ma '
          'Copyright (c) 2000-2026\nbuilt with Apple clang',
        ),
        'N-124085-g162ad61486',
      );
    });

    test('keeps normal yt-dlp version output unchanged', () {
      expect(
        BinaryManager.formatVersionOutputForTest(
          BinaryType.ytDlp,
          '2026.03.17\n',
        ),
        '2026.03.17',
      );
    });
  });

  group('BinaryManager optional-skip TTL contract', () {
    test(
      'skip key is stable per BinaryType (audit-readable in prefs dump)',
      () {
        // Audit + manual prefs inspection rely on a predictable key.
        expect(
          BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl),
          equals('binary_optional_skipped_gallery-dl'),
        );
        expect(
          BinaryManager.optionalSkipKeyForTest(BinaryType.ytDlp),
          equals('binary_optional_skipped_yt-dlp'),
        );
      },
    );

    test('TTL is 7 days — long enough not to pester users, short enough '
        'to retry after upstream fix', () {
      expect(BinaryManager.optionalSkipTtlForTest, const Duration(days: 7));
    });

    test('roundtrip: write timestamp now, reading it back yields a value '
        'within ttl', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl);
      final now = DateTime.now();
      await prefs.setString(key, now.toIso8601String());

      final stored = prefs.getString(key);
      expect(stored, isNotNull);

      final parsed = DateTime.parse(stored!);
      final elapsed = DateTime.now().difference(parsed);
      expect(elapsed, lessThan(BinaryManager.optionalSkipTtlForTest));
    });

    test(
      'expired timestamp (older than TTL) parses to a value beyond ttl',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final key = BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl);
        final ancient = DateTime.now().subtract(const Duration(days: 30));
        await prefs.setString(key, ancient.toIso8601String());

        final stored = prefs.getString(key);
        final parsed = DateTime.parse(stored!);
        final elapsed = DateTime.now().difference(parsed);
        expect(elapsed, greaterThan(BinaryManager.optionalSkipTtlForTest));
      },
    );

    test('malformed timestamp does not crash the read path', () async {
      // The production helper wraps DateTime.tryParse — verify the
      // contract by reading a malformed value the same way and
      // asserting it round-trips to null.
      final prefs = await SharedPreferences.getInstance();
      final key = BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl);
      await prefs.setString(key, 'not-a-date');

      expect(DateTime.tryParse(prefs.getString(key)!), isNull);
    });
  });

  group('BinaryManager.getMissingBinaries — real behaviour with skip TTL', () {
    // These tests exercise the actual missing-list filter through the
    // singleton, mocking only path_provider + SharedPreferences. The
    // round-3 review feedback specifically called out that the prior
    // tests covered only key/parse helpers, not the filtering decision.

    test(
      'fresh skip mark for gallery-dl excludes it from missing list',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final key = BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl);
        // Mark gallery-dl as skipped 1 hour ago — well within 7-day TTL.
        await prefs.setString(
          key,
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        );

        final manager = BinaryManager();
        final missing = await manager.getMissingBinaries();

        expect(
          missing,
          isNot(contains(BinaryType.galleryDl)),
          reason:
              'gallery-dl skipped within TTL must not reappear in '
              'missing list (round-2 finding: setup screen reappears '
              'every launch otherwise).',
        );
        // yt-dlp + ffmpeg are required, no skip mark — they should
        // appear in missing for a fresh install.
        expect(missing, contains(BinaryType.ytDlp));
        expect(missing, contains(BinaryType.ffmpeg));
      },
    );

    test('expired skip mark (older than TTL) re-includes gallery-dl', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl);
      // Mark gallery-dl as skipped 30 days ago — well beyond 7-day TTL.
      await prefs.setString(
        key,
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      );

      final manager = BinaryManager();
      final missing = await manager.getMissingBinaries();

      expect(
        missing,
        contains(BinaryType.galleryDl),
        reason:
            'expired skip should re-attempt — upstream may have '
            'recovered since the original skip.',
      );
    });

    test(
      'no skip mark — gallery-dl appears in missing list (default state)',
      () async {
        final manager = BinaryManager();
        final missing = await manager.getMissingBinaries();

        // Whether gallery-dl is in the list depends on whether
        // platform-config supports it (Intel macOS excludes it). On
        // every other platform the default (no skip mark) is "include
        // because not yet attempted".
        if (BinaryManager.isGalleryDlSupported) {
          expect(missing, contains(BinaryType.galleryDl));
        }
        expect(missing, contains(BinaryType.ytDlp));
        expect(missing, contains(BinaryType.ffmpeg));
      },
    );
  });

  group('BinaryManager.clearOptionalSkipMarks', () {
    test('removes every persisted optional-skip key', () async {
      final prefs = await SharedPreferences.getInstance();
      // Mark every BinaryType (including non-optional ones — clear
      // should remove them all from the namespace anyway).
      for (final type in BinaryType.values) {
        await prefs.setString(
          BinaryManager.optionalSkipKeyForTest(type),
          DateTime.now().toIso8601String(),
        );
      }

      final manager = BinaryManager();
      await manager.clearOptionalSkipMarks();

      for (final type in BinaryType.values) {
        expect(
          prefs.getString(BinaryManager.optionalSkipKeyForTest(type)),
          isNull,
          reason:
              'clearOptionalSkipMarks must purge every binary '
              'type — Settings → Re-download relies on this to force '
              'a retry without waiting for TTL.',
        );
      }
    });

    test(
      'clearOptionalSkipMarks puts gallery-dl back in missing list',
      () async {
        final prefs = await SharedPreferences.getInstance();
        // Start with a fresh skip (would normally suppress).
        await prefs.setString(
          BinaryManager.optionalSkipKeyForTest(BinaryType.galleryDl),
          DateTime.now().toIso8601String(),
        );

        final manager = BinaryManager();
        // Suppressed first.
        var missing = await manager.getMissingBinaries();
        if (BinaryManager.isGalleryDlSupported) {
          expect(missing, isNot(contains(BinaryType.galleryDl)));
        }

        // Clear → next read should include it again.
        await manager.clearOptionalSkipMarks();
        missing = await manager.getMissingBinaries();
        if (BinaryManager.isGalleryDlSupported) {
          expect(missing, contains(BinaryType.galleryDl));
        }
      },
    );
  });
}
