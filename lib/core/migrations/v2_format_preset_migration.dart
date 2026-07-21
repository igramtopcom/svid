/// V2 — Legacy FormatPreset (7-field) → FormatPresetExtended (15-field)
/// migration. Implements UI Spec §17.2 verbatim.
///
/// Runs once at app upgrade from v1.x → v2.0. Idempotent: subsequent
/// runs detect `schemaVersion` and short-circuit. Backward-compatible:
/// missing fields receive safe defaults (see [FormatPresetExtended.fromJson]).
///
/// Built-in seeding is delegated to [BuiltinPresetsSeeder] — this file
/// only handles legacy record upgrade. The two helpers are called in
/// sequence from [V2FormatPresetMigration.run].
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../features/settings/data/datasources/builtin_presets_seeder.dart';
import '../../features/settings/domain/entities/format_preset_extended.dart';
import '../logging/app_logger.dart';

class V2FormatPresetMigration {
  const V2FormatPresetMigration({
    required SharedPreferences prefs,
    Uuid? uuidGen,
  })  : _prefs = prefs,
        _uuid = uuidGen ?? const Uuid();

  final SharedPreferences _prefs;
  final Uuid _uuid;

  /// Execute migration + seeding in the canonical order:
  ///   1. Read existing `format_presets` SharedPref (may be missing).
  ///   2. If missing → seed built-ins only and return.
  ///   3. If records have `schemaVersion` already → skip migration.
  ///   4. Otherwise upgrade each legacy record to v2 schema (UUID + 8
  ///      new fields with defaults) and persist.
  ///   5. Seed any missing built-in IDs on top of the migrated list.
  ///
  /// Designed to never throw on bad user data: malformed JSON is logged
  /// and the migration falls through to a clean built-in seed so the
  /// user is never blocked from launching the app.
  Future<({int migratedCount, int seededCount, bool skippedAlreadyMigrated})>
      run() async {
    final raw = _prefs.getString(formatPresetsKey);

    // Path A — first run / clean install: seed built-ins, no migration.
    if (raw == null || raw.isEmpty) {
      final seeded = await BuiltinPresetsSeeder(prefs: _prefs).ensureSeeded();
      appLogger.info(
        'V2FormatPresetMigration: clean install, seeded $seeded built-ins',
      );
      return (
        migratedCount: 0,
        seededCount: seeded,
        skippedAlreadyMigrated: false,
      );
    }

    final List<Map<String, dynamic>> legacyList;
    try {
      legacyList = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (e, st) {
      // Path C — corrupt JSON. Recover by overwriting with built-in seed
      // so the user is never blocked. The lost custom presets are an
      // acceptable trade vs hard-locking the app.
      appLogger.error(
        'V2FormatPresetMigration: corrupt format_presets JSON, '
        'recovering by reseed',
        e,
        st,
      );
      await _prefs.remove(formatPresetsKey);
      final seeded = await BuiltinPresetsSeeder(prefs: _prefs).ensureSeeded();
      return (
        migratedCount: 0,
        seededCount: seeded,
        skippedAlreadyMigrated: false,
      );
    }

    // Path B — already migrated: every record has `schemaVersion`. Skip
    // upgrade but still run the seeder in case a built-in was deleted
    // or a new built-in shipped in a later v2.x release.
    final allMigrated =
        legacyList.isNotEmpty && legacyList.every((r) => r['schemaVersion'] != null);
    if (allMigrated) {
      final seeded = await BuiltinPresetsSeeder(prefs: _prefs).ensureSeeded();
      appLogger.info(
        'V2FormatPresetMigration: already migrated, seeded $seeded missing built-ins',
      );
      return (
        migratedCount: 0,
        seededCount: seeded,
        skippedAlreadyMigrated: true,
      );
    }

    // Path D — legacy 7-field records present. Upgrade each.
    final upgradedJson = legacyList.map(_upgradeLegacyRecord).toList();
    final encoded = jsonEncode(upgradedJson);
    await _prefs.setString(formatPresetsKey, encoded);

    final seeded = await BuiltinPresetsSeeder(prefs: _prefs).ensureSeeded();
    appLogger.info(
      'V2FormatPresetMigration: migrated ${upgradedJson.length} legacy records, '
      'seeded $seeded built-ins',
    );
    return (
      migratedCount: upgradedJson.length,
      seededCount: seeded,
      skippedAlreadyMigrated: false,
    );
  }

  /// Convert one legacy record to the v2 15-field schema. Preserves all
  /// 7 legacy fields verbatim and fills the 8 new fields with safe
  /// defaults per Spec §17.2.
  ///
  /// Returns a JSON map (not a [FormatPresetExtended]) so the caller
  /// re-encodes once with `jsonEncode` — avoids a double object
  /// allocation per record.
  Map<String, dynamic> _upgradeLegacyRecord(Map<String, dynamic> old) {
    return {
      // Legacy fields preserved as-is.
      'name': old['name'] as String? ?? 'Untitled',
      'maxResolution': (old['maxResolution'] as num?)?.toInt() ?? 0,
      'videoCodec': old['videoCodec'] as String? ?? 'auto',
      'audioCodec': old['audioCodec'] as String? ?? 'auto',
      'containerFormat': old['containerFormat'] as String? ?? 'mp4',
      'fpsPreference': old['fpsPreference'] as String? ?? 'auto',
      'createdAt':
          old['createdAt'] as String? ?? DateTime.now().toIso8601String(),

      // New fields — generate UUID + safe defaults per §17.2.
      'id': _uuid.v4(),
      'isBuiltIn': false,
      'audioOnly': false,
      'audioBitrate': null,
      'fallbackBehavior': FormatPresetFallback.nearest.name,
      'saveLocation': null,
      'subtitlesEnabled': null,
      'embedThumbnail': null,
      'embedMetadata': null,
      'embedChapters': null,
      'schemaVersion': FormatPresetExtended.currentSchemaVersion,
    };
  }
}
