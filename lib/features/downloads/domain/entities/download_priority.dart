import '../../../../core/l10n/app_localizations.dart';

/// Domain enum for user-facing download priority.
///
/// Values map directly to the `priority` DB column (default = 0 = normal).
enum DownloadPriority {
  low(-1),
  normal(0),
  high(1);

  const DownloadPriority(this.value);

  final int value;

  /// Converts a DB integer to a [DownloadPriority].
  /// Any unknown value (including future values) defaults to [normal].
  static DownloadPriority fromInt(int v) => switch (v) {
        1 => high,
        -1 => low,
        _ => normal,
      };

  /// Get display label for UI (localized via AppLocalizations).
  String get displayLabel => switch (this) {
        DownloadPriority.high => AppLocalizations.priorityHigh,
        DownloadPriority.normal => AppLocalizations.priorityNormal,
        DownloadPriority.low => AppLocalizations.priorityLow,
      };
}
