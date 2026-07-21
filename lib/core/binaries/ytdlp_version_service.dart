import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../network/shared_http_client.dart';

/// Service for checking yt-dlp versions against GitHub releases.
///
/// The app tracks yt-dlp's official `master` binary channel so extractor fixes
/// can reach users without waiting for stable releases. yt-dlp uses date-based
/// versioning: `YYYY.MM.DD[.N]` (not semver).
class YtDlpVersionService {
  static const String _githubApiUrl =
      'https://api.github.com/repos/yt-dlp/yt-dlp-master-builds/releases/latest';

  final http.Client _client;

  /// Default client is the process-lifetime [SharedHttpClient.instance]
  /// so repeated version-check calls don't rebuild the TLS socket pool.
  /// The singleton's `close()` is a no-op, keeping [dispose] safe.
  YtDlpVersionService({http.Client? client})
    : _client = client ?? SharedHttpClient.instance;

  /// Fetch the latest yt-dlp master-build version from GitHub API.
  /// Returns tag_name (e.g. "2026.05.25.232152") or null on error.
  Future<String?> fetchLatestVersion() async {
    try {
      final response = await _client
          .get(
            Uri.parse(_githubApiUrl),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent':
                  '${BrandConfig.current.appName}/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [YtDlpVersionService] GitHub API returned ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String?;
      return tagName;
    } catch (e) {
      debugPrint('⚠️ [YtDlpVersionService] Failed to fetch latest version: $e');
      return null;
    }
  }

  /// Compare two yt-dlp versions (date-based: YYYY.MM.DD[.N]).
  /// Returns true if [latest] is newer than [installed].
  bool isNewerVersion(String latest, String installed) {
    final latestParts = _parseVersion(latest);
    final installedParts = _parseVersion(installed);

    if (latestParts == null || installedParts == null) return false;

    for (var i = 0; i < latestParts.length || i < installedParts.length; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final r = i < installedParts.length ? installedParts[i] : 0;
      if (l > r) return true;
      if (l < r) return false;
    }
    return false; // equal
  }

  /// Check if an update is available by comparing installed version with GitHub.
  Future<bool> isUpdateAvailable(String? installedVersion) async {
    if (installedVersion == null || installedVersion.isEmpty) return false;

    final latest = await fetchLatestVersion();
    if (latest == null) return false;

    return isNewerVersion(latest, installedVersion);
  }

  /// Parse version string "YYYY.MM.DD[.N]" into list of ints.
  /// Returns null if format is invalid.
  List<int>? _parseVersion(String version) {
    // Strip leading/trailing whitespace
    final trimmed = version.trim();
    final parts = trimmed.split('.');
    if (parts.length < 3) return null;

    try {
      return parts.map((p) => int.parse(p)).toList();
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
