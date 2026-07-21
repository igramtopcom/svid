import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/migrations/v2_savedpref_to_preset_importer.dart';
import 'package:svid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';

/// Pure-prefs tests — no Riverpod, no widgets. Pin the contract for
/// the one-shot legacy savedPref → preset import that runs after
/// V2FormatPresetMigration in main.dart Phase B.2.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Build a saved-pref JSON map matching the legacy
  /// SettingsLocalDatasource shape (`platform_db_string`: { ... }).
  Map<String, dynamic> savedPrefRecord({
    required String qualityText,
    required String mediaType,
    String? containerFormat,
    int? maxResolution,
  }) {
    return <String, dynamic>{
      'platform': 'youtube', // ignored, key is authoritative
      'qualityText': qualityText,
      'mediaType': mediaType,
      'savedAt': DateTime(2026, 1, 1).toIso8601String(),
      if (containerFormat != null) 'containerFormat': containerFormat,
      if (maxResolution != null) 'maxResolution': maxResolution,
    };
  }

  group('V2SavedPrefToPresetImporter — first-run paths', () {
    test('no saved-prefs → flag set, 0 imported', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      final count = await importer.run();
      expect(count, 0);
      expect(prefs.getBool('imported_savedprefs_v1'), isTrue);
    });

    test('flag already set → skip without scanning', () async {
      SharedPreferences.setMockInitialValues({
        'imported_savedprefs_v1': true,
        'settings_platform_preferences': jsonEncode({
          'tiktok': savedPrefRecord(
            qualityText: '1080p MP4',
            mediaType: 'video',
            maxResolution: 1080,
          ),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      final count = await importer.run();
      expect(count, 0);
      // No write to format_presets — the flag short-circuits the run.
      expect(prefs.getString('format_presets'), isNull);
    });

    test('corrupt savedPref JSON → flag set, 0 imported, no throw',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': '{not valid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      final count = await importer.run();
      expect(count, 0);
      expect(prefs.getBool('imported_savedprefs_v1'), isTrue);
    });
  });

  group('V2SavedPrefToPresetImporter — successful import', () {
    test('imports each saved-pref as preset shadow with platform prefix',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'tiktok': savedPrefRecord(
            qualityText: '1080p MP4',
            mediaType: 'video',
            maxResolution: 1080,
            containerFormat: 'mp4',
          ),
          'youtube': savedPrefRecord(
            qualityText: '720p',
            mediaType: 'video',
            maxResolution: 720,
          ),
        }),
        // Existing format_presets list (V2 migration already ran).
        'format_presets': jsonEncode(
          BuiltinPresetsSeeder.canonicalBuiltins()
              .map((p) => p.toJson())
              .toList(),
        ),
      });
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      final count = await importer.run();
      expect(count, 2);

      final raw = prefs.getString('format_presets')!;
      final decoded = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      // 6 built-ins + 2 imported = 8.
      expect(decoded.length, 8);
      expect(
        decoded.any((m) => m['id'] == 'imported_tiktok'),
        isTrue,
      );
      expect(
        decoded.any((m) => m['id'] == 'imported_youtube'),
        isTrue,
      );

      final tiktokEntry = decoded.firstWhere(
        (m) => m['id'] == 'imported_tiktok',
      );
      // Name format depends on AppLocalizations.platformTiktok and
      // AppLocalizations.importedPresetName. In production both render
      // localised; in tests with i18n uninitialised, `.tr()` returns the
      // raw i18n keys (e.g. 'home.importedPresetName'). Accept either
      // form so the contract holds in both environments.
      final tiktokName = tiktokEntry['name'] as String;
      expect(
        tiktokName.contains('đã lưu') ||
            tiktokName.contains('home.importedPresetName'),
        isTrue,
        reason:
            'Expected localized "đã lưu" suffix or raw i18n key '
            '"home.importedPresetName", got "$tiktokName"',
      );
      expect(tiktokEntry['maxResolution'], 1080);
      expect(tiktokEntry['containerFormat'], 'mp4');
      expect(tiktokEntry['isBuiltIn'], false);
      expect(tiktokEntry['schemaVersion'], isNotNull);
      // Critical contract — imported presets must carry their
      // platformScope so PresetQualityMatcher returns ScopeMismatch
      // when the user activates them and pastes a different
      // platform's URL. Regression here = "TikTok preset bleeds into
      // YouTube download" review concern returns.
      expect(tiktokEntry['platformScope'], 'tiktok');

      final ytEntry = decoded.firstWhere(
        (m) => m['id'] == 'imported_youtube',
      );
      expect(ytEntry['platformScope'], 'youtube');
    });

    test('audio mediaType + qualityText "320 kbps" → audioBitrate parsed',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'youtube': savedPrefRecord(
            qualityText: 'MP3 320 kbps',
            mediaType: 'audio',
            containerFormat: 'mp3',
          ),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await V2SavedPrefToPresetImporter(prefs: prefs).run();

      final raw = prefs.getString('format_presets')!;
      final decoded = jsonDecode(raw) as List;
      final youtubeEntry =
          (decoded.firstWhere((m) => m['id'] == 'imported_youtube')
              as Map<String, dynamic>);
      expect(youtubeEntry['audioOnly'], isTrue);
      expect(youtubeEntry['audioBitrate'], 320);
      expect(youtubeEntry['containerFormat'], 'mp3');
    });

    test('audio mediaType without bitrate in qualityText → audioBitrate null',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'youtube': savedPrefRecord(
            qualityText: 'Audio only',
            mediaType: 'audio',
          ),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await V2SavedPrefToPresetImporter(prefs: prefs).run();

      final raw = prefs.getString('format_presets')!;
      final decoded = jsonDecode(raw) as List;
      final entry = (decoded.firstWhere((m) => m['id'] == 'imported_youtube')
          as Map<String, dynamic>);
      expect(entry['audioOnly'], isTrue);
      expect(entry['audioBitrate'], isNull);
      // Falls back to mp3 default for audio with no explicit container.
      expect(entry['containerFormat'], 'mp3');
    });

    test('idempotent: re-running with flag set → no duplicates', () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'tiktok': savedPrefRecord(
            qualityText: '1080p MP4',
            mediaType: 'video',
            maxResolution: 1080,
          ),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      // First run imports.
      final first = await importer.run();
      expect(first, 1);

      // Second run short-circuits via flag.
      final second = await importer.run();
      expect(second, 0);

      final decoded = jsonDecode(prefs.getString('format_presets')!) as List;
      final tiktokCount =
          decoded.where((m) => m['id'] == 'imported_tiktok').length;
      expect(tiktokCount, 1);
    });

    test('existing entry with same id → not double-inserted', () async {
      // Simulate a flag-cleared re-run scenario where format_presets
      // already has an `imported_tiktok` record. The dedup-by-id guard
      // must skip rather than create a duplicate.
      final preExisting = FormatPresetExtended(
        id: 'imported_tiktok',
        name: '📌 TikTok (đã lưu)',
        isBuiltIn: false,
        maxResolution: 720,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime(2026, 1, 1),
      );
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'tiktok': savedPrefRecord(
            qualityText: '1080p MP4',
            mediaType: 'video',
            maxResolution: 1080,
          ),
        }),
        'format_presets': jsonEncode([preExisting.toJson()]),
        // Flag cleared deliberately.
      });
      final prefs = await SharedPreferences.getInstance();
      final importer = V2SavedPrefToPresetImporter(prefs: prefs);

      final count = await importer.run();
      expect(count, 0);

      final decoded = jsonDecode(prefs.getString('format_presets')!) as List;
      final tiktokCount =
          decoded.where((m) => m['id'] == 'imported_tiktok').length;
      expect(tiktokCount, 1);
    });

    test('skips unknown platform db strings without crashing', () async {
      SharedPreferences.setMockInitialValues({
        'settings_platform_preferences': jsonEncode({
          'tiktok': savedPrefRecord(
            qualityText: '1080p',
            mediaType: 'video',
            maxResolution: 1080,
          ),
          'fake-platform-from-future': savedPrefRecord(
            qualityText: '4k',
            mediaType: 'video',
            maxResolution: 2160,
          ),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final count = await V2SavedPrefToPresetImporter(prefs: prefs).run();
      // tiktok imports; fake-platform may parse as `unknown` (legitimate
      // VideoPlatform fallback) or be skipped — either way the
      // importer must not throw and must not set a partial state.
      expect(count, greaterThanOrEqualTo(1));
      expect(prefs.getBool('imported_savedprefs_v1'), isTrue);
    });
  });
}
