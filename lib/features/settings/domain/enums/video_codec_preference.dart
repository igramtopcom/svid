import '../../../../core/l10n/app_localizations.dart';

/// Video codec preference for downloads
/// Determines which video codec to prefer when multiple are available
enum VideoCodecPreference {
  /// Auto - let yt-dlp choose (usually best quality)
  auto,

  /// H.264/AVC - most compatible, plays everywhere
  h264,

  /// H.265/HEVC - better compression, good compatibility
  h265,

  /// VP9 - Google's codec, good quality/size ratio
  vp9,

  /// AV1 - newest, best compression but limited playback support
  av1;

  String get displayName {
    switch (this) {
      case VideoCodecPreference.auto:
        return AppLocalizations.settingsVideoCodecAuto;
      case VideoCodecPreference.h264:
        return AppLocalizations.settingsVideoCodecH264;
      case VideoCodecPreference.h265:
        return AppLocalizations.settingsVideoCodecH265;
      case VideoCodecPreference.vp9:
        return AppLocalizations.settingsVideoCodecVP9;
      case VideoCodecPreference.av1:
        return AppLocalizations.settingsVideoCodecAV1;
    }
  }

  String get description {
    switch (this) {
      case VideoCodecPreference.auto:
        return AppLocalizations.settingsVideoCodecAutoDesc;
      case VideoCodecPreference.h264:
        return AppLocalizations.settingsVideoCodecH264Desc;
      case VideoCodecPreference.h265:
        return AppLocalizations.settingsVideoCodecH265Desc;
      case VideoCodecPreference.vp9:
        return AppLocalizations.settingsVideoCodecVP9Desc;
      case VideoCodecPreference.av1:
        return AppLocalizations.settingsVideoCodecAV1Desc;
    }
  }

  /// Get yt-dlp vcodec filter value
  String? get ytdlpFilter {
    switch (this) {
      case VideoCodecPreference.auto:
        return null; // No filter
      case VideoCodecPreference.h264:
        return 'avc';
      case VideoCodecPreference.h265:
        return 'hevc';
      case VideoCodecPreference.vp9:
        return 'vp9';
      case VideoCodecPreference.av1:
        return 'av01';
    }
  }

  String toDbString() => name;

  static VideoCodecPreference fromDbString(String value) {
    return VideoCodecPreference.values.firstWhere(
      (pref) => pref.name == value,
      orElse: () => VideoCodecPreference.auto,
    );
  }
}
