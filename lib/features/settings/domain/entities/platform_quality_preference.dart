import '../../../../core/utils/platform_detector.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';
import '../../../downloads/domain/entities/video_info.dart';

/// Saved quality preference for a specific platform.
/// Stores quality choice + optional format overrides (null = use global default).
/// JSON serialization is backward-compatible: old prefs without format fields load fine.
class PlatformQualityPreference {
  final VideoPlatform platform;
  final String qualityText; // e.g., "1080p MP4", "HD"
  final MediaType mediaType; // video, audio, image
  final DateTime savedAt;
  final DownloadFileType? fileType;
  final DownloadQualityIntent? qualityIntent;
  final PortableQualityTarget? qualityTarget;

  // Format overrides (null = use global default from SettingsState)
  final String? videoCodec; // enum name: "h264", "h265", "vp9", "av1", "auto"
  final String? audioCodec; // enum name: "aac", "opus", "mp3", "auto"
  final String? containerFormat; // enum name: "mp4", "mkv", "webm"
  final String? fpsPreference; // enum name: "auto", "prefer60", "prefer30"
  final int? maxResolution; // 0 = unlimited, or height value
  final bool? subtitlesEnabled;
  final List<String>? subtitlesLanguages;
  final String? subtitlesFormat;
  final bool? embedSubtitles;
  final bool? includeAutoSubs;
  final bool? writeThumbnail;
  final bool? sponsorBlockEnabled;
  final String? sponsorBlockAction;
  final List<String>? sponsorBlockCategories;
  final bool? forceRemux;
  final bool? tiktokRemoveWatermark;
  final bool? embedThumbnail;
  final bool? embedMetadata;
  final bool? embedChapters;

  const PlatformQualityPreference({
    required this.platform,
    required this.qualityText,
    required this.mediaType,
    required this.savedAt,
    this.fileType,
    this.qualityIntent,
    this.qualityTarget,
    this.videoCodec,
    this.audioCodec,
    this.containerFormat,
    this.fpsPreference,
    this.maxResolution,
    this.subtitlesEnabled,
    this.subtitlesLanguages,
    this.subtitlesFormat,
    this.embedSubtitles,
    this.includeAutoSubs,
    this.writeThumbnail,
    this.sponsorBlockEnabled,
    this.sponsorBlockAction,
    this.sponsorBlockCategories,
    this.forceRemux,
    this.tiktokRemoveWatermark,
    this.embedThumbnail,
    this.embedMetadata,
    this.embedChapters,
  });

  /// Convert to JSON for storage. Only writes non-null format fields.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'platform': platform.toDbString(),
      'qualityText': qualityText,
      'mediaType': mediaType.name,
      'savedAt': savedAt.toIso8601String(),
    };
    if (fileType != null) map['fileType'] = fileType!.toDbString();
    if (qualityIntent != null) {
      map['qualityIntent'] = qualityIntent!.toDbString();
    }
    if (qualityTarget != null) map['qualityTarget'] = qualityTarget!.toJson();
    if (videoCodec != null) map['videoCodec'] = videoCodec;
    if (audioCodec != null) map['audioCodec'] = audioCodec;
    if (containerFormat != null) map['containerFormat'] = containerFormat;
    if (fpsPreference != null) map['fpsPreference'] = fpsPreference;
    if (maxResolution != null) map['maxResolution'] = maxResolution;
    if (subtitlesEnabled != null) map['subtitlesEnabled'] = subtitlesEnabled;
    if (subtitlesLanguages != null) {
      map['subtitlesLanguages'] = subtitlesLanguages;
    }
    if (subtitlesFormat != null) map['subtitlesFormat'] = subtitlesFormat;
    if (embedSubtitles != null) map['embedSubtitles'] = embedSubtitles;
    if (includeAutoSubs != null) map['includeAutoSubs'] = includeAutoSubs;
    if (writeThumbnail != null) map['writeThumbnail'] = writeThumbnail;
    if (sponsorBlockEnabled != null) {
      map['sponsorBlockEnabled'] = sponsorBlockEnabled;
    }
    if (sponsorBlockAction != null) {
      map['sponsorBlockAction'] = sponsorBlockAction;
    }
    if (sponsorBlockCategories != null) {
      map['sponsorBlockCategories'] = sponsorBlockCategories;
    }
    if (forceRemux != null) map['forceRemux'] = forceRemux;
    if (tiktokRemoveWatermark != null) {
      map['tiktokRemoveWatermark'] = tiktokRemoveWatermark;
    }
    if (embedThumbnail != null) map['embedThumbnail'] = embedThumbnail;
    if (embedMetadata != null) map['embedMetadata'] = embedMetadata;
    if (embedChapters != null) map['embedChapters'] = embedChapters;
    return map;
  }

  /// Create from JSON. Backward-compatible: missing format fields default to null.
  factory PlatformQualityPreference.fromJson(Map<String, dynamic> json) {
    return PlatformQualityPreference(
      platform: VideoPlatform.fromDbString(json['platform'] as String),
      qualityText: json['qualityText'] as String,
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == json['mediaType'],
        orElse: () => MediaType.video,
      ),
      savedAt: DateTime.parse(json['savedAt'] as String),
      fileType:
          json['fileType'] is String
              ? DownloadFileType.fromDbString(json['fileType'] as String)
              : null,
      qualityIntent:
          json['qualityIntent'] is String
              ? DownloadQualityIntent.fromDbString(
                json['qualityIntent'] as String,
              )
              : null,
      qualityTarget:
          json['qualityTarget'] is Map<String, dynamic>
              ? PortableQualityTarget.fromJson(
                json['qualityTarget'] as Map<String, dynamic>,
              )
              : null,
      videoCodec: json['videoCodec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      containerFormat: json['containerFormat'] as String?,
      fpsPreference: json['fpsPreference'] as String?,
      maxResolution: json['maxResolution'] as int?,
      subtitlesEnabled: json['subtitlesEnabled'] as bool?,
      subtitlesLanguages:
          (json['subtitlesLanguages'] as List<dynamic>?)?.cast<String>(),
      subtitlesFormat: json['subtitlesFormat'] as String?,
      embedSubtitles: json['embedSubtitles'] as bool?,
      includeAutoSubs: json['includeAutoSubs'] as bool?,
      writeThumbnail: json['writeThumbnail'] as bool?,
      sponsorBlockEnabled: json['sponsorBlockEnabled'] as bool?,
      sponsorBlockAction: json['sponsorBlockAction'] as String?,
      sponsorBlockCategories:
          (json['sponsorBlockCategories'] as List<dynamic>?)?.cast<String>(),
      forceRemux: json['forceRemux'] as bool?,
      tiktokRemoveWatermark: json['tiktokRemoveWatermark'] as bool?,
      embedThumbnail: json['embedThumbnail'] as bool?,
      embedMetadata: json['embedMetadata'] as bool?,
      embedChapters: json['embedChapters'] as bool?,
    );
  }

  /// Whether this preference has any format overrides saved
  bool get hasFormatOverrides =>
      videoCodec != null ||
      audioCodec != null ||
      containerFormat != null ||
      fpsPreference != null ||
      maxResolution != null ||
      subtitlesEnabled != null ||
      subtitlesLanguages != null ||
      subtitlesFormat != null ||
      embedSubtitles != null ||
      includeAutoSubs != null ||
      writeThumbnail != null ||
      sponsorBlockEnabled != null ||
      sponsorBlockAction != null ||
      sponsorBlockCategories != null ||
      forceRemux != null ||
      tiktokRemoveWatermark != null ||
      embedThumbnail != null ||
      embedMetadata != null ||
      embedChapters != null;

  bool get hasPrimaryIntent =>
      fileType != null || qualityIntent != null || qualityTarget != null;

  PlatformQualityPreference copyWith({
    VideoPlatform? platform,
    String? qualityText,
    MediaType? mediaType,
    DateTime? savedAt,
    DownloadFileType? Function()? fileType,
    DownloadQualityIntent? Function()? qualityIntent,
    PortableQualityTarget? Function()? qualityTarget,
    String? Function()? videoCodec,
    String? Function()? audioCodec,
    String? Function()? containerFormat,
    String? Function()? fpsPreference,
    int? Function()? maxResolution,
    bool? Function()? subtitlesEnabled,
    List<String>? Function()? subtitlesLanguages,
    String? Function()? subtitlesFormat,
    bool? Function()? embedSubtitles,
    bool? Function()? includeAutoSubs,
    bool? Function()? writeThumbnail,
    bool? Function()? sponsorBlockEnabled,
    String? Function()? sponsorBlockAction,
    List<String>? Function()? sponsorBlockCategories,
    bool? Function()? forceRemux,
    bool? Function()? tiktokRemoveWatermark,
    bool? Function()? embedThumbnail,
    bool? Function()? embedMetadata,
    bool? Function()? embedChapters,
  }) {
    return PlatformQualityPreference(
      platform: platform ?? this.platform,
      qualityText: qualityText ?? this.qualityText,
      mediaType: mediaType ?? this.mediaType,
      savedAt: savedAt ?? this.savedAt,
      fileType: fileType != null ? fileType() : this.fileType,
      qualityIntent:
          qualityIntent != null ? qualityIntent() : this.qualityIntent,
      qualityTarget:
          qualityTarget != null ? qualityTarget() : this.qualityTarget,
      videoCodec: videoCodec != null ? videoCodec() : this.videoCodec,
      audioCodec: audioCodec != null ? audioCodec() : this.audioCodec,
      containerFormat:
          containerFormat != null ? containerFormat() : this.containerFormat,
      fpsPreference:
          fpsPreference != null ? fpsPreference() : this.fpsPreference,
      maxResolution:
          maxResolution != null ? maxResolution() : this.maxResolution,
      subtitlesEnabled:
          subtitlesEnabled != null ? subtitlesEnabled() : this.subtitlesEnabled,
      subtitlesLanguages:
          subtitlesLanguages != null
              ? subtitlesLanguages()
              : this.subtitlesLanguages,
      subtitlesFormat:
          subtitlesFormat != null ? subtitlesFormat() : this.subtitlesFormat,
      embedSubtitles:
          embedSubtitles != null ? embedSubtitles() : this.embedSubtitles,
      includeAutoSubs:
          includeAutoSubs != null ? includeAutoSubs() : this.includeAutoSubs,
      writeThumbnail:
          writeThumbnail != null ? writeThumbnail() : this.writeThumbnail,
      sponsorBlockEnabled:
          sponsorBlockEnabled != null
              ? sponsorBlockEnabled()
              : this.sponsorBlockEnabled,
      sponsorBlockAction:
          sponsorBlockAction != null
              ? sponsorBlockAction()
              : this.sponsorBlockAction,
      sponsorBlockCategories:
          sponsorBlockCategories != null
              ? sponsorBlockCategories()
              : this.sponsorBlockCategories,
      forceRemux: forceRemux != null ? forceRemux() : this.forceRemux,
      tiktokRemoveWatermark:
          tiktokRemoveWatermark != null
              ? tiktokRemoveWatermark()
              : this.tiktokRemoveWatermark,
      embedThumbnail:
          embedThumbnail != null ? embedThumbnail() : this.embedThumbnail,
      embedMetadata:
          embedMetadata != null ? embedMetadata() : this.embedMetadata,
      embedChapters:
          embedChapters != null ? embedChapters() : this.embedChapters,
    );
  }

  @override
  String toString() {
    final overrides = hasFormatOverrides ? ' +overrides' : '';
    return 'PlatformQualityPreference(platform: ${platform.displayName}, quality: $qualityText, type: $mediaType$overrides)';
  }
}
