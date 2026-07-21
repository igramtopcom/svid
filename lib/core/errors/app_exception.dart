import 'dart:io' show ProcessException;

import 'package:freezed_annotation/freezed_annotation.dart';
import '../l10n/app_localizations.dart';

part 'app_exception.freezed.dart';

/// Base exception class for the application
@freezed
class AppException with _$AppException implements Exception {
  const factory AppException.network({
    required String message,
    int? statusCode,
    dynamic data,
  }) = NetworkException;

  const factory AppException.download({
    required String message,
    String? url,
    dynamic data,
  }) = DownloadException;

  const factory AppException.storage({
    required String message,
    String? path,
    dynamic data,
  }) = StorageException;

  const factory AppException.permission({
    required String message,
    String? resource,
  }) = PermissionException;

  const factory AppException.validation({
    required String message,
    Map<String, String>? errors,
  }) = ValidationException;

  const factory AppException.unknown({
    required String message,
    dynamic error,
    StackTrace? stackTrace,
  }) = UnknownException;

  const factory AppException.rust({
    required String message,
    String? details,
  }) = RustException;
}

/// Extension methods for AppException
extension AppExceptionX on AppException {
  /// Get a user-friendly error message
  String get userMessage => when(
        network: (message, statusCode, data) =>
            statusCode != null ? 'Network error ($statusCode): $message' : 'Network error: $message',
        download: (message, url, data) => 'Download failed: $message',
        storage: (message, path, data) => 'Storage error: $message',
        permission: (message, resource) => 'Permission denied: $message',
        validation: (message, errors) => 'Validation error: $message',
        unknown: (message, error, stackTrace) => 'An error occurred: $message',
        rust: (message, details) => 'Native error: $message',
      );

  /// Check if this is a network-related error
  bool get isNetworkError => this is NetworkException;

  /// Check if this is a download-related error
  bool get isDownloadError => this is DownloadException;

  /// Check if this is a storage-related error
  bool get isStorageError => this is StorageException;

  /// Extract a clean, user-readable error message from any error object.
  /// Use this instead of `e.toString()` in catch blocks shown to users.
  static String readableMessage(Object error) {
    if (error is AppException) return error.message;
    if (error is ProcessException) return error.message;
    final s = error.toString();
    // Strip Dart class prefixes like "Exception: ", "FormatException: "
    final stripped = s.replaceFirst(RegExp(r'^[\w]+Exception:\s*'), '');
    // Detect "Instance of 'X'" — return generic message instead
    if (stripped.startsWith('Instance of')) return 'An unexpected error occurred';
    return stripped;
  }

  /// Get a localized user-friendly error message.
  /// Use this instead of [userMessage] when you have access to localization.
  String get localizedMessage => when(
        network: (message, statusCode, data) => statusCode != null
            ? AppLocalizations.errorNetworkWithCode(statusCode, message)
            : AppLocalizations.errorNetwork(message),
        download: (message, url, data) => AppLocalizations.errorDownload(message),
        storage: (message, path, data) => AppLocalizations.errorStorage(message),
        permission: (message, resource) => AppLocalizations.errorPermission(message),
        validation: (message, errors) => AppLocalizations.errorValidation(message),
        unknown: (message, error, stackTrace) => AppLocalizations.errorUnknown(message),
        rust: (message, details) => AppLocalizations.errorNative(message),
      );
}
