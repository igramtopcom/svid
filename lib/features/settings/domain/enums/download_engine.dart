import '../../../../core/l10n/app_localizations.dart';

/// Download engine preference
enum DownloadEngine {
  /// Try yt-dlp first (recommended)
  auto,

  /// Only use yt-dlp, no fallback
  ytdlpOnly,

  /// V2 reconcile: API-only mode — never invoke yt-dlp. Used by
  /// `ExtractVideoInfoUseCase._extractWithApiRetry` when the user
  /// explicitly opts in to backend-driven extraction (lower CPU on
  /// low-end Windows / VidCombo PHP backend codepath).
  apiOnly;

  String get displayName {
    switch (this) {
      case DownloadEngine.auto:
        return AppLocalizations.settingsEngineAuto;
      case DownloadEngine.ytdlpOnly:
        return AppLocalizations.settingsEngineYtdlpOnly;
      case DownloadEngine.apiOnly:
        return AppLocalizations.settingsEngineYtdlpOnly; // TODO(ui-wording): add apiOnly label
    }
  }

  String get description {
    switch (this) {
      case DownloadEngine.auto:
        return AppLocalizations.settingsEngineAutoDesc;
      case DownloadEngine.ytdlpOnly:
        return AppLocalizations.settingsEngineYtdlpOnlyDesc;
      case DownloadEngine.apiOnly:
        return AppLocalizations.settingsEngineYtdlpOnlyDesc; // TODO(ui-wording)
    }
  }

  /// Parse from string
  static DownloadEngine fromString(String value) {
    return DownloadEngine.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DownloadEngine.auto,
    );
  }
}
