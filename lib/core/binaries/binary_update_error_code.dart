import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Structured error codes for binary update failures.
/// Used by BinaryManager.updateBinarySafely() and settings screen.
enum BinaryUpdateErrorCode {
  // Network
  networkOffline,
  networkTimeout,
  httpError,

  // File system
  permissionDenied,
  diskFull,
  backupFailed,

  // Archive
  extractionFailed,
  archiveCorrupt,

  // General
  unknown,
}

extension BinaryUpdateErrorCodeX on BinaryUpdateErrorCode {
  /// User-friendly recovery hint (l10n key).
  String get hint => switch (this) {
    BinaryUpdateErrorCode.networkOffline => AppLocalizations.binaryUpdateHintNetworkOffline,
    BinaryUpdateErrorCode.networkTimeout => AppLocalizations.binaryUpdateHintNetworkTimeout,
    BinaryUpdateErrorCode.httpError => AppLocalizations.binaryUpdateHintHttpError,
    BinaryUpdateErrorCode.permissionDenied => AppLocalizations.binaryUpdateHintPermissionDenied,
    BinaryUpdateErrorCode.diskFull => AppLocalizations.binaryUpdateHintDiskFull,
    BinaryUpdateErrorCode.backupFailed => AppLocalizations.binaryUpdateHintBackupFailed,
    BinaryUpdateErrorCode.extractionFailed => AppLocalizations.binaryUpdateHintExtractionFailed,
    BinaryUpdateErrorCode.archiveCorrupt => AppLocalizations.binaryUpdateHintArchiveCorrupt,
    BinaryUpdateErrorCode.unknown => AppLocalizations.binaryUpdateHintUnknown,
  };

  /// Whether this error type is worth automatically retrying.
  bool get isRetryable => switch (this) {
    BinaryUpdateErrorCode.networkOffline ||
    BinaryUpdateErrorCode.networkTimeout ||
    BinaryUpdateErrorCode.httpError => true,
    _ => false,
  };

  /// Semantic icon for each error type.
  IconData get icon => switch (this) {
    BinaryUpdateErrorCode.networkOffline => Icons.wifi_off_rounded,
    BinaryUpdateErrorCode.networkTimeout => Icons.timer_off_rounded,
    BinaryUpdateErrorCode.httpError => Icons.cloud_off_rounded,
    BinaryUpdateErrorCode.permissionDenied => Icons.folder_off_rounded,
    BinaryUpdateErrorCode.diskFull => Icons.storage_rounded,
    BinaryUpdateErrorCode.backupFailed => Icons.backup_rounded,
    BinaryUpdateErrorCode.extractionFailed => Icons.unarchive_rounded,
    BinaryUpdateErrorCode.archiveCorrupt => Icons.broken_image_rounded,
    BinaryUpdateErrorCode.unknown => Icons.error_outline_rounded,
  };

  /// Classify a raw error message into a structured error code.
  static BinaryUpdateErrorCode classify(String rawError) {
    final lower = rawError.toLowerCase();

    // Network errors
    if (lower.contains('socketexception') ||
        lower.contains('no internet') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup')) {
      return BinaryUpdateErrorCode.networkOffline;
    }
    if (lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('connection timed out')) {
      return BinaryUpdateErrorCode.networkTimeout;
    }
    if (lower.contains('http 4') ||
        lower.contains('http 5') ||
        lower.contains('download failed: http')) {
      return BinaryUpdateErrorCode.httpError;
    }

    // File system errors
    if (lower.contains('eacces') ||
        lower.contains('permission denied') ||
        lower.contains('access is denied')) {
      return BinaryUpdateErrorCode.permissionDenied;
    }
    if (lower.contains('enospc') ||
        lower.contains('no space left') ||
        lower.contains('disk full')) {
      return BinaryUpdateErrorCode.diskFull;
    }
    if (lower.contains('backup failed')) {
      return BinaryUpdateErrorCode.backupFailed;
    }

    // Archive errors
    if (lower.contains('not found in archive') ||
        lower.contains('binary not found')) {
      return BinaryUpdateErrorCode.extractionFailed;
    }
    if (lower.contains('unable to detect archive') ||
        lower.contains('invalid archive') ||
        lower.contains('archive corrupt') ||
        lower.contains('formatexception')) {
      return BinaryUpdateErrorCode.archiveCorrupt;
    }

    return BinaryUpdateErrorCode.unknown;
  }
}
