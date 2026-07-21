import '../../../../core/l10n/app_localizations.dart';

/// Status of a conversion job throughout its lifecycle.
enum ConversionStatus {
  /// Queued and waiting to start
  queued,

  /// Probing input file with ffprobe
  probing,

  /// Actively converting with ffmpeg
  converting,

  /// Paused by user (Unix SIGSTOP)
  paused,

  /// Successfully completed
  completed,

  /// Failed with error
  failed,

  /// Cancelled by user
  cancelled;

  /// Whether the job is in a terminal state (no further transitions)
  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;

  /// Whether the job is actively running
  bool get isActive => this == probing || this == converting;

  /// Display name for UI — resolves via AppLocalizations so the label
  /// follows the user's selected locale (Pattern E migration: stable
  /// enum.name as key, localized prose at render time).
  String get displayName => AppLocalizations.conversionStatusLabel(name);

  /// Parse from stored string value
  static ConversionStatus fromString(String value) {
    return ConversionStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ConversionStatus.queued,
    );
  }
}
