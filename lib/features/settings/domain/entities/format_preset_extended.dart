/// V2 — Extended FormatPreset entity.
///
/// Replaces the legacy 7-field [FormatPreset] in
/// `lib/features/settings/data/datasources/format_presets_service.dart`
/// with the 15-field schema described in UI Spec §5.3 + §17.2. Backward-
/// compatible JSON: missing fields fall back to safe defaults so users
/// rolling between v1 ↔ v2 don't lose data (Spec §17.3).
///
/// Built-in presets (`isBuiltIn = true`) are read-only — the user can
/// clone but never edit / delete them. The `schemaVersion` field lets
/// future migrations detect "already migrated" records.
///
/// Hand-rolled (no `freezed`) to keep the V2 entry block free of codegen
/// dependencies; can be swapped to freezed later without API changes.
library;

/// Quality fallback strategy when the requested resolution isn't
/// available for a particular video.
enum FormatPresetFallback {
  /// Pick the closest available quality (default — least surprise).
  nearest,

  /// Round up to the next higher quality if available.
  higher,

  /// Block the download and surface an error to the user.
  block;

  static FormatPresetFallback fromJson(Object? value) {
    if (value is String) {
      for (final v in values) {
        if (v.name == value) return v;
      }
    }
    return nearest;
  }
}

/// Audio container hint when [FormatPresetExtended.audioOnly] is true.
/// Mirrors the strings used by yt-dlp's `--audio-format`.
class AudioBitrateHint {
  AudioBitrateHint._();

  /// Common preset bitrates. Kept as a const list (not enum) because the
  /// underlying field accepts any positive integer in kbps.
  static const List<int> commonValues = [128, 192, 256, 320];
}

class FormatPresetExtended {
  /// Stable identifier (UUID v4 for user-created presets, well-known
  /// strings for built-ins: `auto`, `1080p_mp4`, `720p_compact`,
  /// `audio_mp3_320`, `4k_max`, `archive`).
  final String id;

  /// Human-readable name shown in the popover profile selector.
  final String name;

  /// Whether the preset ships with the app and cannot be edited / deleted.
  /// Users can clone built-ins to make a custom variant.
  final bool isBuiltIn;

  /// Maximum video height in pixels. `0` = "best available".
  final int maxResolution;

  /// Preferred video codec (e.g. `h264`, `vp9`, `auto`).
  final String videoCodec;

  /// Preferred audio codec (e.g. `aac`, `opus`, `auto`).
  final String audioCodec;

  /// Container format: `mp4`, `webm`, `mkv`, `mp3`, `m4a`, `auto`, ...
  final String containerFormat;

  /// Frame rate preference: `auto`, `30`, `60`.
  final String fpsPreference;

  /// When true the preset only downloads the audio track. The video
  /// resolution / codec fields are ignored except for fallback display.
  final bool audioOnly;

  /// Audio bitrate in kbps. `null` = use yt-dlp default for the chosen
  /// container. Common values listed in [AudioBitrateHint.commonValues].
  final int? audioBitrate;

  /// What to do when the exact requested quality isn't available.
  final FormatPresetFallback fallbackBehavior;

  /// Per-preset save folder. `null` = use the global download path
  /// from settings.
  final String? saveLocation;

  /// `null` = inherit global subtitle setting from [SettingsState].
  final bool? subtitlesEnabled;

  /// `null` = inherit global "embed thumbnail" toggle.
  final bool? embedThumbnail;

  /// `null` = inherit global "embed metadata" toggle.
  final bool? embedMetadata;

  /// `null` = inherit global "embed chapters" toggle.
  final bool? embedChapters;

  /// Per-platform scope (Spec §5.4 — scope tag synthesis).
  ///
  ///   - `null` → universal preset, fires on any platform.
  ///   - `<VideoPlatform>.toDbString()` (e.g. `'tiktok'`, `'youtube'`)
  ///     → preset only auto-picks when the URL's platform matches.
  ///
  /// Used by [PresetQualityMatcher] + Rule 1.5 in
  /// `HomeDownloadMixin.handleDownloadDecision` to honour the
  /// per-platform semantic that legacy `settings_platform_preferences`
  /// records had: a preset named "📌 TikTok (đã lưu)" must apply to
  /// TikTok URLs only when activated, not silently bleed into YouTube
  /// downloads. Built-in presets and user-typed custom presets default
  /// to `null` (universal).
  final String? platformScope;

  /// Migration tracking. Bump on every breaking schema change so
  /// migration code can short-circuit when records are already up to
  /// date. v2.0 ships at version 1.
  final int schemaVersion;

  final DateTime createdAt;

  const FormatPresetExtended({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    required this.maxResolution,
    required this.videoCodec,
    required this.audioCodec,
    required this.containerFormat,
    required this.fpsPreference,
    this.audioOnly = false,
    this.audioBitrate,
    this.fallbackBehavior = FormatPresetFallback.nearest,
    this.saveLocation,
    this.subtitlesEnabled,
    this.embedThumbnail,
    this.embedMetadata,
    this.embedChapters,
    this.platformScope,
    this.schemaVersion = 1,
    required this.createdAt,
  });

  /// Current schema version literal — bumped only when a NEW field is
  /// added that older clients can't safely default to.
  static const int currentSchemaVersion = 1;

  FormatPresetExtended copyWith({
    String? id,
    String? name,
    bool? isBuiltIn,
    int? maxResolution,
    String? videoCodec,
    String? audioCodec,
    String? containerFormat,
    String? fpsPreference,
    bool? audioOnly,
    Object? audioBitrate = _sentinel,
    FormatPresetFallback? fallbackBehavior,
    Object? saveLocation = _sentinel,
    Object? subtitlesEnabled = _sentinel,
    Object? embedThumbnail = _sentinel,
    Object? embedMetadata = _sentinel,
    Object? embedChapters = _sentinel,
    Object? platformScope = _sentinel,
    int? schemaVersion,
    DateTime? createdAt,
  }) {
    return FormatPresetExtended(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      maxResolution: maxResolution ?? this.maxResolution,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      containerFormat: containerFormat ?? this.containerFormat,
      fpsPreference: fpsPreference ?? this.fpsPreference,
      audioOnly: audioOnly ?? this.audioOnly,
      audioBitrate: identical(audioBitrate, _sentinel)
          ? this.audioBitrate
          : audioBitrate as int?,
      fallbackBehavior: fallbackBehavior ?? this.fallbackBehavior,
      saveLocation: identical(saveLocation, _sentinel)
          ? this.saveLocation
          : saveLocation as String?,
      subtitlesEnabled: identical(subtitlesEnabled, _sentinel)
          ? this.subtitlesEnabled
          : subtitlesEnabled as bool?,
      embedThumbnail: identical(embedThumbnail, _sentinel)
          ? this.embedThumbnail
          : embedThumbnail as bool?,
      embedMetadata: identical(embedMetadata, _sentinel)
          ? this.embedMetadata
          : embedMetadata as bool?,
      embedChapters: identical(embedChapters, _sentinel)
          ? this.embedChapters
          : embedChapters as bool?,
      platformScope: identical(platformScope, _sentinel)
          ? this.platformScope
          : platformScope as String?,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isBuiltIn': isBuiltIn,
        'maxResolution': maxResolution,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'containerFormat': containerFormat,
        'fpsPreference': fpsPreference,
        'audioOnly': audioOnly,
        'audioBitrate': audioBitrate,
        'fallbackBehavior': fallbackBehavior.name,
        'saveLocation': saveLocation,
        'subtitlesEnabled': subtitlesEnabled,
        'embedThumbnail': embedThumbnail,
        'embedMetadata': embedMetadata,
        'embedChapters': embedChapters,
        'platformScope': platformScope,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Tolerant JSON parse. Missing fields receive safe defaults so the
  /// same parser handles legacy 7-field records (when wrapped by the
  /// migration helper) and current 15-field records.
  factory FormatPresetExtended.fromJson(Map<String, dynamic> json) {
    return FormatPresetExtended(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      maxResolution: (json['maxResolution'] as num?)?.toInt() ?? 0,
      videoCodec: json['videoCodec'] as String? ?? 'auto',
      audioCodec: json['audioCodec'] as String? ?? 'auto',
      containerFormat: json['containerFormat'] as String? ?? 'mp4',
      fpsPreference: json['fpsPreference'] as String? ?? 'auto',
      audioOnly: json['audioOnly'] as bool? ?? false,
      audioBitrate: (json['audioBitrate'] as num?)?.toInt(),
      fallbackBehavior:
          FormatPresetFallback.fromJson(json['fallbackBehavior']),
      saveLocation: json['saveLocation'] as String?,
      subtitlesEnabled: json['subtitlesEnabled'] as bool?,
      embedThumbnail: json['embedThumbnail'] as bool?,
      embedMetadata: json['embedMetadata'] as bool?,
      embedChapters: json['embedChapters'] as bool?,
      // Backwards-compat: missing platformScope → null = universal.
      // Old v1 records (pre-scope-tag) load as universal presets, which
      // is the safe default — they were universally applicable before
      // the scope concept existed.
      platformScope: json['platformScope'] as String?,
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  static DateTime _parseDateTime(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

/// Sentinel used by [FormatPresetExtended.copyWith] to distinguish
/// "argument not provided" from "provided as null".
const Object _sentinel = Object();
