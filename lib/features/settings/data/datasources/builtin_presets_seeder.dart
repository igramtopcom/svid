/// V2 — Built-in FormatPreset seeder.
///
/// Idempotently seeds the six built-in profiles defined in UI Spec §5.3
/// into SharedPreferences key `format_presets`. Built-ins use stable
/// well-known IDs (not UUID) so subsequent launches recognise them and
/// the migration script can detect "already seeded" without rewriting.
///
/// Built-ins are read-only (`isBuiltIn = true`) — the user can clone but
/// never edit / delete them. Cloning produces a new user-owned record
/// with a fresh UUID and `isBuiltIn = false`.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/format_preset_extended.dart';

/// SharedPreferences key — kept canonical with the legacy
/// `FormatPresetsNotifier._key` so v1 + v2 read the same bucket.
const String formatPresetsKey = 'format_presets';

/// Stable IDs for the six built-in profiles. Engineers reference these
/// constants — never the literal strings — so a future rename has a
/// single edit point.
class BuiltinPresetIds {
  BuiltinPresetIds._();
  static const String auto = 'auto';
  static const String mp4_1080p = '1080p_mp4';
  static const String compact_720p = '720p_compact';
  static const String audioMp3_320 = 'audio_mp3_320';
  static const String max_4k = '4k_max';
  static const String archive = 'archive';

  static const List<String> all = [
    auto,
    mp4_1080p,
    compact_720p,
    audioMp3_320,
    max_4k,
    archive,
  ];
}

/// Seeds & validates the built-in preset set.
///
/// Pure logic — accepts a [SharedPreferences] handle so tests can pass
/// an in-memory mock and assert behavior deterministically.
class BuiltinPresetsSeeder {
  const BuiltinPresetsSeeder({required SharedPreferences prefs})
      : _prefs = prefs;

  final SharedPreferences _prefs;

  /// Build canonical [FormatPresetExtended] for each built-in ID. The
  /// `createdAt` is fixed at the v2 epoch so seed records are stable
  /// across launches (don't differ from device to device).
  static List<FormatPresetExtended> canonicalBuiltins({
    DateTime? seedTimestamp,
  }) {
    final now = seedTimestamp ?? DateTime.utc(2026, 5, 5);
    return [
      // Default profile — let yt-dlp pick the best available format.
      // Stored `name` is the English baseline; UI must resolve via
      // [AppLocalizations.builtinPresetName(id)] when `isBuiltIn=true` so
      // existing devices with a previously-seeded Vietnamese literal still
      // render in the user's current locale (the stored value is shadow-only).
      FormatPresetExtended(
        id: BuiltinPresetIds.auto,
        name: 'Auto (highest)',
        isBuiltIn: true,
        maxResolution: 0,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'auto',
        fpsPreference: 'auto',
        fallbackBehavior: FormatPresetFallback.nearest,
        createdAt: now,
      ),
      // Common HD video bundle.
      FormatPresetExtended(
        id: BuiltinPresetIds.mp4_1080p,
        name: '1080p MP4',
        isBuiltIn: true,
        maxResolution: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        fallbackBehavior: FormatPresetFallback.nearest,
        createdAt: now,
      ),
      // Compact / data-saver bundle.
      FormatPresetExtended(
        id: BuiltinPresetIds.compact_720p,
        name: '720p data-saver',
        isBuiltIn: true,
        maxResolution: 720,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        fallbackBehavior: FormatPresetFallback.nearest,
        createdAt: now,
      ),
      // Audio-only — popular for music ripping.
      FormatPresetExtended(
        id: BuiltinPresetIds.audioMp3_320,
        name: 'Audio MP3 320k',
        isBuiltIn: true,
        maxResolution: 0,
        videoCodec: 'auto',
        audioCodec: 'mp3',
        containerFormat: 'mp3',
        fpsPreference: 'auto',
        audioOnly: true,
        audioBitrate: 320,
        fallbackBehavior: FormatPresetFallback.nearest,
        createdAt: now,
      ),
      // Max quality — power users / archivists.
      FormatPresetExtended(
        id: BuiltinPresetIds.max_4k,
        name: '4K maximum',
        isBuiltIn: true,
        maxResolution: 2160,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        fallbackBehavior: FormatPresetFallback.nearest,
        createdAt: now,
      ),
      // Archival — best codec + subs + metadata + chapters.
      FormatPresetExtended(
        id: BuiltinPresetIds.archive,
        name: 'Archive',
        isBuiltIn: true,
        maxResolution: 0,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'mkv',
        fpsPreference: 'auto',
        fallbackBehavior: FormatPresetFallback.nearest,
        subtitlesEnabled: true,
        embedThumbnail: true,
        embedMetadata: true,
        embedChapters: true,
        createdAt: now,
      ),
    ];
  }

  /// Seed missing built-ins into the existing list. Idempotent — safe
  /// to call on every launch. Returns the **count of new built-ins
  /// inserted** for telemetry / startup logs.
  Future<int> ensureSeeded() async {
    final existing = _readExisting();
    final existingIds = existing.map((p) => p.id).toSet();
    final missing = canonicalBuiltins()
        .where((p) => !existingIds.contains(p.id))
        .toList();

    if (missing.isEmpty) return 0;

    final merged = [...existing, ...missing];
    await _writeAll(merged);
    return missing.length;
  }

  List<FormatPresetExtended> _readExisting() {
    final raw = _prefs.getString(formatPresetsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(FormatPresetExtended.fromJson)
          .toList(growable: false);
    } catch (_) {
      // Corrupt JSON → treat as empty; the migration step has its own
      // recovery path. We don't throw here so a single malformed user
      // record can't brick the entire startup flow.
      return const [];
    }
  }

  Future<void> _writeAll(List<FormatPresetExtended> list) async {
    final encoded = jsonEncode(list.map((p) => p.toJson()).toList());
    await _prefs.setString(formatPresetsKey, encoded);
  }
}
