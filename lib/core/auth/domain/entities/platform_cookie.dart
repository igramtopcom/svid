import 'package:freezed_annotation/freezed_annotation.dart';

part 'platform_cookie.freezed.dart';

/// Platform authentication cookie entity
/// Stores encrypted cookies for authenticated downloads
@freezed
class PlatformCookie with _$PlatformCookie {
  const PlatformCookie._();

  const factory PlatformCookie({
    required String platform, // "youtube", "instagram", "facebook", etc.
    required String cookieString, // Formatted cookie string
    required DateTime savedAt,
    DateTime? expiresAt,
  }) = _PlatformCookie;

  /// Check if cookie is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if cookie is still valid
  bool get isValid => !isExpired;

  /// Get display name for platform
  String get platformDisplayName {
    return platform[0].toUpperCase() + platform.substring(1);
  }
}
