import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';
import 'brand_config.dart';

/// Resolves the default download folder for first-launch installs.
///
/// Lives at the brand layer because each brand has its own folder
/// history that we must respect:
///
/// - **Svid** (existing production users): `getDownloadsDirectory()` —
///   raw `~/Downloads/`. Behavior preserved unchanged so no current user
///   is broken.
///
/// - **VidCombo** (legacy users on old PHP/ObjectBox app): existing
///   downloads live at `~/Documents/VidCombo/` or `~/Downloads/VidCombo/`.
///   We auto-detect those folders and use them as the default so file
///   layout is preserved with zero file moves. New installs get the
///   industry-standard branded subfolder under the OS Downloads dir.
///
/// Called only on first launch (when settings storage is empty / placeholder).
/// Existing user settings are NEVER touched.
class BrandDownloadPathResolver {
  const BrandDownloadPathResolver();

  /// Media file extensions used to confirm a legacy folder is "live"
  /// (i.e. has actual content worth preserving). Matches the importer.
  static const _legacyMediaExts = <String>{
    '.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi', '.flv', '.ts',
    '.mp3', '.m4a', '.opus', '.ogg', '.wav', '.flac', '.aac',
  };

  Future<String> resolveFirstLaunchDefault() async {
    final brand = BrandConfig.current.brand;
    if (brand == Brand.vidcombo) {
      final legacy = await detectVidComboLegacyFolder();
      if (legacy != null) {
        appLogger.info(
          '[BrandDownloadPathResolver] VidCombo legacy folder detected: $legacy',
        );
        return legacy;
      }
      return _osBrandedDefault('VidCombo');
    }

    // Svid: keep current behavior 100% unchanged.
    return _svidPlatformDefault();
  }

  /// Returns the path of the most-populated VidCombo legacy folder, or null
  /// if no candidate has any media file in it.
  ///
  /// [homeOverride] and [oneDriveOverride] are exposed for unit tests so the
  /// folder probe can be exercised against a temp directory without mutating
  /// the host's `HOME` / `USERPROFILE` / `OneDrive` env vars. Production
  /// callers leave both null to read from `Platform.environment`.
  @visibleForTesting
  Future<String?> detectVidComboLegacyFolder({
    String? homeOverride,
    String? oneDriveOverride,
  }) async {
    // Windows uses USERPROFILE; POSIX uses HOME. Must not rely on HOME
    // universally or fresh VidCombo installs on Windows skip legacy detection.
    final home = homeOverride ??
        (Platform.isWindows
            ? (Platform.environment['USERPROFILE'] ?? '')
            : (Platform.environment['HOME'] ?? ''));
    if (home.isEmpty) return null;

    final candidates = <String>{
      p.join(home, 'Documents', 'VidCombo'),
      p.join(home, 'Downloads', 'VidCombo'),
      p.join(home, 'Downloads', 'VidCombo App Downloader'),
      // Mirror the importer's cloud-provider probes so default save-path
      // detection stays consistent with what the importer actually
      // imports. See vidcombo_legacy_importer.dart.
      p.join(home, 'Dropbox', 'VidCombo'),
      p.join(home, 'Dropbox', 'Documents', 'VidCombo'),
      p.join(home, 'Dropbox', 'Downloads', 'VidCombo'),
      p.join(home, 'Google Drive', 'VidCombo'),
      p.join(home, 'Google Drive', 'Documents', 'VidCombo'),
      p.join(home, 'Google Drive', 'Downloads', 'VidCombo'),
    };

    // Windows: OneDrive often redirects Documents/Downloads. Check the
    // resolved OneDrive root too so legacy users on OneDrive-backed folders
    // still get auto-detected.
    final oneDrive = oneDriveOverride ??
        (Platform.isWindows ? (Platform.environment['OneDrive'] ?? '') : '');
    if (oneDrive.isNotEmpty) {
      candidates
        ..add(p.join(oneDrive, 'Documents', 'VidCombo'))
        ..add(p.join(oneDrive, 'Downloads', 'VidCombo'))
        ..add(p.join(oneDrive, 'Downloads', 'VidCombo App Downloader'));
    }

    String? best;
    int bestCount = 0;
    for (final candidate in candidates) {
      try {
        final dir = Directory(candidate);
        if (!await dir.exists()) continue;
        final count = await _countMediaFiles(dir);
        if (count > bestCount) {
          best = candidate;
          bestCount = count;
        }
      } catch (e) {
        appLogger.debug(
          '[BrandDownloadPathResolver] candidate scan failed for '
          '$candidate: $e',
        );
      }
    }
    return best;
  }

  Future<int> _countMediaFiles(Directory dir) async {
    var count = 0;
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (_legacyMediaExts.contains(ext)) count++;
      }
    } catch (_) {
      // ignore — permission denied, etc.
    }
    return count;
  }

  /// Svid pre-existing default — kept identical to the old inline logic
  /// in settings_provider so existing users see no behavior change.
  Future<String> _svidPlatformDefault() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return downloadsDir.path;
    } catch (e) {
      appLogger.debug('[BrandDownloadPathResolver] getDownloadsDirectory: $e');
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// New-install default for a branded app: place a subfolder under the
  /// OS-conventional Downloads directory. Falls back to documents dir.
  Future<String> _osBrandedDefault(String brandFolder) async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        final branded = Directory(p.join(downloadsDir.path, brandFolder));
        try {
          if (!await branded.exists()) {
            await branded.create(recursive: true);
          }
        } catch (e) {
          appLogger.debug(
            '[BrandDownloadPathResolver] could not create $branded: $e',
          );
        }
        return branded.path;
      }
    } catch (e) {
      appLogger.debug('[BrandDownloadPathResolver] getDownloadsDirectory: $e');
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, brandFolder);
  }
}
