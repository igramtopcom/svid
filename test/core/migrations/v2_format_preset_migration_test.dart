import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/migrations/v2_format_preset_migration.dart';
import 'package:ssvid/features/settings/data/datasources/builtin_presets_seeder.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('V2FormatPresetMigration.run', () {
    test('Path A — clean install seeds 6 built-ins, no migration', () async {
      final prefs = await SharedPreferences.getInstance();
      final result =
          await V2FormatPresetMigration(prefs: prefs).run();

      expect(result.migratedCount, 0);
      expect(result.seededCount, 6);
      expect(result.skippedAlreadyMigrated, false);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 6);
      // All seeded records carry schemaVersion = 1 marker.
      expect(list.every((r) => r['schemaVersion'] == 1), true);
    });

    test('Path D — legacy 7-field records upgrade to 15-field schema',
        () async {
      // Mimic v1.x SharedPreferences state with 2 user-created presets.
      final prefs = await SharedPreferences.getInstance();
      final legacy = [
        {
          'name': '1080p MP4',
          'maxResolution': 1080,
          'videoCodec': 'h264',
          'audioCodec': 'aac',
          'containerFormat': 'mp4',
          'fpsPreference': 'auto',
          'createdAt': '2025-12-01T10:00:00.000Z',
        },
        {
          'name': 'Audio bundle',
          'maxResolution': 0,
          'videoCodec': 'auto',
          'audioCodec': 'mp3',
          'containerFormat': 'mp3',
          'fpsPreference': 'auto',
          'createdAt': '2026-01-15T08:30:00.000Z',
        },
      ];
      await prefs.setString(formatPresetsKey, jsonEncode(legacy));

      final result =
          await V2FormatPresetMigration(prefs: prefs).run();

      // 2 legacy records upgraded.
      expect(result.migratedCount, 2);
      // Plus 6 built-ins seeded on top.
      expect(result.seededCount, 6);
      expect(result.skippedAlreadyMigrated, false);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 8); // 2 user + 6 builtins

      // Every upgraded record now has UUID + schemaVersion + 8 new fields.
      final upgradedUserRecords = list.where((r) => r['isBuiltIn'] == false);
      expect(upgradedUserRecords.length, 2);
      for (final r in upgradedUserRecords) {
        expect(r['id'], isA<String>());
        expect((r['id'] as String).length, greaterThan(20)); // UUID-shaped
        expect(r['schemaVersion'], 1);
        expect(r['audioOnly'], false);
        expect(r['fallbackBehavior'], 'nearest');
        expect(r['embedMetadata'], null); // null = inherit
      }

      // Original 7 fields still present + intact.
      final mp4 = upgradedUserRecords.firstWhere((r) => r['name'] == '1080p MP4');
      expect(mp4['maxResolution'], 1080);
      expect(mp4['videoCodec'], 'h264');
    });

    test('Path B — already migrated records are not double-migrated',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // First run does the migration.
      await V2FormatPresetMigration(prefs: prefs).run();
      final firstSnapshot = prefs.getString(formatPresetsKey);

      // Second run sees schemaVersion present → skips migration.
      final result2 = await V2FormatPresetMigration(prefs: prefs).run();
      expect(result2.skippedAlreadyMigrated, true);
      expect(result2.migratedCount, 0);
      expect(result2.seededCount, 0); // Nothing new to seed.

      expect(prefs.getString(formatPresetsKey), firstSnapshot);
    });

    test('Path B — re-seeds built-ins missing post-migration', () async {
      final prefs = await SharedPreferences.getInstance();
      await V2FormatPresetMigration(prefs: prefs).run();

      // Simulate a user deleting one built-in (e.g., archive).
      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final filtered = list
          .where((r) => r['id'] != BuiltinPresetIds.archive)
          .toList();
      await prefs.setString(formatPresetsKey, jsonEncode(filtered));

      // Re-run migration — built-in should be re-seeded back in.
      final result = await V2FormatPresetMigration(prefs: prefs).run();
      expect(result.skippedAlreadyMigrated, true);
      expect(result.seededCount, 1);
    });

    test('Path C — corrupt JSON recovers cleanly with built-in seed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(formatPresetsKey, '[{"name":');

      final result = await V2FormatPresetMigration(prefs: prefs).run();
      expect(result.migratedCount, 0);
      expect(result.seededCount, 6);
      expect(result.skippedAlreadyMigrated, false);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 6);
    });
  });
}
