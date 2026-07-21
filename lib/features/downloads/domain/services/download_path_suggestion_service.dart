import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/platform_detector.dart';
import '../entities/video_info.dart';

/// Suggests download paths based on platform and media type.
///
/// Organizes downloads into branded subdirectories:
/// `{basePath}/{Brand} App Downloader/{Platform Category}/`
///
/// The brand prefix is resolved at runtime from
/// [BrandConfig.current.appName] rather than hard-coded, so a
/// VidCombo build lands files in `VidCombo App Downloader/` and an
/// Svid build lands them in `Svid App Downloader/`. Pre-fix the
/// constant was literal `'Svid App Downloader'`, which violated the
/// multi-brand contract (`.claude/rules/brand-config.md`: "ALL
/// brand-specific values through `BrandConfig.current` — never
/// hardcode") and caused VidCombo testers to see their files land
/// in an `Svid App Downloader/` folder on disk.
class DownloadPathSuggestionService {
  /// Branded download folder name resolved at access time from
  /// [BrandConfig.current]. Kept as a getter (not `static const`)
  /// so the value tracks whatever `--dart-define=BRAND=...` the
  /// current build was compiled with, with no risk of a stale
  /// compile-time constant baked from one brand leaking into the
  /// other.
  static String get brandFolder =>
      '${BrandConfig.current.appName} App Downloader';

  /// Returns a platform-specific subdirectory name based on the video platform
  /// and the selected media type.
  String suggestSubdirectory(VideoPlatform platform, MediaType mediaType) {
    switch (platform) {
      case VideoPlatform.youtube:
        return switch (mediaType) {
          MediaType.video => 'YouTube Videos',
          MediaType.audio => 'YouTube Music',
          MediaType.image => 'YouTube',
          MediaType.subtitle => 'YouTube Subtitles',
        };
      case VideoPlatform.tiktok:
        return switch (mediaType) {
          MediaType.video => 'TikTok Videos',
          MediaType.audio => 'TikTok Music',
          MediaType.image => 'TikTok',
          MediaType.subtitle => 'TikTok Subtitles',
        };
      case VideoPlatform.instagram:
        return switch (mediaType) {
          MediaType.video => 'Instagram Reels',
          MediaType.audio => 'Instagram',
          MediaType.image => 'Instagram Photos',
          MediaType.subtitle => 'Instagram Subtitles',
        };
      case VideoPlatform.facebook:
        return switch (mediaType) {
          MediaType.video => 'Facebook Videos',
          MediaType.audio => 'Facebook',
          MediaType.image => 'Facebook',
          MediaType.subtitle => 'Facebook Subtitles',
        };
      case VideoPlatform.twitter:
        return switch (mediaType) {
          MediaType.video => 'Twitter Videos',
          MediaType.audio => 'Twitter',
          MediaType.image => 'Twitter',
          MediaType.subtitle => 'Twitter Subtitles',
        };
      case VideoPlatform.reddit:
        return switch (mediaType) {
          MediaType.video => 'Reddit Videos',
          MediaType.audio => 'Reddit',
          MediaType.image => 'Reddit',
          MediaType.subtitle => 'Reddit Subtitles',
        };
      case VideoPlatform.pinterest:
        return switch (mediaType) {
          MediaType.video => 'Pinterest',
          MediaType.audio => 'Pinterest',
          MediaType.image => 'Pinterest Photos',
          MediaType.subtitle => 'Pinterest Subtitles',
        };
      case VideoPlatform.vimeo:
        return switch (mediaType) {
          MediaType.video => 'Vimeo Videos',
          MediaType.audio => 'Vimeo',
          MediaType.image => 'Vimeo',
          MediaType.subtitle => 'Vimeo Subtitles',
        };
      case VideoPlatform.dailymotion:
        return switch (mediaType) {
          MediaType.video => 'Dailymotion Videos',
          MediaType.audio => 'Dailymotion',
          MediaType.image => 'Dailymotion',
          MediaType.subtitle => 'Dailymotion Subtitles',
        };
      case VideoPlatform.soundcloud:
        return switch (mediaType) {
          MediaType.video => 'SoundCloud',
          MediaType.audio => 'SoundCloud Music',
          MediaType.image => 'SoundCloud',
          MediaType.subtitle => 'SoundCloud Subtitles',
        };
      case VideoPlatform.bilibili:
        return switch (mediaType) {
          MediaType.video => 'Bilibili Videos',
          MediaType.audio => 'Bilibili Music',
          MediaType.image => 'Bilibili',
          MediaType.subtitle => 'Bilibili Subtitles',
        };
      case VideoPlatform.linkedin:
        return switch (mediaType) {
          MediaType.video => 'LinkedIn Videos',
          MediaType.audio => 'LinkedIn',
          MediaType.image => 'LinkedIn',
          MediaType.subtitle => 'LinkedIn Subtitles',
        };
      case VideoPlatform.douyin:
        return switch (mediaType) {
          MediaType.video => 'Douyin Videos',
          MediaType.audio => 'Douyin',
          MediaType.image => 'Douyin',
          MediaType.subtitle => 'Douyin Subtitles',
        };
      case VideoPlatform.threads:
        return switch (mediaType) {
          MediaType.video => 'Threads Videos',
          MediaType.audio => 'Threads',
          MediaType.image => 'Threads Photos',
          MediaType.subtitle => 'Threads Subtitles',
        };
      case VideoPlatform.unknown:
        return switch (mediaType) {
          MediaType.video => 'Videos',
          MediaType.audio => 'Music',
          MediaType.image => 'Images',
          MediaType.subtitle => 'Subtitles',
        };
    }
  }

  /// Constructs the full branded output path without touching the filesystem.
  String buildOutputPath(String basePath, String subdirectory) {
    return p.join(basePath, brandFolder, subdirectory);
  }

  /// Constructs the full path `basePath/Svid App Downloader/subdirectory`
  /// and creates the directory recursively.
  ///
  /// [directoryFactory] is injectable for testing.
  /// Throws [AppException.permission] if the directory cannot be created.
  Future<String> resolveAndCreate(
    String basePath,
    String subdirectory, {
    Directory Function(String)? directoryFactory,
  }) async {
    final factory = directoryFactory ?? Directory.new;
    final dir = factory(buildOutputPath(basePath, subdirectory));
    try {
      await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw AppException.permission(
        message: 'Cannot create download folder: ${e.message} at ${dir.path}',
        resource: dir.path,
      );
    }
    return dir.path;
  }
}
