import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BuiltinPresetsSeeder.canonicalBuiltins', () {
    test('produces exactly 6 built-ins per Spec §5.3', () {
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      expect(builtins.length, 6);
    });

    test('all built-ins flagged isBuiltIn=true', () {
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      expect(builtins.every((p) => p.isBuiltIn), true);
    });

    test('IDs match BuiltinPresetIds.all', () {
      final ids =
          BuiltinPresetsSeeder.canonicalBuiltins().map((p) => p.id).toSet();
      expect(ids, BuiltinPresetIds.all.toSet());
    });

    test('audio_mp3_320 has audioOnly=true and 320kbps bitrate', () {
      final audio = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.audioMp3_320);
      expect(audio.audioOnly, true);
      expect(audio.audioBitrate, 320);
      expect(audio.containerFormat, 'mp3');
    });

    test('archive preset enables subs + metadata + chapters', () {
      final archive = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.archive);
      expect(archive.subtitlesEnabled, true);
      expect(archive.embedThumbnail, true);
      expect(archive.embedMetadata, true);
      expect(archive.embedChapters, true);
      expect(archive.containerFormat, 'mkv');
    });

    test('all built-ins use FormatPresetFallback.nearest by default', () {
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      expect(
        builtins.every((p) => p.fallbackBehavior == FormatPresetFallback.nearest),
        true,
      );
    });

    test('seedTimestamp parameter overrides createdAt for determinism', () {
      final epoch = DateTime.utc(2030, 1, 1);
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins(
        seedTimestamp: epoch,
      );
      expect(builtins.every((p) => p.createdAt == epoch), true);
    });
  });

  group('BuiltinPresetsSeeder.ensureSeeded', () {
    test('clean install seeds all 6 built-ins', () async {
      final prefs = await SharedPreferences.getInstance();
      final seeder = BuiltinPresetsSeeder(prefs: prefs);

      final inserted = await seeder.ensureSeeded();
      expect(inserted, 6);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 6);
    });

    test('idempotent — second run inserts 0', () async {
      final prefs = await SharedPreferences.getInstance();
      final seeder = BuiltinPresetsSeeder(prefs: prefs);

      await seeder.ensureSeeded();
      final inserted2 = await seeder.ensureSeeded();
      expect(inserted2, 0);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 6);
    });

    test('preserves existing user records, only adds missing built-ins',
        () async {
      // Pre-populate with one user preset; the seeder should preserve it
      // and add all 6 built-ins on top.
      final prefs = await SharedPreferences.getInstance();
      final userPreset = FormatPresetExtended(
        id: 'user-uuid-1',
        name: 'My Preset',
        isBuiltIn: false,
        maxResolution: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime.utc(2026),
      );
      await prefs.setString(
        formatPresetsKey,
        jsonEncode([userPreset.toJson()]),
      );

      final seeder = BuiltinPresetsSeeder(prefs: prefs);
      final inserted = await seeder.ensureSeeded();
      expect(inserted, 6);

      final raw = prefs.getString(formatPresetsKey)!;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      expect(list.length, 7); // 1 user + 6 builtins
      expect(list.any((m) => m['id'] == 'user-uuid-1'), true);
    });

    test('partial built-in set — only missing IDs inserted', () async {
      // Pre-seed with just `auto`; the rest should fill in.
      final prefs = await SharedPreferences.getInstance();
      final autoOnly = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.auto);
      await prefs.setString(formatPresetsKey, jsonEncode([autoOnly.toJson()]));

      final seeder = BuiltinPresetsSeeder(prefs: prefs);
      final inserted = await seeder.ensureSeeded();
      expect(inserted, 5);
    });

    test('corrupt JSON treated as empty (recovery, no throw)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(formatPresetsKey, '{not json[');

      final seeder = BuiltinPresetsSeeder(prefs: prefs);
      // Should not throw, should treat as empty + seed 6 built-ins.
      final inserted = await seeder.ensureSeeded();
      expect(inserted, 6);
    });
  });
}
