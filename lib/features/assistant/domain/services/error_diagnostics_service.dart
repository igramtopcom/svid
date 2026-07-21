import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

const _storageKey = 'agent_error_incidents';
const _maxIncidents = 200;

/// A single recorded error incident.
class ErrorIncident {
  final String platform;
  final DownloadErrorCode errorCode;
  final String? errorDetail;
  final String? url;
  final DateTime timestamp;
  final bool wasAutoHealed;

  const ErrorIncident({
    required this.platform,
    required this.errorCode,
    this.errorDetail,
    this.url,
    required this.timestamp,
    this.wasAutoHealed = false,
  });

  Map<String, dynamic> toJson() => {
    'p': platform,
    'c': errorCode.name,
    'd': errorDetail,
    'u': url,
    't': timestamp.millisecondsSinceEpoch,
    'h': wasAutoHealed,
  };

  factory ErrorIncident.fromJson(Map<String, dynamic> json) {
    final codeName = json['c'] as String;
    final code = DownloadErrorCode.values.firstWhere(
      (e) => e.name == codeName,
      orElse: () => DownloadErrorCode.unknown,
    );
    return ErrorIncident(
      platform: json['p'] as String,
      errorCode: code,
      errorDetail: json['d'] as String?,
      url: json['u'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      wasAutoHealed: json['h'] as bool? ?? false,
    );
  }
}

/// A detected pattern across multiple incidents.
class ErrorPattern {
  final DownloadErrorCode errorCode;
  final String? platform;
  final int occurrences;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int autoHealedCount;

  const ErrorPattern({
    required this.errorCode,
    this.platform,
    required this.occurrences,
    required this.firstSeen,
    required this.lastSeen,
    this.autoHealedCount = 0,
  });

  /// Whether this is a "hot" pattern (3+ in 24h).
  bool get isHot {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return lastSeen.isAfter(cutoff) && occurrences >= 3;
  }

  /// Auto-heal success rate (0.0 to 1.0).
  double get healRate => occurrences > 0 ? autoHealedCount / occurrences : 0.0;

  /// Human-readable time span — locale-aware unit suffix resolved via
  /// `AppLocalizations.diagnosticsTimeSpan(...)`. Bucket selection (minutes /
  /// hours / days) is identical to the prior hardcoded version; only the
  /// rendered unit text localizes.
  String get timeSpan {
    final diff = lastSeen.difference(firstSeen);
    return AppLocalizations.diagnosticsTimeSpan(
      minutes: diff.inMinutes,
      hours: diff.inHours,
      days: diff.inDays,
    );
  }
}

/// A diagnosis with confidence and recommended actions.
class ErrorDiagnosis {
  final DownloadErrorCode errorCode;
  final String title;
  final String explanation;
  final double confidence;
  final List<RecommendedAction> actions;
  final ErrorPattern? pattern;

  const ErrorDiagnosis({
    required this.errorCode,
    required this.title,
    required this.explanation,
    required this.confidence,
    required this.actions,
    this.pattern,
  });

  String get confidenceLabel => '${(confidence * 100).round()}%';
}

/// A recommended action to resolve an error.
class RecommendedAction {
  final String label;
  final String description;
  final RecommendedActionType type;

  const RecommendedAction({
    required this.label,
    required this.description,
    required this.type,
  });
}

enum RecommendedActionType {
  autoRetry,
  updateYtdlp,
  checkNetwork,
  useVpn,
  addCookies,
  changeSavePath,
  freeDiskSpace,
  tryAlternateQuality,
  waitAndRetry,
  manualRetry,
}

/// State for the error diagnostics service.
class ErrorDiagnosticsState {
  final List<ErrorIncident> incidents;
  final List<ErrorPattern> patterns;

  const ErrorDiagnosticsState({
    this.incidents = const [],
    this.patterns = const [],
  });

  /// Total incidents recorded.
  int get totalIncidents => incidents.length;

  /// Incidents from the last 24 hours.
  List<ErrorIncident> get recentIncidents {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return incidents.where((i) => i.timestamp.isAfter(cutoff)).toList();
  }

  /// Overall auto-heal success rate.
  double get overallHealRate {
    if (incidents.isEmpty) return 0.0;
    final healed = incidents.where((i) => i.wasAutoHealed).length;
    return healed / incidents.length;
  }

  /// Hot patterns (3+ occurrences in 24h).
  List<ErrorPattern> get hotPatterns => patterns.where((p) => p.isHot).toList();
}

/// Tracks download errors, detects patterns, and provides diagnoses.
///
/// This is the "Forensics Lab" — transforms cryptic errors into
/// actionable intelligence with pattern detection.
class ErrorDiagnosticsNotifier extends StateNotifier<ErrorDiagnosticsState> {
  final SharedPreferences _prefs;

  ErrorDiagnosticsNotifier(this._prefs) : super(const ErrorDiagnosticsState()) {
    _load();
  }

  void _load() {
    try {
      final json = _prefs.getString(_storageKey);
      if (json == null) return;
      final list =
          (jsonDecode(json) as List)
              .map((e) => ErrorIncident.fromJson(e as Map<String, dynamic>))
              .toList();
      state = ErrorDiagnosticsState(
        incidents: list,
        patterns: _computePatterns(list),
      );
    } catch (e) {
      appLogger.warning('ErrorDiagnostics: failed to load: $e');
    }
  }

  Future<void> _save() async {
    try {
      final list = state.incidents.map((e) => e.toJson()).toList();
      await _prefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      appLogger.warning('ErrorDiagnostics: failed to save: $e');
    }
  }

  /// Record a download failure. Called from download watcher.
  Future<void> recordFailure(DownloadEntity download) async {
    final errorCode = download.errorCode ?? DownloadErrorCode.unknown;
    final incident = ErrorIncident(
      platform: download.platform,
      errorCode: errorCode,
      errorDetail: download.errorDetail,
      url: download.url,
      timestamp: DateTime.now(),
      wasAutoHealed: false,
    );

    final updated = [...state.incidents, incident];
    // Trim to max size
    final trimmed =
        updated.length > _maxIncidents
            ? updated.sublist(updated.length - _maxIncidents)
            : updated;

    state = ErrorDiagnosticsState(
      incidents: trimmed,
      patterns: _computePatterns(trimmed),
    );
    await _save();

    appLogger.info(
      '🔬 ErrorDiagnostics: recorded ${errorCode.name} '
      'for ${download.platform} (${state.totalIncidents} total)',
    );
  }

  /// Mark an incident as auto-healed (download succeeded after retry).
  Future<void> markHealed(DownloadEntity download) async {
    final url = download.url;
    final updatedIncidents =
        state.incidents.map((i) {
          if (i.url == url && !i.wasAutoHealed) {
            return ErrorIncident(
              platform: i.platform,
              errorCode: i.errorCode,
              errorDetail: i.errorDetail,
              url: i.url,
              timestamp: i.timestamp,
              wasAutoHealed: true,
            );
          }
          return i;
        }).toList();

    state = ErrorDiagnosticsState(
      incidents: updatedIncidents,
      patterns: _computePatterns(updatedIncidents),
    );
    await _save();
  }

  /// Diagnose a specific download failure.
  ErrorDiagnosis diagnose(DownloadEntity download) {
    final errorCode = download.errorCode ?? DownloadErrorCode.unknown;
    final platform = download.platform;

    // Find matching pattern
    final pattern = state.patterns
        .where(
          (p) =>
              p.errorCode == errorCode &&
              (p.platform == null || p.platform == platform),
        )
        .fold<ErrorPattern?>(
          null,
          (best, p) =>
              best == null || p.occurrences > best.occurrences ? p : best,
        );

    return _buildDiagnosis(errorCode, platform, pattern);
  }

  /// Diagnose by error code (without a specific download).
  ErrorDiagnosis diagnoseByCode(DownloadErrorCode code, {String? platform}) {
    final pattern = state.patterns
        .where(
          (p) =>
              p.errorCode == code &&
              (platform == null ||
                  p.platform == null ||
                  p.platform == platform),
        )
        .fold<ErrorPattern?>(
          null,
          (best, p) =>
              best == null || p.occurrences > best.occurrences ? p : best,
        );

    return _buildDiagnosis(code, platform, pattern);
  }

  ErrorDiagnosis _buildDiagnosis(
    DownloadErrorCode code,
    String? platform,
    ErrorPattern? pattern,
  ) {
    // Confidence: base from error type + boost from pattern data
    double confidence = _baseConfidence(code);
    if (pattern != null && pattern.occurrences >= 3) {
      confidence = (confidence + 0.15).clamp(0.0, 0.99);
    }
    if (pattern != null && pattern.isHot) {
      confidence = (confidence + 0.10).clamp(0.0, 0.99);
    }

    final actions = _recommendActions(code, pattern);
    final title = _diagnosisTitle(code, pattern);
    final explanation = _diagnosisExplanation(code, platform, pattern);

    return ErrorDiagnosis(
      errorCode: code,
      title: title,
      explanation: explanation,
      confidence: confidence,
      actions: actions,
      pattern: pattern,
    );
  }

  double _baseConfidence(DownloadErrorCode code) => switch (code) {
    DownloadErrorCode.networkOffline => 0.95,
    DownloadErrorCode.diskFull => 0.95,
    DownloadErrorCode.permissionDenied => 0.90,
    DownloadErrorCode.pathNotFound => 0.90,
    DownloadErrorCode.geoRestricted => 0.88,
    DownloadErrorCode.loginRequired => 0.87,
    DownloadErrorCode.ageRestricted => 0.87,
    DownloadErrorCode.videoNotFound => 0.85,
    DownloadErrorCode.rateLimited => 0.82,
    DownloadErrorCode.ytdlpBinaryMissing => 0.95,
    DownloadErrorCode.binaryNotAvailable => 0.90,
    DownloadErrorCode.jsRuntimeUnavailable => 0.92,
    DownloadErrorCode.networkTimeout => 0.75,
    DownloadErrorCode.serverError => 0.70,
    DownloadErrorCode.connectionRefused => 0.70,
    DownloadErrorCode.sslError => 0.72,
    DownloadErrorCode.accessDenied => 0.68,
    DownloadErrorCode.formatUnavailable => 0.78,
    DownloadErrorCode.ffmpegError => 0.72,
    DownloadErrorCode.contentUnavailable => 0.80,
    DownloadErrorCode.cookieDbLocked => 0.90,
    DownloadErrorCode.unknown => 0.40,
  };

  String _diagnosisTitle(DownloadErrorCode code, ErrorPattern? pattern) {
    if (pattern != null && pattern.isHot) {
      return '${AppLocalizations.diagnosticsTitlePatternPrefix}${code.hint}';
    }
    return code.hint;
  }

  String _diagnosisExplanation(
    DownloadErrorCode code,
    String? platform,
    ErrorPattern? pattern,
  ) {
    final base = AppLocalizations.diagnosticsExplanation(code.name);

    if (pattern != null && pattern.isHot) {
      final platformLabel =
          platform ?? pattern.platform ?? AppLocalizations.diagnosticsPlatformFallback;
      final healedNote = pattern.autoHealedCount > 0
          ? AppLocalizations.diagnosticsPatternHealedSome(pattern.autoHealedCount)
          : AppLocalizations.diagnosticsPatternHealedNone;
      return AppLocalizations.diagnosticsPatternSummary(
        base: base,
        count: pattern.occurrences,
        span: pattern.timeSpan,
        platform: platformLabel,
        healedNote: healedNote,
      );
    }

    return base;
  }

  /// Build a RecommendedAction with locale-aware label+description resolved
  /// at call time via [AppLocalizations]. The action `type` enum stays as
  /// stable logic key for upstream UI handlers; only the rendered strings
  /// localize.
  RecommendedAction _action(String id, RecommendedActionType type) =>
      RecommendedAction(
        label: AppLocalizations.diagnosticsActionLabel(id),
        description: AppLocalizations.diagnosticsActionDesc(id),
        type: type,
      );

  List<RecommendedAction> _recommendActions(
    DownloadErrorCode code,
    ErrorPattern? pattern,
  ) {
    return switch (code) {
      DownloadErrorCode.networkOffline => [
        _action('checkConnection', RecommendedActionType.checkNetwork),
        if (code.isRetryable)
          _action('autoRetryNetwork', RecommendedActionType.autoRetry),
      ],
      DownloadErrorCode.networkTimeout ||
      DownloadErrorCode.serverError ||
      DownloadErrorCode.connectionRefused => [
        _action('waitAndRetry', RecommendedActionType.waitAndRetry),
        if (pattern != null && pattern.isHot)
          _action('tryVpnHot', RecommendedActionType.useVpn),
      ],
      DownloadErrorCode.sslError => [
        _action('checkVpnAntivirus', RecommendedActionType.checkNetwork),
        _action('retryManualGeneric', RecommendedActionType.manualRetry),
      ],
      DownloadErrorCode.geoRestricted => [
        _action('useVpnGeo', RecommendedActionType.useVpn),
      ],
      DownloadErrorCode.loginRequired || DownloadErrorCode.ageRestricted => [
        _action('addCookies', RecommendedActionType.addCookies),
      ],
      DownloadErrorCode.cookieDbLocked => [
        _action('closeBrowser', RecommendedActionType.addCookies),
      ],
      DownloadErrorCode.videoNotFound ||
      DownloadErrorCode.contentUnavailable => [
        _action('retryManualUrl', RecommendedActionType.manualRetry),
      ],
      DownloadErrorCode.formatUnavailable => [
        _action('tryAltQuality', RecommendedActionType.tryAlternateQuality),
      ],
      DownloadErrorCode.rateLimited => [
        _action('autoRetryRate', RecommendedActionType.autoRetry),
        _action('useVpnRate', RecommendedActionType.useVpn),
      ],
      DownloadErrorCode.accessDenied => [
        _action('reExtract', RecommendedActionType.manualRetry),
      ],
      DownloadErrorCode.ytdlpBinaryMissing ||
      DownloadErrorCode.binaryNotAvailable ||
      DownloadErrorCode.jsRuntimeUnavailable => [
        _action('repairTools', RecommendedActionType.updateYtdlp),
      ],
      DownloadErrorCode.ffmpegError => [
        _action('updateYtdlpFfmpeg', RecommendedActionType.updateYtdlp),
        _action('tryAltQualityFfmpeg', RecommendedActionType.tryAlternateQuality),
      ],
      DownloadErrorCode.diskFull => [
        _action('freeDisk', RecommendedActionType.freeDiskSpace),
        _action('changeSavePathDisk', RecommendedActionType.changeSavePath),
      ],
      DownloadErrorCode.permissionDenied || DownloadErrorCode.pathNotFound => [
        _action('changeSavePathPerm', RecommendedActionType.changeSavePath),
      ],
      DownloadErrorCode.unknown => [
        _action('retryManualGeneric', RecommendedActionType.manualRetry),
        _action('updateYtdlpUnknown', RecommendedActionType.updateYtdlp),
      ],
    };
  }

  /// Compute patterns from incident list.
  List<ErrorPattern> _computePatterns(List<ErrorIncident> incidents) {
    // Group by (errorCode, platform)
    final groups = <String, List<ErrorIncident>>{};
    for (final i in incidents) {
      final key = '${i.errorCode.name}:${i.platform}';
      (groups[key] ??= []).add(i);
    }

    // Also group by errorCode alone (cross-platform patterns)
    final codeGroups = <String, List<ErrorIncident>>{};
    for (final i in incidents) {
      (codeGroups[i.errorCode.name] ??= []).add(i);
    }

    final patterns = <ErrorPattern>[];

    // Per-platform patterns
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length < 2) continue;
      final first = list.first;
      patterns.add(
        ErrorPattern(
          errorCode: first.errorCode,
          platform: first.platform,
          occurrences: list.length,
          firstSeen: list.first.timestamp,
          lastSeen: list.last.timestamp,
          autoHealedCount: list.where((i) => i.wasAutoHealed).length,
        ),
      );
    }

    // Cross-platform patterns (only if multiple platforms affected)
    for (final entry in codeGroups.entries) {
      final list = entry.value;
      final platforms = list.map((i) => i.platform).toSet();
      if (platforms.length < 2 || list.length < 3) continue;
      patterns.add(
        ErrorPattern(
          errorCode: list.first.errorCode,
          platform: null, // cross-platform
          occurrences: list.length,
          firstSeen: list.first.timestamp,
          lastSeen: list.last.timestamp,
          autoHealedCount: list.where((i) => i.wasAutoHealed).length,
        ),
      );
    }

    // Sort by recency then count
    patterns.sort((a, b) {
      final hot = b.isHot ? 1 : 0;
      final hotA = a.isHot ? 1 : 0;
      if (hot != hotA) return hot - hotA;
      return b.occurrences.compareTo(a.occurrences);
    });

    return patterns;
  }

  /// Clear all incident history.
  Future<void> clearAll() async {
    state = const ErrorDiagnosticsState();
    await _prefs.remove(_storageKey);
  }
}

/// Provider for error diagnostics.
final errorDiagnosticsProvider =
    StateNotifierProvider<ErrorDiagnosticsNotifier, ErrorDiagnosticsState>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ErrorDiagnosticsNotifier(prefs);
    });
