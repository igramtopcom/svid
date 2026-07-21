import '../../../../core/l10n/app_localizations.dart';

/// Audio codec preference for downloads
/// Determines which audio codec to prefer when multiple are available
enum AudioCodecPreference {
  /// Auto - let yt-dlp choose (usually best quality)
  auto,

  /// AAC - most compatible, good quality
  aac,

  /// Opus - best quality/size ratio, good compatibility
  opus,

  /// MP3 - universal compatibility
  mp3;

  String get displayName {
    switch (this) {
      case AudioCodecPreference.auto:
        return AppLocalizations.settingsAudioCodecAuto;
      case AudioCodecPreference.aac:
        return AppLocalizations.settingsAudioCodecAAC;
      case AudioCodecPreference.opus:
        return AppLocalizations.settingsAudioCodecOpus;
      case AudioCodecPreference.mp3:
        return AppLocalizations.settingsAudioCodecMP3;
    }
  }

  String get description {
    switch (this) {
      case AudioCodecPreference.auto:
        return AppLocalizations.settingsAudioCodecAutoDesc;
      case AudioCodecPreference.aac:
        return AppLocalizations.settingsAudioCodecAACDesc;
      case AudioCodecPreference.opus:
        return AppLocalizations.settingsAudioCodecOpusDesc;
      case AudioCodecPreference.mp3:
        return AppLocalizations.settingsAudioCodecMP3Desc;
    }
  }

  /// Get yt-dlp acodec filter value
  String? get ytdlpFilter {
    switch (this) {
      case AudioCodecPreference.auto:
        return null; // No filter
      case AudioCodecPreference.aac:
        return 'aac';
      case AudioCodecPreference.opus:
        return 'opus';
      case AudioCodecPreference.mp3:
        return 'mp3';
    }
  }

  String toDbString() => name;

  static AudioCodecPreference fromDbString(String value) {
    return AudioCodecPreference.values.firstWhere(
      (pref) => pref.name == value,
      orElse: () => AudioCodecPreference.auto,
    );
  }
}
