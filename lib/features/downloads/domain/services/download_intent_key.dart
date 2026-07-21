import '../../../../core/utils/url_normalizer.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../entities/download_config.dart';
import '../entities/download_entity.dart';
import '../entities/download_status.dart';
import '../entities/video_info.dart';

/// RC10 Blocker 3 of Ultra Plan v3 — pure value type representing
/// the user's "what to download" intent. Used by duplicate detection
/// across Home + Floating Capture + Archive Warning so all three
/// surfaces agree on what counts as "the same download already
/// exists".
///
/// Pre-RC10 duplicate detection matched URL + qualityLabel only:
///   - `home_download_mixin.dart:1593` (Home)
///   - `capture_download_coordinator_provider.dart:478` (Floating)
/// Result: user trying MP4 1080p got falsely warned about an
/// existing WebM 1080p of the same video (both have qualityLabel
/// "1080p", but the output files are different).
///
/// RC10 fix: full output intent is the comparison key.
///
/// Design constraints (Codex direction 2026-05-23):
///   - Pure value type. No I/O, no provider reads, no DB calls.
///   - Constructible from `(VideoInfo + Quality + DownloadConfig)`
///     (pre-start path) AND from `DownloadEntity` (existing row).
///   - `matches(other)` is the duplicate-detection predicate.
///   - Implements value `==` so it doubles as a Set/Map key.
class DownloadIntentKey {
  /// Normalized URL (tracking params stripped, fragment stripped,
  /// host lowercased, default ports stripped). Use `UrlNormalizer`.
  final String normalizedUrl;

  /// Whether this is a video, audio, image, or subtitle pull.
  /// `DownloadFileType.video` vs `.audio` are distinct intents even
  /// for the same source URL — video MP4 1080p and audio MP3 320k
  /// from the same YouTube video are NOT duplicates.
  final DownloadFileType fileType;

  /// User-visible quality label ("1080p", "720p60", "Audio Only",
  /// "Best (4K)"). Comparison is case-insensitive + trimmed. Empty
  /// matches empty.
  final String qualityLabel;

  /// Container extension the user picked (mp4/mkv/webm/avi/mov/m4v/
  /// flv). Distinguishes MP4 1080p from WebM 1080p of same video.
  /// Empty when not applicable (e.g., audio-only pull).
  final String container;

  /// Audio format for audio-only pulls (mp3/aac/m4a/opus/flac/wav).
  /// Empty for video pulls.
  final String audioFormat;

  /// Target bitrate in kbps (0 = best / auto). Two audio MP3 pulls
  /// at 192 vs 320 kbps are distinct intents.
  final int audioBitrateKbps;

  /// Section / chapter marker. Two downloads of the same video that
  /// extract different chapters are distinct intents. Empty for
  /// whole-video pulls.
  final String section;

  const DownloadIntentKey({
    required this.normalizedUrl,
    required this.fileType,
    required this.qualityLabel,
    required this.container,
    required this.audioFormat,
    required this.audioBitrateKbps,
    required this.section,
  });

  /// Construct from a fresh download start request.
  ///
  /// `videoInfo.url` is normalized via `UrlNormalizer`. Quality
  /// label + container + audioFormat + bitrate are pulled from the
  /// matching fields of `Quality` and `DownloadConfig`. `section`
  /// is read from the config's chapter selection (empty if none).
  factory DownloadIntentKey.fromRequest({
    required VideoInfo videoInfo,
    required Quality quality,
    required DownloadConfig? config,
    // RC10 Codex-catch B — when `config` is null (quick-start
    // download without opening the dialog), the user's GLOBAL
    // settings still imply a container + audio format + bitrate.
    // Pre-fix returned empty strings → an MP4 download from
    // quick-start would NOT match an existing MP4 row (both keys
    // had `container=''`), producing a false-negative duplicate.
    // Callers MUST pass the user's effective settings here.
    ContainerFormatPreference? fallbackContainer,
    AudioCodecPreference? fallbackAudioCodec,
    int? fallbackAudioBitrateKbps,
  }) {
    final isAudio = quality.mediaType == MediaType.audio ||
        (config?.fileType == DownloadFileType.audio);
    // Container: prefer config override, then global fallback, then
    // a hard default (mp4 for video, empty for audio). Audio rows
    // intentionally have empty container — they're indexed by
    // `audioFormat` instead.
    final container = isAudio
        ? ''
        : ((config?.containerFormatOverride ??
                    fallbackContainer ??
                    ContainerFormatPreference.mp4)
                .toDbString())
            .toLowerCase();
    // Audio format: prefer config target, then settings codec, then
    // 'mp3' (yt-dlp's audio-extract default). Match `_resolveRetryAudioFormat`
    // in downloads_notifier (RC5 pattern).
    final audioFormat = isAudio
        ? (() {
            final cfgFmt = config?.qualityTarget?.outputFormat;
            if (cfgFmt != null && cfgFmt.isNotEmpty) {
              return cfgFmt.toLowerCase();
            }
            // Map AudioCodecPreference → yt-dlp audio-format token.
            switch (fallbackAudioCodec) {
              case AudioCodecPreference.aac:
                return 'aac';
              case AudioCodecPreference.opus:
                return 'opus';
              case AudioCodecPreference.mp3:
                return 'mp3';
              case AudioCodecPreference.auto:
              case null:
                return 'mp3';
            }
          })()
        : '';
    // Bitrate: prefer config target, then settings fallback, then 0
    // (= "best / auto" — treated as a distinct intent from explicit
    // 320kbps, but matches the legacy auto-bitrate row).
    final bitrate = isAudio
        ? (config?.audioBitrateKbpsFor(quality) ??
            fallbackAudioBitrateKbps ??
            0)
        : 0;
    // Section marker — empty when no per-chapter / no per-section
    // scope. Two encodings to consider:
    //   1. `sectionStartTime..sectionEndTime` — single range cut.
    //   2. `selectedChapterRanges` — per-chapter multi-range cut.
    // Both encodings serialize to a stable comparison string.
    final section = _sectionKey(config);
    return DownloadIntentKey(
      normalizedUrl: UrlNormalizer.normalize(videoInfo.url),
      fileType: isAudio ? DownloadFileType.audio : DownloadFileType.video,
      qualityLabel: quality.qualityText.trim().toLowerCase(),
      container: container,
      audioFormat: audioFormat,
      audioBitrateKbps: bitrate,
      section: section,
    );
  }

  /// Construct from an existing persisted download row. Used to
  /// answer "does this row count as a duplicate of the proposed
  /// new download intent?"
  ///
  /// Caveat: some fields are best-effort from a row's persisted
  /// data. `audioBitrateKbps` is derived from filename regex (RC5
  /// pattern); `audioFormat` is derived from filename extension.
  /// `section` is currently always empty since chapter scope is
  /// not persisted on the row (TODO follow-up).
  factory DownloadIntentKey.fromEntity(DownloadEntity entity) {
    final filename = entity.filename;
    final ext = _extOf(filename);
    final isAudio = _audioExts.contains(ext);
    return DownloadIntentKey(
      normalizedUrl: UrlNormalizer.normalize(
        entity.sourceUrl.isNotEmpty ? entity.sourceUrl : entity.url,
      ),
      fileType: isAudio ? DownloadFileType.audio : DownloadFileType.video,
      qualityLabel: (entity.qualityLabel ?? '').trim().toLowerCase(),
      container: isAudio ? '' : ext,
      audioFormat: isAudio ? ext : '',
      audioBitrateKbps: isAudio ? _parseBitrateFromFilename(filename) : 0,
      section: '',
    );
  }

  /// Duplicate-detection predicate. Two intents match when they
  /// agree on every comparison-meaningful field. Empty qualityLabel
  /// on either side falls back to "not a duplicate" (legacy
  /// behavior — pre-RC10 also bailed on empty labels).
  bool matches(DownloadIntentKey other) {
    if (normalizedUrl.isEmpty || other.normalizedUrl.isEmpty) return false;
    if (normalizedUrl != other.normalizedUrl) return false;
    if (fileType != other.fileType) return false;
    if (qualityLabel.isEmpty || other.qualityLabel.isEmpty) return false;
    if (qualityLabel != other.qualityLabel) return false;
    if (container != other.container) return false;
    if (audioFormat != other.audioFormat) return false;
    if (audioBitrateKbps != other.audioBitrateKbps) return false;
    if (section != other.section) return false;
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadIntentKey &&
        other.normalizedUrl == normalizedUrl &&
        other.fileType == fileType &&
        other.qualityLabel == qualityLabel &&
        other.container == container &&
        other.audioFormat == audioFormat &&
        other.audioBitrateKbps == audioBitrateKbps &&
        other.section == section;
  }

  @override
  int get hashCode => Object.hash(
        normalizedUrl,
        fileType,
        qualityLabel,
        container,
        audioFormat,
        audioBitrateKbps,
        section,
      );

  @override
  String toString() =>
      'DownloadIntentKey($normalizedUrl, $fileType, $qualityLabel, '
      'container=$container, audio=$audioFormat@$audioBitrateKbps, '
      'section=$section)';

  /// RC10 Codex-round-3 — derive a yt-dlp archive-file suffix that
  /// segments `--download-archive` per FULL output intent. yt-dlp's
  /// archive records `<extractor> <video_id>` and is intent-BLIND,
  /// so without full segmentation a user who already downloaded a
  /// video as MP4 1080p has subsequent MP4 720p / WebM 1080p / MP3
  /// pulls silently skipped (same video_id, intent ignored).
  ///
  /// Round-2's suffix was `_video_<container>` + `_audio` — still
  /// collapsed quality + bitrate variants. Round-3 expanded to
  /// `_video_<quality>_<container>` / `_audio_<format>[_<bitrate>k]`.
  /// Round-5 (Codex) adds the section/chapter dimension so a
  /// whole-video pull and a clip-of-the-same-video pull don't share
  /// an archive entry. The new section token is derived from the
  /// same `_sectionKey` the duplicate-detection path uses, so
  /// duplicate logic and archive logic stay aligned.
  ///
  /// Schema:
  ///   - video: `_video_<quality>_<container>[_<sectionToken>]`
  ///   - audio: `_audio_<format>[_<bitrate>k][_<sectionToken>]`
  ///   - image: `_image`
  ///   - subtitle: `` (no archive — subs always re-extract)
  ///
  /// Empty `section` keeps the legacy whole-video suffix shape so
  /// existing archives don't get invalidated by the round-5 change.
  static String archiveFileSuffix({
    required MediaType mediaType,
    required ContainerFormatPreference container,
    required String qualityLabel,
    String audioFormat = '',
    int audioBitrateKbps = 0,
    String section = '',
  }) {
    String sanitize(String raw) {
      if (raw.trim().isEmpty) return 'auto';
      final lower = raw.toLowerCase().trim();
      final safe = lower
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      return safe.isEmpty ? 'auto' : safe;
    }

    final sectionToken =
        section.trim().isEmpty ? '' : '_${sanitize(section)}';

    switch (mediaType) {
      case MediaType.video:
        final qToken = sanitize(qualityLabel);
        return '_video_${qToken}_${container.extension.toLowerCase()}$sectionToken';
      case MediaType.audio:
        final fmt = audioFormat.trim().isEmpty
            ? 'auto'
            : audioFormat.toLowerCase().trim();
        final br = audioBitrateKbps > 0 ? '_${audioBitrateKbps}k' : '';
        return '_audio_$fmt$br$sectionToken';
      case MediaType.image:
        return '_image';
      case MediaType.subtitle:
        return '';
    }
  }

  /// RC10 Codex-round-5 — instance-level archive suffix derived from
  /// THIS key's fields. Single source of truth: duplicate detection
  /// and archive scoping both go through the same DownloadIntentKey
  /// construction, so they cannot drift. Callers that already have
  /// (or are about to construct) an intent key for duplicate
  /// detection should use this method instead of the static
  /// archiveFileSuffix to ensure the section dimension is included.
  ///
  /// The container field is reconstituted via best-effort lookup on
  /// the stored `container` string (the value `toDbString()` produces
  /// in DownloadIntentKey.fromRequest). Audio-only intents pass
  /// `ContainerFormatPreference.mp4` as a placeholder since audio
  /// pulls don't consult the video container in archiveFileSuffix.
  String archiveSuffix() {
    final containerPref = ContainerFormatPreference.fromExtension(container) ??
        ContainerFormatPreference.mp4;
    final isAudio = fileType == DownloadFileType.audio;
    return archiveFileSuffix(
      mediaType: isAudio ? MediaType.audio : MediaType.video,
      container: containerPref,
      qualityLabel: qualityLabel,
      audioFormat: audioFormat,
      audioBitrateKbps: audioBitrateKbps,
      section: section,
    );
  }

  static const Set<String> _audioExts = {
    'mp3',
    'm4a',
    'opus',
    'aac',
    'flac',
    'wav',
    'ogg',
    'alac',
  };

  static String _extOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return '';
    return filename.substring(dot + 1).toLowerCase().trim();
  }

  /// Serialize the section / chapter scope to a stable comparison
  /// string. Empty when no scope applied.
  static String _sectionKey(DownloadConfig? config) {
    if (config == null) return '';
    if (config.sectionStartTime != null || config.sectionEndTime != null) {
      final start = config.sectionStartTime?.inMilliseconds ?? 0;
      final end = config.sectionEndTime?.inMilliseconds ?? 0;
      return 'section:$start-$end';
    }
    final ranges = config.selectedChapterRanges;
    if (ranges != null && ranges.isNotEmpty) {
      final encoded = ranges
          .map((r) =>
              '${r.$1.inMilliseconds}-${r.$2.inMilliseconds}')
          .join(',');
      return 'chapters:$encoded';
    }
    return '';
  }

  static int _parseBitrateFromFilename(String filename) {
    // Matches "song [128kbps].mp3" or "song 192k.opus" etc.
    final match =
        RegExp(r'(\d{2,4})\s*k(?:bps|b/s)?', caseSensitive: false)
            .firstMatch(filename);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }
}

/// Returns true when [existing] should warn the user as a duplicate
/// of the [proposed] intent. Encapsulates the "active row only"
/// rule (cancelled/failed rows are not duplicates because the user
/// presumably wants to try again) so duplicate-detection callsites
/// stay one-liners.
///
/// The `proposed` intent is computed via
/// `DownloadIntentKey.fromRequest(...)`; the `existing` row's intent
/// is derived via `DownloadIntentKey.fromEntity(existing)`. Both
/// pure — no I/O.
bool isDuplicateOfActive(
  DownloadIntentKey proposed,
  DownloadEntity existing,
) {
  // Cancelled / failed rows are NOT duplicates — user retrying or
  // re-attempting is normal flow.
  if (existing.status == DownloadStatus.cancelled) return false;
  if (existing.status == DownloadStatus.failed) return false;
  final existingKey = DownloadIntentKey.fromEntity(existing);
  return proposed.matches(existingKey);
}

/// RC10 Codex-catch A — find a duplicate among MULTIPLE candidates
/// sharing the same normalized URL.
///
/// Pre-fix the duplicate detection sites queried `getDownloadByUrl`
/// which returns ONE row (typically the most recent). If the DB
/// holds both a completed MP4 1080p AND a completed WebM 1080p of
/// the same video, the single-row query might pick WebM, the user
/// is requesting MP4, `isDuplicateOfActive` returns false → user
/// silently creates a third row even though the MP4 1080p duplicate
/// already exists.
///
/// This helper scans the FULL list (from in-memory notifier state
/// or repo query) and returns the first row whose intent matches
/// the proposed. Returns null when no match.
///
/// Callers pass `candidates` as the already-loaded downloads list
/// (no I/O inside this helper — pure predicate over a snapshot).
DownloadEntity? findDuplicateAmong(
  DownloadIntentKey proposed,
  Iterable<DownloadEntity> candidates,
) {
  for (final candidate in candidates) {
    if (isDuplicateOfActive(proposed, candidate)) return candidate;
  }
  return null;
}
