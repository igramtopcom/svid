import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'download_selection_intent.dart';
import 'video_info.dart';

export 'download_selection_intent.dart';

/// Content selection mode for quality dialog
enum ContentMode {
  singleItem, // 1 quality → radio buttons
  multiItems, // Multiple same type → checkboxes
  mixedContent, // Images + Videos → tabs + checkboxes
}

/// Bundles quality selection + per-download format overrides.
/// Null override = use global settings from SettingsState.
class DownloadConfig {
  // Quality selection
  final List<Quality> selectedQualities;
  final DownloadFileType? fileType;
  final DownloadQualityIntent qualityIntent;
  final PortableQualityTarget? qualityTarget;

  // Format overrides (null = use global)
  final VideoCodecPreference? videoCodecOverride;
  final AudioCodecPreference? audioCodecOverride;
  final ContainerFormatPreference? containerFormatOverride;
  final FpsPreference? fpsOverride;
  final int? maxResolutionOverride; // null = use global, 0 = unlimited

  // Extras overrides (null = use global)
  final bool? subtitlesEnabled;
  final List<String>? subtitlesLanguages;
  final String? subtitlesFormat;
  final bool? embedSubtitles;
  final bool? includeAutoSubs;
  final bool? writeThumbnail;
  final bool? embedThumbnail;
  final bool? embedMetadata;
  final bool? embedChapters;
  final bool? sponsorBlockEnabled;
  final String? sponsorBlockAction;
  final List<String>? sponsorBlockCategories;
  final bool? forceRemux;
  final bool? tiktokRemoveWatermark;

  // Section selection (null = download full video)
  final Duration? sectionStartTime;
  final Duration? sectionEndTime;

  /// V2 reconcile: per-chapter selected time ranges (null = no chapter
  /// filter / download full). Each tuple is `(start, end)`. Per-video
  /// only — batch reuse path must clear via `copyWith` before applying.
  final List<(Duration, Duration)>? selectedChapterRanges;

  // Flow control
  final bool applyToAll;
  final bool rememberForPlatform;
  final bool saveAsDefault;
  final String? savePathOverride; // one-time base download path override

  const DownloadConfig({
    required this.selectedQualities,
    this.fileType,
    this.qualityIntent = DownloadQualityIntent.recommended,
    this.qualityTarget,
    this.videoCodecOverride,
    this.audioCodecOverride,
    this.containerFormatOverride,
    this.fpsOverride,
    this.maxResolutionOverride,
    this.subtitlesEnabled,
    this.subtitlesLanguages,
    this.subtitlesFormat,
    this.embedSubtitles,
    this.includeAutoSubs,
    this.writeThumbnail,
    this.embedThumbnail,
    this.embedMetadata,
    this.embedChapters,
    this.sponsorBlockEnabled,
    this.sponsorBlockAction,
    this.sponsorBlockCategories,
    this.forceRemux,
    this.tiktokRemoveWatermark,
    this.sectionStartTime,
    this.sectionEndTime,
    this.selectedChapterRanges,
    this.applyToAll = false,
    this.rememberForPlatform = false,
    this.saveAsDefault = false,
    this.savePathOverride,
  });

  // Resolve methods: override ?? global default

  VideoCodecPreference resolveVideoCodec(SettingsState s) =>
      videoCodecOverride ?? s.videoCodecPreference;

  AudioCodecPreference resolveAudioCodec(SettingsState s) =>
      audioCodecOverride ?? s.audioCodecPreference;

  ContainerFormatPreference resolveContainerFormat(SettingsState s) =>
      containerFormatOverride ?? s.containerFormatPreference;

  FpsPreference resolveFps(SettingsState s) => fpsOverride ?? s.fpsPreference;

  int resolveMaxResolution(SettingsState s) =>
      maxResolutionOverride ?? s.maxResolution;

  bool resolveSubtitlesEnabled(SettingsState s) =>
      subtitlesEnabled ?? s.subtitlesEnabled;

  List<String> resolveSubtitlesLanguages(SettingsState s) =>
      subtitlesLanguages ?? s.subtitlesLanguages;

  String resolveSubtitlesFormat(SettingsState s) =>
      subtitlesFormat ?? s.subtitlesFormat;

  bool resolveEmbedSubtitles(SettingsState s) =>
      embedSubtitles ?? s.embedSubtitles;

  bool resolveIncludeAutoSubs(SettingsState s) =>
      includeAutoSubs ?? s.includeAutoSubs;

  bool resolveWriteThumbnail(SettingsState s) =>
      writeThumbnail ?? s.writeThumbnail;

  bool resolveEmbedThumbnail(SettingsState s) =>
      embedThumbnail ?? s.embedThumbnail;

  bool resolveEmbedMetadata(SettingsState s) =>
      embedMetadata ?? s.embedMetadata;

  bool resolveEmbedChapters(SettingsState s) =>
      embedChapters ?? s.embedChapters;

  bool resolveSponsorBlockEnabled(SettingsState s) =>
      sponsorBlockEnabled ?? s.sponsorBlockEnabled;

  String resolveSponsorBlockAction(SettingsState s) =>
      sponsorBlockAction ?? s.sponsorBlockAction;

  List<String> resolveSponsorBlockCategories(SettingsState s) =>
      sponsorBlockCategories ?? s.sponsorBlockCategories;

  bool resolveForceRemux(SettingsState s) => forceRemux ?? s.forceRemux;

  bool resolveTiktokRemoveWatermark(SettingsState s) =>
      tiktokRemoveWatermark ?? s.tiktokRemoveWatermark;

  /// Dialog audio selection stores bitrate in the portable target, not in
  /// global audio codec settings. Use this when launching yt-dlp so the right
  /// column's 320/256/192 kbps choice is the actual postprocessor target.
  int? audioBitrateKbpsFor(Quality quality) {
    if (quality.mediaType != MediaType.audio) return null;
    final target = qualityTarget;
    if (target?.fileType == DownloadFileType.audio) {
      final outputFormat = target?.outputFormat?.trim().toLowerCase();
      if (outputFormat == 'wav' || outputFormat == 'flac') return null;
      return target?.targetBitrateKbps;
    }
    return null;
  }

  /// Whether a section time range is set for partial download
  bool get hasSectionRange =>
      sectionStartTime != null && sectionEndTime != null;

  /// Check if any format overrides differ from global settings
  bool hasOverrides(SettingsState s) {
    return fileType != null ||
        qualityIntent != DownloadQualityIntent.recommended ||
        qualityTarget != null ||
        videoCodecOverride != null ||
        audioCodecOverride != null ||
        containerFormatOverride != null ||
        fpsOverride != null ||
        maxResolutionOverride != null ||
        subtitlesEnabled != null ||
        subtitlesLanguages != null ||
        subtitlesFormat != null ||
        embedSubtitles != null ||
        includeAutoSubs != null ||
        writeThumbnail != null ||
        embedThumbnail != null ||
        embedMetadata != null ||
        embedChapters != null ||
        sponsorBlockEnabled != null ||
        sponsorBlockAction != null ||
        sponsorBlockCategories != null ||
        forceRemux != null ||
        tiktokRemoveWatermark != null ||
        sectionStartTime != null ||
        sectionEndTime != null;
  }

  DownloadConfig copyWith({
    List<Quality>? selectedQualities,
    DownloadFileType? fileType,
    DownloadQualityIntent? qualityIntent,
    PortableQualityTarget? Function()? qualityTarget,
    VideoCodecPreference? Function()? videoCodecOverride,
    AudioCodecPreference? Function()? audioCodecOverride,
    ContainerFormatPreference? Function()? containerFormatOverride,
    FpsPreference? Function()? fpsOverride,
    int? Function()? maxResolutionOverride,
    bool? Function()? subtitlesEnabled,
    List<String>? Function()? subtitlesLanguages,
    String? Function()? subtitlesFormat,
    bool? Function()? embedSubtitles,
    bool? Function()? includeAutoSubs,
    bool? Function()? writeThumbnail,
    bool? Function()? embedThumbnail,
    bool? Function()? embedMetadata,
    bool? Function()? embedChapters,
    bool? Function()? sponsorBlockEnabled,
    String? Function()? sponsorBlockAction,
    List<String>? Function()? sponsorBlockCategories,
    bool? Function()? forceRemux,
    bool? Function()? tiktokRemoveWatermark,
    Duration? Function()? sectionStartTime,
    Duration? Function()? sectionEndTime,
    List<(Duration, Duration)>? Function()? selectedChapterRanges,
    bool? applyToAll,
    bool? rememberForPlatform,
    bool? saveAsDefault,
    String? Function()? savePathOverride,
  }) {
    return DownloadConfig(
      selectedQualities: selectedQualities ?? this.selectedQualities,
      fileType: fileType ?? this.fileType,
      qualityIntent: qualityIntent ?? this.qualityIntent,
      qualityTarget:
          qualityTarget != null ? qualityTarget() : this.qualityTarget,
      videoCodecOverride:
          videoCodecOverride != null
              ? videoCodecOverride()
              : this.videoCodecOverride,
      audioCodecOverride:
          audioCodecOverride != null
              ? audioCodecOverride()
              : this.audioCodecOverride,
      containerFormatOverride:
          containerFormatOverride != null
              ? containerFormatOverride()
              : this.containerFormatOverride,
      fpsOverride: fpsOverride != null ? fpsOverride() : this.fpsOverride,
      maxResolutionOverride:
          maxResolutionOverride != null
              ? maxResolutionOverride()
              : this.maxResolutionOverride,
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
      embedThumbnail:
          embedThumbnail != null ? embedThumbnail() : this.embedThumbnail,
      embedMetadata:
          embedMetadata != null ? embedMetadata() : this.embedMetadata,
      embedChapters:
          embedChapters != null ? embedChapters() : this.embedChapters,
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
      sectionStartTime:
          sectionStartTime != null ? sectionStartTime() : this.sectionStartTime,
      sectionEndTime:
          sectionEndTime != null ? sectionEndTime() : this.sectionEndTime,
      selectedChapterRanges:
          selectedChapterRanges != null
              ? selectedChapterRanges()
              : this.selectedChapterRanges,
      applyToAll: applyToAll ?? this.applyToAll,
      rememberForPlatform: rememberForPlatform ?? this.rememberForPlatform,
      saveAsDefault: saveAsDefault ?? this.saveAsDefault,
      savePathOverride:
          savePathOverride != null ? savePathOverride() : this.savePathOverride,
    );
  }
}
