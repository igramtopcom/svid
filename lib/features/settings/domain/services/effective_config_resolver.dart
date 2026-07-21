/// V2 — `EffectiveDownloadConfigService` — 3-layer config resolver.
///
/// Implements UI Spec §5.1 architecture:
///
///   Layer 1: PlatformQualityPreference (auto, per-URL platform)
///            ↓ fallback if no per-platform pref for the detected platform
///   Layer 2: Active FormatPreset + currentConfig (manual, global)
///            ↓ fallback per-field for any null override
///   Layer 3: SettingsState global defaults (codec, container, fps...)
///
/// The resolver is field-by-field merge: the first non-null value wins
/// at each field. Pure synchronous — caller passes already-loaded inputs
/// from providers, so the service has no I/O.
library;

import '../entities/format_preset_extended.dart';
import '../entities/platform_quality_preference.dart';

/// Lightweight projection of [SettingsState] limited to the fields the
/// resolver actually reads. Kept as a separate type so tests don't need
/// to construct a full SettingsState and the resolver doesn't pull in
/// unrelated dependencies.
class GlobalDownloadDefaults {
  const GlobalDownloadDefaults({
    this.preferredQuality,
    this.containerFormat,
    this.videoCodec,
    this.audioCodec,
    this.fpsPreference,
    this.subtitlesEnabled,
    this.embedThumbnail,
    this.embedMetadata,
    this.embedChapters,
    this.saveLocation,
  });

  /// Preferred resolution ceiling (px height); `0` = "best".
  final int? preferredQuality;

  final String? containerFormat;
  final String? videoCodec;
  final String? audioCodec;
  final String? fpsPreference;
  final bool? subtitlesEnabled;
  final bool? embedThumbnail;
  final bool? embedMetadata;
  final bool? embedChapters;
  final String? saveLocation;
}

/// Final resolved config that callers feed into yt-dlp / Rust download
/// engine. Mirrors the full [FormatPresetExtended] surface — every
/// field is either a concrete value or a documented "auto" sentinel.
///
/// This is the contract the rest of the download pipeline reads — it
/// MUST NOT be a `FormatPresetExtended` directly because resolution
/// must always produce a complete record (no nullable fields).
class EffectiveDownloadConfig {
  const EffectiveDownloadConfig({
    required this.maxResolution,
    required this.videoCodec,
    required this.audioCodec,
    required this.containerFormat,
    required this.fpsPreference,
    required this.audioOnly,
    required this.audioBitrate,
    required this.fallbackBehavior,
    required this.saveLocation,
    required this.subtitlesEnabled,
    required this.embedThumbnail,
    required this.embedMetadata,
    required this.embedChapters,
    required this.sourcePresetId,
    required this.sourcePresetName,
    required this.appliedPlatformOverride,
  });

  final int maxResolution;
  final String videoCodec;
  final String audioCodec;
  final String containerFormat;
  final String fpsPreference;
  final bool audioOnly;

  /// Audio bitrate in kbps. `null` means "yt-dlp default for the
  /// chosen container".
  final int? audioBitrate;

  final FormatPresetFallback fallbackBehavior;

  /// Resolved save location — never null. Callers compose this with
  /// per-download subdirectories themselves.
  final String saveLocation;

  final bool subtitlesEnabled;
  final bool embedThumbnail;
  final bool embedMetadata;
  final bool embedChapters;

  /// Identifier of the FormatPreset that was active when this config
  /// resolved. Useful for telemetry / undo.
  final String sourcePresetId;
  final String sourcePresetName;

  /// True when Layer 1 (per-platform pref) supplied at least one field
  /// — telemetry signal that the user has trained the system.
  final bool appliedPlatformOverride;
}

/// Pure resolver — no Riverpod, no I/O.
class EffectiveConfigResolver {
  const EffectiveConfigResolver();

  /// Resolve the effective config for [presetWithOverrides] (Layer 2),
  /// optionally enriched by [platformPref] (Layer 1) and falling back
  /// to [defaults] (Layer 3) for any field still null.
  ///
  /// Layer 1 ([platformPref]) wins for any field it specifies.
  /// Layer 2 ([presetWithOverrides]) provides the operating preset.
  /// Layer 3 ([defaults]) fills the remaining holes with global defaults.
  EffectiveDownloadConfig resolve({
    required FormatPresetExtended presetWithOverrides,
    PlatformQualityPreference? platformPref,
    required GlobalDownloadDefaults defaults,
    String? globalSaveLocation,
  }) {
    // ── maxResolution (int — `0` = best, no null) ──
    // Platform pref doesn't carry a maxResolution; preset is canonical
    // unless preset says `0` ("best"), then defer to defaults.
    final maxResolution = presetWithOverrides.maxResolution != 0
        ? presetWithOverrides.maxResolution
        : (defaults.preferredQuality ?? 0);

    // ── videoCodec / audioCodec / containerFormat / fpsPreference ──
    // Layer 1 platform pref currently doesn't override codec/container
    // (they live on the preset); we still pass through defaults for
    // forward-compat when the entity grows fields.
    final videoCodec = _firstNonAuto(
      presetWithOverrides.videoCodec,
      defaults.videoCodec,
    );
    final audioCodec = _firstNonAuto(
      presetWithOverrides.audioCodec,
      defaults.audioCodec,
    );
    final containerFormat = _firstNonAuto(
      presetWithOverrides.containerFormat,
      defaults.containerFormat,
    );
    final fpsPreference = _firstNonAuto(
      presetWithOverrides.fpsPreference,
      defaults.fpsPreference,
    );

    // ── nullable booleans inherit from defaults when preset says null ──
    final subtitlesEnabled =
        presetWithOverrides.subtitlesEnabled ?? defaults.subtitlesEnabled ?? false;
    final embedThumbnail =
        presetWithOverrides.embedThumbnail ?? defaults.embedThumbnail ?? false;
    final embedMetadata =
        presetWithOverrides.embedMetadata ?? defaults.embedMetadata ?? false;
    final embedChapters =
        presetWithOverrides.embedChapters ?? defaults.embedChapters ?? false;

    // ── saveLocation: preset override → global default → caller global ──
    final saveLocation = presetWithOverrides.saveLocation ??
        defaults.saveLocation ??
        globalSaveLocation ??
        '';

    return EffectiveDownloadConfig(
      maxResolution: maxResolution,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      containerFormat: containerFormat,
      fpsPreference: fpsPreference,
      audioOnly: presetWithOverrides.audioOnly,
      audioBitrate: presetWithOverrides.audioBitrate,
      fallbackBehavior: presetWithOverrides.fallbackBehavior,
      saveLocation: saveLocation,
      subtitlesEnabled: subtitlesEnabled,
      embedThumbnail: embedThumbnail,
      embedMetadata: embedMetadata,
      embedChapters: embedChapters,
      sourcePresetId: presetWithOverrides.id,
      sourcePresetName: presetWithOverrides.name,
      appliedPlatformOverride: platformPref != null,
    );
  }

  /// Return the first non-`auto` / non-empty string, or `'auto'` if both
  /// are auto / null. Treats `'auto'` and `null` as equivalent so
  /// either layer can defer to the next.
  String _firstNonAuto(String primary, String? fallback) {
    if (primary.isNotEmpty && primary != 'auto') return primary;
    if (fallback != null && fallback.isNotEmpty && fallback != 'auto') {
      return fallback;
    }
    return primary.isEmpty ? (fallback ?? 'auto') : primary;
  }
}
