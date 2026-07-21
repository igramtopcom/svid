import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';

/// Structured error codes for download failures.
/// Stored in DB as `errorCode:rawMessage` in the existing errorMessage field.
enum DownloadErrorCode {
  // Network errors
  networkOffline,
  networkTimeout,
  serverError,
  connectionRefused,
  sslError,

  // yt-dlp errors
  videoNotFound,
  geoRestricted,
  loginRequired,
  ageRestricted,
  formatUnavailable,
  rateLimited,
  accessDenied,
  contentUnavailable,
  ytdlpBinaryMissing,
  binaryNotAvailable,
  ffmpegError,

  /// Deno (or other supported JS runtime) is unavailable — yt-dlp
  /// cannot solve YouTube nsig / n-challenge JavaScript. Distinct
  /// from `loginRequired` so UI does NOT trigger the auto-login flow
  /// (logging in further does not provide a JS runtime).
  ///
  /// `YtDlpDataSource._maybeTriggerDenoRepair` fires
  /// `BinaryManager.triggerRepair(BinaryType.deno)` (idempotent) when
  /// this error is detected, so a fan-out of N concurrent failed
  /// extractions collapses to a single re-download.
  jsRuntimeUnavailable,

  /// yt-dlp could not read the cookie store of the requested browser:
  /// locked browser DB (yt-dlp issue 7271), unsupported profile, or
  /// Windows DPAPI decrypt failure (yt-dlp issue 10927). Distinct from
  /// `loginRequired` so the
  /// cookies-from-browser fallback chain advances to the next
  /// candidate (Edge → Firefox → …) instead of misrouting to the
  /// auto-login flow. Production log 2026-05-12 §138 caught this
  /// silently failing the entire YouTube retry path.
  cookieDbLocked,

  // Storage errors
  diskFull,
  permissionDenied,
  pathNotFound,

  // General
  unknown,
}

extension DownloadErrorCodeX on DownloadErrorCode {
  /// Whether this is a network-related error that may resolve on reconnect.
  bool get isNetworkError => switch (this) {
    DownloadErrorCode.networkOffline ||
    DownloadErrorCode.networkTimeout ||
    DownloadErrorCode.serverError ||
    DownloadErrorCode.connectionRefused ||
    DownloadErrorCode.sslError => true,
    _ => false,
  };

  /// Whether this error type is worth automatically retrying.
  ///
  /// [accessDenied] (HTTP 403) is NOT retryable — retrying with the same
  /// URL will fail again (CDN URL expired or genuine access block).
  bool get isRetryable => switch (this) {
    DownloadErrorCode.networkOffline ||
    DownloadErrorCode.networkTimeout ||
    DownloadErrorCode.serverError ||
    DownloadErrorCode.connectionRefused ||
    DownloadErrorCode.sslError ||
    DownloadErrorCode.rateLimited => true,
    _ => false,
  };

  /// User-facing hint suggesting how to resolve this error.
  /// Resolves via AppLocalizations at runtime — locale-aware,
  /// matches the rest of the error feedback voice (`errorFeedback.hint.*`).
  /// Every enum value has a dedicated hint key (no more 'unknown' fallback
  /// for `binaryNotAvailable` / `ffmpegError` / `sslError` — the prior
  /// fallback caused the diagnose-panel title to read the generic
  /// "unexpected error" line while the body rendered code-specific text).
  String get hint => AppLocalizations.errorFeedbackHint(name);

  /// User-facing short title for this error type (snackbar headline).
  /// One-to-one mapping with enum name; same coverage guarantee as [hint].
  String get title => AppLocalizations.errorFeedbackTitle(name);

  /// Semantic icon for each error type.
  IconData get icon => switch (this) {
    DownloadErrorCode.networkOffline => Icons.wifi_off_rounded,
    DownloadErrorCode.networkTimeout => Icons.timer_off_rounded,
    DownloadErrorCode.serverError => Icons.cloud_off_rounded,
    DownloadErrorCode.connectionRefused => Icons.link_off_rounded,
    DownloadErrorCode.sslError => Icons.shield_rounded,
    DownloadErrorCode.videoNotFound => Icons.videocam_off_rounded,
    DownloadErrorCode.geoRestricted => Icons.location_off_rounded,
    DownloadErrorCode.loginRequired => Icons.lock_rounded,
    DownloadErrorCode.ageRestricted => Icons.no_adult_content_rounded,
    DownloadErrorCode.formatUnavailable => Icons.format_list_bulleted_rounded,
    DownloadErrorCode.rateLimited => Icons.speed_rounded,
    DownloadErrorCode.accessDenied => Icons.block_rounded,
    DownloadErrorCode.contentUnavailable => Icons.cloud_off_rounded,
    DownloadErrorCode.ytdlpBinaryMissing => Icons.terminal_rounded,
    DownloadErrorCode.binaryNotAvailable =>
      Icons.desktop_access_disabled_rounded,
    DownloadErrorCode.ffmpegError => Icons.broken_image_rounded,
    DownloadErrorCode.jsRuntimeUnavailable => Icons.javascript_rounded,
    DownloadErrorCode.cookieDbLocked => Icons.cookie_outlined,
    DownloadErrorCode.diskFull => Icons.storage_rounded,
    DownloadErrorCode.permissionDenied => Icons.folder_off_rounded,
    DownloadErrorCode.pathNotFound => Icons.folder_delete_rounded,
    DownloadErrorCode.unknown => Icons.error_outline_rounded,
  };

  /// Parse error code from stored `errorCode:rawMessage` format.
  /// Returns null if the string doesn't match any known code.
  static DownloadErrorCode? fromStoredMessage(String? errorMessage) {
    if (errorMessage == null || errorMessage.isEmpty) return null;
    final colonIndex = errorMessage.indexOf(':');
    if (colonIndex < 0) return null;
    final codeName = errorMessage.substring(0, colonIndex);
    for (final code in DownloadErrorCode.values) {
      if (code.name == codeName) return code;
    }
    return null;
  }

  /// Extract the raw error detail from stored `errorCode:rawMessage` format.
  static String? detailFromStoredMessage(String? errorMessage) {
    if (errorMessage == null || errorMessage.isEmpty) return null;
    final colonIndex = errorMessage.indexOf(':');
    if (colonIndex < 0) return errorMessage; // Legacy format: return as-is
    return errorMessage.substring(colonIndex + 1);
  }
}
