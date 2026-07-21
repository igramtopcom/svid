import '../../../../core/l10n/app_localizations.dart';
import '../../../settings/domain/entities/platform_quality_preference.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../domain/entities/download_config.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/format_selector_service.dart';

class PlatformPreferenceResolution {
  final Quality? quality;
  final bool canAutoApply;
  final FormatSelectionWarning? warning;

  const PlatformPreferenceResolution._({
    required this.quality,
    required this.canAutoApply,
    this.warning,
  });

  const PlatformPreferenceResolution.match(Quality quality)
    : this._(quality: quality, canAutoApply: true);

  const PlatformPreferenceResolution.fallback(
    Quality quality,
    FormatSelectionWarning warning,
  ) : this._(quality: quality, canAutoApply: true, warning: warning);

  const PlatformPreferenceResolution.none()
    : this._(quality: null, canAutoApply: false);
}

PlatformPreferenceResolution resolveQualityForPlatformPreference(
  PlatformQualityPreference preference,
  List<Quality> qualities,
) {
  if (qualities.isEmpty) return const PlatformPreferenceResolution.none();

  final fileType =
      preference.fileType ??
      preference.qualityTarget?.fileType ??
      DownloadFileType.fromMediaType(preference.mediaType);

  final scoped =
      qualities.where((q) => q.mediaType == fileType.toMediaType()).toList();
  if (scoped.isEmpty) return const PlatformPreferenceResolution.none();

  // Raw stream identifiers are URL-specific and must never be replayed as a
  // portable platform preference.
  if (preference.qualityIntent == DownloadQualityIntent.technicalStream) {
    return const PlatformPreferenceResolution.none();
  }

  final resolvedByIntent = _qualityForIntent(
    scoped,
    fileType,
    preference.qualityIntent,
    preference.qualityTarget,
  );
  if (resolvedByIntent != null) {
    return PlatformPreferenceResolution.match(resolvedByIntent);
  }

  if (preference.qualityIntent == DownloadQualityIntent.specific) {
    final fallback = _fallbackQualityForTarget(
      scoped,
      preference.qualityTarget,
    );
    if (fallback != null) return fallback;
    return const PlatformPreferenceResolution.none();
  }

  if (preference.qualityIntent != null) {
    return const PlatformPreferenceResolution.none();
  }

  final legacyMatch = _firstWhereOrNull(
    scoped,
    (q) =>
        q.qualityText == preference.qualityText &&
        q.mediaType == preference.mediaType,
  );
  return legacyMatch != null
      ? PlatformPreferenceResolution.match(legacyMatch)
      : const PlatformPreferenceResolution.none();
}

bool canApplySavedChoice(VideoInfo videoInfo) {
  if (videoInfo.isCarousel) return false;

  final hasImages = videoInfo.availableQualities.any(
    (q) => q.mediaType == MediaType.image,
  );
  final hasVideos = videoInfo.availableQualities.any(
    (q) => q.mediaType == MediaType.video,
  );
  if (hasImages && hasVideos) return false;

  return true;
}

DownloadConfig? downloadConfigFromPlatformPreference(
  PlatformQualityPreference preference,
  Quality quality,
) {
  if (!preference.hasFormatOverrides && !preference.hasPrimaryIntent) {
    return null;
  }
  return DownloadConfig(
    selectedQualities: [quality],
    fileType:
        preference.fileType ??
        DownloadFileType.fromMediaType(preference.mediaType),
    qualityIntent:
        preference.qualityIntent ?? DownloadQualityIntent.recommended,
    qualityTarget: preference.qualityTarget,
    videoCodecOverride:
        preference.videoCodec != null
            ? VideoCodecPreference.fromDbString(preference.videoCodec!)
            : null,
    audioCodecOverride:
        preference.audioCodec != null
            ? AudioCodecPreference.fromDbString(preference.audioCodec!)
            : null,
    containerFormatOverride:
        preference.containerFormat != null
            ? ContainerFormatPreference.fromDbString(
              preference.containerFormat!,
            )
            : null,
    fpsOverride:
        preference.fpsPreference != null
            ? FpsPreference.fromDbString(preference.fpsPreference!)
            : null,
    maxResolutionOverride: preference.maxResolution,
    subtitlesEnabled: preference.subtitlesEnabled,
    subtitlesLanguages: preference.subtitlesLanguages,
    subtitlesFormat: preference.subtitlesFormat,
    embedSubtitles: preference.embedSubtitles,
    includeAutoSubs: preference.includeAutoSubs,
    writeThumbnail: preference.writeThumbnail,
    sponsorBlockEnabled: preference.sponsorBlockEnabled,
    sponsorBlockAction: preference.sponsorBlockAction,
    sponsorBlockCategories: preference.sponsorBlockCategories,
    forceRemux: preference.forceRemux,
    tiktokRemoveWatermark: preference.tiktokRemoveWatermark,
    embedThumbnail: preference.embedThumbnail,
    embedMetadata: preference.embedMetadata,
    embedChapters: preference.embedChapters,
  );
}

Quality? _qualityForIntent(
  List<Quality> qualities,
  DownloadFileType fileType,
  DownloadQualityIntent? intent,
  PortableQualityTarget? target,
) {
  if (intent == null || intent == DownloadQualityIntent.technicalStream) {
    return null;
  }

  switch (intent) {
    case DownloadQualityIntent.recommended:
      return _recommendedQuality(qualities, fileType);
    case DownloadQualityIntent.bestAvailable:
      return fileType == DownloadFileType.video
          ? _bestAvailableVideoQuality(qualities)
          : _recommendedQuality(qualities, fileType);
    case DownloadQualityIntent.specific:
      return _qualityForTarget(qualities, target);
    case DownloadQualityIntent.technicalStream:
      return null;
  }
}

Quality _recommendedQuality(
  List<Quality> qualities,
  DownloadFileType fileType,
) {
  switch (fileType) {
    case DownloadFileType.video:
      return _recommendedVideoQuality(qualities) ??
          _bestAvailableVideoQuality(qualities) ??
          qualities.first;
    case DownloadFileType.audio:
      return _firstWhereOrNull(
            qualities,
            (q) => q.encryptedUrl == 'ytdlp:audio:mp3',
          ) ??
          qualities.first;
    case DownloadFileType.image:
      return _firstWhereOrNull(
            qualities,
            (q) => q.encryptedUrl.startsWith('gallerydl:all:'),
          ) ??
          qualities.first;
    case DownloadFileType.subtitle:
      return qualities.first;
  }
}

Quality? _recommendedVideoQuality(List<Quality> qualities) {
  final candidates =
      qualities.where((q) => q.encryptedUrl != 'ytdlp:best:mp4').toList();
  if (candidates.isEmpty) return null;

  final withHeights =
      candidates
          .map((q) => (quality: q, height: _qualityHeight(q)))
          .where((entry) => entry.height != null)
          .toList()
        ..sort((a, b) => b.height!.compareTo(a.height!));
  if (withHeights.isEmpty) return candidates.first;

  for (final entry in withHeights) {
    if (entry.height! <= 1080) return entry.quality;
  }
  return withHeights.last.quality;
}

Quality? _bestAvailableVideoQuality(List<Quality> qualities) {
  final best = _firstWhereOrNull(
    qualities,
    (q) => q.encryptedUrl == 'ytdlp:best:mp4',
  );
  if (best != null) return best;

  final withHeights =
      qualities
          .map((q) => (quality: q, height: _qualityHeight(q)))
          .where((entry) => entry.height != null)
          .toList()
        ..sort((a, b) => b.height!.compareTo(a.height!));
  return withHeights.isNotEmpty ? withHeights.first.quality : qualities.first;
}

Quality? _qualityForTarget(
  List<Quality> qualities,
  PortableQualityTarget? target,
) {
  if (target == null) return null;

  switch (target.fileType) {
    case DownloadFileType.video:
      final targetHeight = target.targetHeight;
      if (targetHeight == null) return null;
      return _firstWhereOrNull(
        qualities,
        (q) => _qualityHeight(q) == targetHeight,
      );
    case DownloadFileType.audio:
      return _audioOutputQualityFor(qualities, target);
    case DownloadFileType.subtitle:
      final languageCode = target.languageCode;
      if (languageCode == null) return null;
      return _firstWhereOrNull(
        qualities,
        (q) => q.qualityText.contains('($languageCode)'),
      );
    case DownloadFileType.image:
      return _firstWhereOrNull(
        qualities,
        (q) =>
            target.imageSelectionMode == ImageSelectionMode.all &&
            q.encryptedUrl.startsWith('gallerydl:all:'),
      );
  }
}

PlatformPreferenceResolution? _fallbackQualityForTarget(
  List<Quality> qualities,
  PortableQualityTarget? target,
) {
  if (target == null) return null;

  switch (target.fileType) {
    case DownloadFileType.video:
      final targetHeight = target.targetHeight;
      if (targetHeight == null) return null;
      final candidates =
          qualities
              .map(
                (quality) => (
                  quality: quality,
                  height: _qualityHeight(quality),
                ),
              )
              .where(
                (entry) =>
                    entry.height != null && entry.height! <= targetHeight,
              )
              .toList()
            ..sort((a, b) => b.height!.compareTo(a.height!));
      if (candidates.isEmpty) return null;
      final fallback = candidates.first.quality;
      return PlatformPreferenceResolution.fallback(
        fallback,
        FormatSelectionWarning(
          code: FormatSelectionWarningCode.exactUnavailable,
          requestedLabel: '${targetHeight}p',
          resolvedLabel: _qualityLabel(fallback),
          messageKey: 'configDialog.qualityFallbackWarning',
        ),
      );
    case DownloadFileType.audio:
      final quality = _audioOutputQualityFor(qualities, target);
      if (quality == null) return null;
      return PlatformPreferenceResolution.match(quality);
    case DownloadFileType.image:
    case DownloadFileType.subtitle:
      return null;
  }
}

int? _qualityHeight(Quality quality) {
  final text = '${quality.qualityText} ${quality.encryptedUrl}'.toLowerCase();
  final heightMatch = RegExp(r'\b(\d{3,4})p\b').firstMatch(text);
  if (heightMatch != null) return int.tryParse(heightMatch.group(1)!);
  if (RegExp(r'\b8k\b').hasMatch(text)) return 4320;
  if (RegExp(r'\b4k\b').hasMatch(text)) return 2160;
  if (RegExp(r'\b2k\b').hasMatch(text)) return 1440;
  return null;
}

String _qualityLabel(Quality quality) {
  final height = _qualityHeight(quality);
  return height != null ? '${height}p' : quality.qualityText;
}

Quality? _audioOutputQualityFor(
  List<Quality> qualities,
  PortableQualityTarget target,
) {
  final outputFormat = _normalizeAudioOutputFormat(target.outputFormat);
  final bitrate = target.targetBitrateKbps;
  if (outputFormat == null) return null;
  final formatExists = qualities.any(
    (q) => _audioFormatForQuality(q) == outputFormat,
  );
  if (!formatExists) return null;
  if (_isLosslessAudioFormat(outputFormat)) {
    return Quality(
      qualityText: AppLocalizations.configDialogAudioQualityLossless(
        _audioOutputFormatLabel(outputFormat),
      ),
      size: AppLocalizations.configDialogAudioSizeLossless,
      encryptedUrl: 'ytdlp:audio:$outputFormat',
      mediaType: MediaType.audio,
      isAudioOnly: true,
    );
  }
  if (bitrate == null) return null;
  return Quality(
    qualityText: AppLocalizations.configDialogAudioQualityBitrate(
      _audioOutputFormatLabel(outputFormat),
      bitrate,
    ),
    size: '',
    encryptedUrl: 'ytdlp:audio:$outputFormat',
    mediaType: MediaType.audio,
    isAudioOnly: true,
    tbr: bitrate.toDouble(),
  );
}

String? _normalizeAudioOutputFormat(String? format) {
  final normalized = format?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized == 'aac') return 'm4a';
  return normalized;
}

bool _isLosslessAudioFormat(String? format) {
  switch (_normalizeAudioOutputFormat(format)) {
    case 'wav':
    case 'flac':
      return true;
    default:
      return false;
  }
}

String _audioOutputFormatLabel(String format) {
  switch (_normalizeAudioOutputFormat(format)) {
    case 'm4a':
      return 'AAC';
    case 'mp3':
      return 'MP3';
    case 'opus':
      return 'Opus';
    case 'wav':
      return 'WAV';
    case 'flac':
      return 'FLAC';
    default:
      return format.toUpperCase();
  }
}

String _audioFormatForQuality(Quality quality) {
  final parts = quality.encryptedUrl.toLowerCase().split(':');
  if (parts.length >= 3 && parts[0] == 'ytdlp' && parts[1] == 'audio') {
    return _normalizeAudioOutputFormat(parts[2]) ?? 'mp3';
  }
  final haystack =
      '${quality.qualityText} ${quality.encryptedUrl}'.toLowerCase();
  for (final format in const ['mp3', 'm4a', 'opus', 'wav', 'aac']) {
    if (haystack.contains(format)) {
      return _normalizeAudioOutputFormat(format) ?? 'mp3';
    }
  }
  return 'mp3';
}

Quality? _firstWhereOrNull(
  Iterable<Quality> qualities,
  bool Function(Quality quality) test,
) {
  for (final quality in qualities) {
    if (test(quality)) return quality;
  }
  return null;
}
