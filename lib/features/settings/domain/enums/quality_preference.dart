import '../../../../core/l10n/app_localizations.dart';

/// Quality preference for auto-selection
enum QualityPreference {
  auto, // Let app choose best available
  best, // Highest quality
  p1080, // 1080p
  p720, // 720p
  p480, // 480p
  audioOnly; // Audio only

  String get displayName {
    switch (this) {
      case QualityPreference.auto:
        return AppLocalizations.settingsQualityAuto;
      case QualityPreference.best:
        return AppLocalizations.settingsQualityBest;
      case QualityPreference.p1080:
        return '1080p';
      case QualityPreference.p720:
        return '720p';
      case QualityPreference.p480:
        return '480p';
      case QualityPreference.audioOnly:
        return AppLocalizations.settingsQualityAudioOnly;
    }
  }

  String toDbString() => name;

  static QualityPreference fromDbString(String value) {
    return QualityPreference.values.firstWhere(
      (pref) => pref.name == value,
      orElse: () => QualityPreference.auto,
    );
  }
}
