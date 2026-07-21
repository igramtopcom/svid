/// V2 — One-shot import of legacy `settings_platform_preferences`
/// (per-platform saved-pref entries written by `DownloadConfigDialog`'s
/// "Save as preference" checkbox) into the new `format_presets` v2
/// store as discoverable [FormatPresetExtended] entries.
///
/// Why: pre-V2 the only "save my choice" UX was a checkbox buried in
/// the download dialog. Users had complete per-platform fingerprints
/// (TikTok=1080p MP4, YouTube=720p, IG=carousel etc.) but those entries
/// were invisible from the home command bar — the new chip popover
/// only knew about its 6 built-ins. This importer surfaces the user's
/// historical work as discoverable entries:
///
///   📌 TikTok (đã lưu)
///   📌 YouTube (đã lưu)
///   📌 Instagram (đã lưu)
///   …
///
/// Both stores remain authoritative for their original purposes:
///   - `settings_platform_preferences` — Rule 2 in HomeDownloadMixin
///     auto-applies the savedPref when the active preset doesn't match
///     and a user has stored a per-platform preference (legacy UX
///     intact, no behavior break).
///   - `format_presets` — chip popover profile selector + Rule 1.5
///     (active preset auto-pick). Imported entries become user-wide
///     when explicitly activated; until then they're informational.
///
/// Idempotent: writes a `imported_savedprefs_v1` boolean flag on first
/// successful run. Subsequent launches skip via the flag, even if the
/// user later deletes the imported presets in the popover.
///
/// Stable IDs (`imported_<platform_db_string>`) make the import safe
/// to re-run if the flag is ever cleared — duplicate IDs are filtered
/// against the existing list before write.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/downloads/domain/entities/video_info.dart';
import '../../features/settings/data/datasources/builtin_presets_seeder.dart';
import '../../features/settings/domain/entities/format_preset_extended.dart';
import '../l10n/app_localizations.dart';
import '../../features/settings/domain/entities/platform_quality_preference.dart';
import '../logging/app_logger.dart';
import '../utils/platform_detector.dart';

class V2SavedPrefToPresetImporter {
  V2SavedPrefToPresetImporter({required SharedPreferences prefs})
    : _prefs = prefs;

  final SharedPreferences _prefs;

  static const String _keyImportFlag = 'imported_savedprefs_v1';
  static const String _keySavedPrefs = 'settings_platform_preferences';

  /// Execute import. Returns the number of saved-prefs that were
  /// converted to presets. Zero is normal — fresh install / no
  /// pre-V2 saved-prefs / already imported.
  ///
  /// Never throws on bad data: malformed JSON or unknown platform db
  /// strings are logged and skipped so the importer can't brick app
  /// startup. Designed to run AFTER [V2FormatPresetMigration] in
  /// `main.dart` Phase B.1.
  Future<int> run() async {
    if (_prefs.getBool(_keyImportFlag) == true) {
      // Already imported once — even if the user deleted some entries
      // in the popover, we don't re-import. Re-importing would surprise
      // the user by recreating presets they intentionally removed.
      return 0;
    }

    final savedPrefsJson = _prefs.getString(_keySavedPrefs);
    if (savedPrefsJson == null || savedPrefsJson.isEmpty) {
      // No legacy saved-prefs to import. Set the flag so we don't
      // re-scan on every launch.
      await _prefs.setBool(_keyImportFlag, true);
      return 0;
    }

    final Map<String, dynamic> savedPrefsMap;
    try {
      final decoded = jsonDecode(savedPrefsJson);
      if (decoded is! Map<String, dynamic>) {
        await _prefs.setBool(_keyImportFlag, true);
        return 0;
      }
      savedPrefsMap = decoded;
    } catch (e, st) {
      appLogger.error(
        'V2SavedPrefToPresetImporter: corrupt savedPref JSON, skipping',
        e,
        st,
      );
      await _prefs.setBool(_keyImportFlag, true);
      return 0;
    }

    final imported = <FormatPresetExtended>[];
    for (final entry in savedPrefsMap.entries) {
      try {
        final platform = VideoPlatform.fromDbString(entry.key);
        final pref = PlatformQualityPreference.fromJson(
          entry.value as Map<String, dynamic>,
        );
        imported.add(_convertSavedPrefToPreset(platform, pref));
      } catch (e, st) {
        appLogger.warning(
          'V2SavedPrefToPresetImporter: skipping unparseable entry "${entry.key}"',
          e,
          st,
        );
      }
    }

    if (imported.isEmpty) {
      await _prefs.setBool(_keyImportFlag, true);
      return 0;
    }

    // Read the existing format_presets list (V2FormatPresetMigration
    // guarantees this key exists with v2-shaped records). Filter
    // duplicates against existing IDs so re-running this importer
    // (e.g. flag cleared by manual debug) doesn't double-insert.
    final existingList = _readExistingPresetMaps();

    final existingIds =
        existingList.map((m) => m['id'] as String?).whereType<String>().toSet();
    final newRecords = imported
        .where((p) => !existingIds.contains(p.id))
        .map((p) => p.toJson())
        .toList(growable: false);

    if (newRecords.isEmpty) {
      await _prefs.setBool(_keyImportFlag, true);
      return 0;
    }

    final merged = [...existingList, ...newRecords];
    await _prefs.setString(formatPresetsKey, jsonEncode(merged));
    await _prefs.setBool(_keyImportFlag, true);

    appLogger.info(
      'V2SavedPrefToPresetImporter: imported ${newRecords.length} '
      'saved-pref entr${newRecords.length == 1 ? "y" : "ies"} as preset shadows',
    );
    return newRecords.length;
  }

  List<Map<String, dynamic>> _readExistingPresetMaps() {
    final existingJson = _prefs.getString(formatPresetsKey);
    if (existingJson == null || existingJson.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(existingJson);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // Corrupt JSON — skip merge, just persist new entries fresh.
    }
    return const [];
  }

  /// Convert one [PlatformQualityPreference] into a discoverable
  /// [FormatPresetExtended]. Audio bitrate is parsed from qualityText
  /// (`"MP3 320 kbps"` → 320) when the saved-pref's media type is audio
  /// — that string format is what `DownloadConfigDialog` writes for
  /// audio Quality entries today.
  FormatPresetExtended _convertSavedPrefToPreset(
    VideoPlatform platform,
    PlatformQualityPreference pref,
  ) {
    final isAudio = pref.mediaType == MediaType.audio;

    int? audioBitrate;
    if (isAudio) {
      final match = RegExp(
        r'(\d+)\s*kbps',
        caseSensitive: false,
      ).firstMatch(pref.qualityText);
      if (match != null) {
        audioBitrate = int.tryParse(match.group(1) ?? '');
      }
    }

    // Default container per media type when the saved-pref didn't
    // specify (legacy users who just picked "1080p" without a codec/
    // container override). Matches the same defaults the legacy dialog
    // writes when fields are unset.
    final containerFormat = pref.containerFormat ?? (isAudio ? 'mp3' : 'mp4');

    return FormatPresetExtended(
      id: 'imported_${platform.toDbString()}',
      // English baseline; UI must resolve via [AppLocalizations
      // .homeImportedPresetName(platform)] at render time so locale switch
      // is live (em handle this at the active-preset-chip + preset-picker
      // render sites just like builtin presets).
      name: AppLocalizations.homeImportedPresetName(platform.displayName),
      isBuiltIn: false,
      maxResolution: pref.maxResolution ?? 0,
      videoCodec: pref.videoCodec ?? 'auto',
      audioCodec: pref.audioCodec ?? 'auto',
      containerFormat: containerFormat,
      fpsPreference: pref.fpsPreference ?? 'auto',
      audioOnly: isAudio,
      audioBitrate: audioBitrate,
      fallbackBehavior: FormatPresetFallback.nearest,
      saveLocation: null,
      subtitlesEnabled: pref.subtitlesEnabled,
      embedThumbnail: pref.embedThumbnail,
      embedMetadata: pref.embedMetadata,
      embedChapters: pref.embedChapters,
      // Platform-scoped: this preset only fires on this platform's
      // URLs, even when the user activates it. Mirrors the per-platform
      // semantic the original `settings_platform_preferences` record
      // had — activating "📌 TikTok (đã lưu)" doesn't bleed into
      // YouTube downloads. PresetQualityMatcher returns
      // PresetScopeMismatch for non-matching URLs, falling through to
      // Rule 2 (savedPref) → Rule 3 (dialog).
      platformScope: platform.toDbString(),
      schemaVersion: FormatPresetExtended.currentSchemaVersion,
      createdAt: pref.savedAt,
    );
  }
}
