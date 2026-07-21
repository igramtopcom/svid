import '../../../../core/l10n/app_localizations.dart';

/// FPS (frames per second) preference for downloads
/// Determines whether to prefer higher frame rates or standard
enum FpsPreference {
  /// Auto - let yt-dlp choose (usually highest)
  auto,

  /// Prefer 60fps when available
  prefer60,

  /// Prefer 30fps (smaller files, smoother on older devices)
  prefer30;

  String get displayName {
    switch (this) {
      case FpsPreference.auto:
        return AppLocalizations.settingsFpsAuto;
      case FpsPreference.prefer60:
        return AppLocalizations.settingsFpsPrefer60;
      case FpsPreference.prefer30:
        return AppLocalizations.settingsFpsPrefer30;
    }
  }

  String get description {
    switch (this) {
      case FpsPreference.auto:
        return AppLocalizations.settingsFpsAutoDesc;
      case FpsPreference.prefer60:
        return AppLocalizations.settingsFpsPrefer60Desc;
      case FpsPreference.prefer30:
        return AppLocalizations.settingsFpsPrefer30Desc;
    }
  }

  /// Get max FPS value for yt-dlp filter
  int? get maxFps {
    switch (this) {
      case FpsPreference.auto:
        return null; // No limit
      case FpsPreference.prefer60:
        return 60;
      case FpsPreference.prefer30:
        return 30;
    }
  }

  String toDbString() => name;

  static FpsPreference fromDbString(String value) {
    return FpsPreference.values.firstWhere(
      (pref) => pref.name == value,
      orElse: () => FpsPreference.auto,
    );
  }
}
