import '../../../../core/l10n/app_localizations.dart';

/// Container format preference for downloads.
///
/// Two tiers:
///
/// **Native (no recode)** — yt-dlp merges DASH streams directly into the
/// container without re-encoding. Fastest, lossless, codec-bound:
///   - `mp4`, `mkv`, `webm`
///
/// **Recoded (requires --recode-video)** — yt-dlp merges into a native
/// container first, then post-processes with ffmpeg to transcode into the
/// requested container. Slower (transcode time scales with file size)
/// but unlocks containers yt-dlp's merger cannot emit directly:
///   - `avi` — legacy NLE editors (Premiere, AVS, VirtualDub)
///   - `mov` — Apple ecosystem (Final Cut Pro, iMovie, QuickTime)
///   - `m4v` — Apple TV / iTunes import (MP4 wrapped with .m4v ext)
///   - `flv` — legacy Flash archives / RTMP streaming pipelines
///
/// The selector service emits `--recode-video` only for the recoded tier;
/// native tier still uses `--merge-output-format` priority list.
enum ContainerFormatPreference {
  /// MP4 - most compatible, plays everywhere
  mp4,

  /// MKV - flexible container, supports all codecs
  mkv,

  /// WebM - web-optimized, VP9/Opus
  webm,

  /// AVI - legacy editor compatibility (Premiere/VirtualDub/AVS).
  /// Requires ffmpeg recode after merge.
  avi,

  /// MOV - Apple QuickTime / Final Cut Pro / iMovie pipelines.
  /// Requires ffmpeg recode after merge.
  mov,

  /// M4V - iTunes / Apple TV import (MP4 stream with .m4v extension).
  /// Requires ffmpeg recode after merge.
  m4v,

  /// FLV - Flash Video for legacy archives / RTMP capture.
  /// Requires ffmpeg recode after merge.
  flv;

  /// Parse a container from a file extension or filename. RC3 of
  /// Ultra Plan v3 — the retry path uses this to recover the user's
  /// original container choice from `download.filename` since that
  /// column is set on the first yt-dlp invocation and persists
  /// across retries (where the global settings preference may have
  /// drifted since the download was created).
  ///
  /// Accepts: `'avi'`, `'.avi'`, `'video.avi'`, `'My.Video [Best (1080p)].avi'`.
  /// Case-insensitive. Returns null for unknown / audio-only / empty
  /// inputs, leaving the caller to fall back to global settings.
  static ContainerFormatPreference? fromExtension(String? extOrFilename) {
    if (extOrFilename == null || extOrFilename.isEmpty) return null;
    // Pull the last `.xxx` chunk; if the input is already bare like
    // `'avi'` (no dot) treat the whole string as the extension.
    final dot = extOrFilename.lastIndexOf('.');
    final raw = dot >= 0 ? extOrFilename.substring(dot + 1) : extOrFilename;
    final ext = raw.trim().toLowerCase();
    if (ext.isEmpty) return null;
    for (final value in ContainerFormatPreference.values) {
      if (value.name == ext) return value;
    }
    return null;
  }

  /// True when yt-dlp must transcode via `--recode-video` because the
  /// container is not in yt-dlp's native merge set.
  bool get requiresRecode {
    switch (this) {
      case ContainerFormatPreference.mp4:
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.webm:
        return false;
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return true;
    }
  }

  String get displayName {
    switch (this) {
      case ContainerFormatPreference.mp4:
        return AppLocalizations.settingsContainerMP4;
      case ContainerFormatPreference.mkv:
        return AppLocalizations.settingsContainerMKV;
      case ContainerFormatPreference.webm:
        return AppLocalizations.settingsContainerWebM;
      case ContainerFormatPreference.avi:
        return AppLocalizations.settingsContainerAVI;
      case ContainerFormatPreference.mov:
        return AppLocalizations.settingsContainerMOV;
      case ContainerFormatPreference.m4v:
        return AppLocalizations.settingsContainerM4V;
      case ContainerFormatPreference.flv:
        return AppLocalizations.settingsContainerFLV;
    }
  }

  String get description {
    switch (this) {
      case ContainerFormatPreference.mp4:
        return AppLocalizations.settingsContainerMP4Desc;
      case ContainerFormatPreference.mkv:
        return AppLocalizations.settingsContainerMKVDesc;
      case ContainerFormatPreference.webm:
        return AppLocalizations.settingsContainerWebMDesc;
      case ContainerFormatPreference.avi:
        return AppLocalizations.settingsContainerAVIDesc;
      case ContainerFormatPreference.mov:
        return AppLocalizations.settingsContainerMOVDesc;
      case ContainerFormatPreference.m4v:
        return AppLocalizations.settingsContainerM4VDesc;
      case ContainerFormatPreference.flv:
        return AppLocalizations.settingsContainerFLVDesc;
    }
  }

  /// Get file extension
  String get extension {
    switch (this) {
      case ContainerFormatPreference.mp4:
        return 'mp4';
      case ContainerFormatPreference.mkv:
        return 'mkv';
      case ContainerFormatPreference.webm:
        return 'webm';
      case ContainerFormatPreference.avi:
        return 'avi';
      case ContainerFormatPreference.mov:
        return 'mov';
      case ContainerFormatPreference.m4v:
        return 'm4v';
      case ContainerFormatPreference.flv:
        return 'flv';
    }
  }

  String toDbString() => name;

  static ContainerFormatPreference fromDbString(String value) {
    return ContainerFormatPreference.values.firstWhere(
      (pref) => pref.name == value,
      orElse: () => ContainerFormatPreference.mp4,
    );
  }
}
