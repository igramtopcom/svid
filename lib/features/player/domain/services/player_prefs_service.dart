import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/logging/app_logger.dart';

/// Persists per-file player preferences (speed, volume, subtitle style, track
/// selection) across app restarts, keyed by a SHA-1 hash of the canonical URL.
///
/// Graceful degradation: read/write errors are caught and logged — never crash.
class PlayerPrefsService {
  final SharedPreferences _prefs;

  static const _keyPrefix = 'player_prefs_';

  // Query params that carry no content identity — strip before hashing.
  static const _paramsToStrip = {
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'si', 'pp', 'feature', 'fbclid', 'gclid', 'igshid', 'ref',
  };

  PlayerPrefsService(this._prefs);

  /// Returns saved preferences for [url], or null if not found / parse error.
  Future<PlayerPrefs?> getPrefs(String url) async {
    final key = _keyFor(url);
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return PlayerPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      appLogger.debug('PlayerPrefsService: corrupt prefs for $url — clearing: $e');
      await _prefs.remove(key);
      return null;
    }
  }

  /// Saves [prefs] for [url]. Errors are caught and logged (never rethrow).
  Future<void> savePrefs(String url, PlayerPrefs prefs) async {
    final key = _keyFor(url);
    try {
      await _prefs.setString(key, jsonEncode(prefs.toJson()));
    } catch (e) {
      appLogger.debug('PlayerPrefsService: failed to save prefs for $url: $e');
    }
  }

  /// Removes saved preferences for [url].
  Future<void> clearPrefs(String url) async {
    await _prefs.remove(_keyFor(url));
  }

  /// Removes ALL saved player preferences (exposed for "Clear player prefs" setting).
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Key helpers — exposed via @visibleForTesting statics for unit tests
  // ---------------------------------------------------------------------------

  /// SharedPreferences key for [url]. Exposed for tests.
  @visibleForTesting
  static String keyFor(String url) => _keyFor(url);

  static String _keyFor(String url) {
    final canonical = _canonicalUrl(url);
    final hash = sha1.convert(utf8.encode(canonical)).toString();
    return '$_keyPrefix$hash';
  }

  /// Canonical form of [rawUrl]: strips tracking params, preserves content ID.
  /// Exposed for tests.
  @visibleForTesting
  static String canonicalUrl(String rawUrl) => _canonicalUrl(rawUrl);

  static String _canonicalUrl(String rawUrl) {
    final Uri uri;
    try {
      uri = Uri.parse(rawUrl);
      if (!uri.hasScheme) return rawUrl;
    } catch (_) {
      return rawUrl;
    }

    final cleaned = Map.fromEntries(
      uri.queryParameters.entries.where(
        (e) => !_paramsToStrip.contains(e.key) && !e.key.startsWith('utm_'),
      ),
    );

    // Nothing was stripped — return original string unchanged.
    if (cleaned.length == uri.queryParameters.length) return rawUrl;

    if (cleaned.isEmpty) {
      // Strip query entirely — take everything up to the '?' character.
      final q = rawUrl.indexOf('?');
      return q == -1 ? rawUrl : rawUrl.substring(0, q);
    }

    return uri.replace(queryParameters: cleaned).toString();
  }
}

// ---------------------------------------------------------------------------
// PlayerPrefs value class
// ---------------------------------------------------------------------------

/// Snapshot of player preferences for a specific media file.
class PlayerPrefs {
  final double speed;
  final double volume;
  final String? subtitleTrackId;
  final String? audioTrackId;
  final double subtitleFontSize;
  final int subtitleDelay;

  const PlayerPrefs({
    this.speed = 1.0,
    this.volume = 1.0,
    this.subtitleTrackId,
    this.audioTrackId,
    this.subtitleFontSize = 32.0,
    this.subtitleDelay = 0,
  });

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'volume': volume,
    if (subtitleTrackId != null) 'subtitleTrackId': subtitleTrackId,
    if (audioTrackId != null) 'audioTrackId': audioTrackId,
    'subtitleFontSize': subtitleFontSize,
    'subtitleDelay': subtitleDelay,
  };

  factory PlayerPrefs.fromJson(Map<String, dynamic> json) => PlayerPrefs(
    speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    subtitleTrackId: json['subtitleTrackId'] as String?,
    audioTrackId: json['audioTrackId'] as String?,
    subtitleFontSize: (json['subtitleFontSize'] as num?)?.toDouble() ?? 32.0,
    subtitleDelay: (json['subtitleDelay'] as int?) ?? 0,
  );
}
