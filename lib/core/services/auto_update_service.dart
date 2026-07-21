import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../logging/app_logger.dart';
import '../network/shared_http_client.dart';
import '../providers/backend_providers.dart';
import '../providers/database_provider.dart';
import 'error_reporter_service.dart';

/// Update download & install status
enum UpdateStatus {
  idle,
  downloading,
  verifying,
  readyToInstall,
  installing,
  failed,
}

/// Tracks the state of an in-progress or completed update
class UpdateState {
  final UpdateStatus status;
  final double progress;
  final String? version;
  final String? error;
  final String? installerPath;
  final int totalBytes;
  final int receivedBytes;
  final String source;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.progress = 0,
    this.version,
    this.error,
    this.installerPath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.source = 'unknown',
  });

  UpdateState copyWith({
    UpdateStatus? status,
    double? progress,
    String? version,
    String? error,
    String? installerPath,
    int? totalBytes,
    int? receivedBytes,
    String? source,
  }) => UpdateState(
    status: status ?? this.status,
    progress: progress ?? this.progress,
    version: version ?? this.version,
    error: error ?? this.error,
    installerPath: installerPath ?? this.installerPath,
    totalBytes: totalBytes ?? this.totalBytes,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    source: source ?? this.source,
  );

  bool get isIdle => status == UpdateStatus.idle;
  bool get isDownloading => status == UpdateStatus.downloading;
  bool get isReady => status == UpdateStatus.readyToInstall;
  bool get isFailed => status == UpdateStatus.failed;
  bool get isInstalling => status == UpdateStatus.installing;
}

/// Handles downloading, verifying, and installing app updates.
///
/// Platform-specific install strategies:
/// - macOS: Mount DMG → copy .app → unmount → relaunch via helper script
/// - Windows: Run InnoSetup installer with /VERYSILENT flags
/// - Linux: Replace AppImage binary via helper script
/// Telemetry callback fired ONCE per actually-started download attempt.
///
/// Multiple call sites (startup_service mandatory branch, global mandatory
/// gate, banner mandatory auto-trigger, dialog mandatory auto-trigger) can each invoke
/// [AutoUpdateNotifier.downloadUpdate] within the same event-loop turn.
/// Before round 6 review, each site emitted its own telemetry event
/// BEFORE calling downloadUpdate — so 3 callers produced 3 events even
/// though only 1 caller actually won the `_downloadInFlight` race and
/// performed the network fetch. Funnel maths broke.
///
/// The fix routes every telemetry emit through this single callback,
/// invoked from inside [AutoUpdateNotifier.downloadUpdate] AFTER the
/// guard has been claimed. By construction it fires at most once per
/// real download attempt.
typedef DownloadStartedTelemetry = void Function(String version, String source);
typedef UpdateLifecycleTelemetry =
    void Function(String eventName, Map<String, dynamic> properties);
typedef UpdateInstallHandoffStarted =
    Future<void> Function(String version, String source);

class UpdateInstallAckService {
  static const _pendingInstallKey = 'app_update_pending_install_v1';

  static Future<void> markHandoffStarted(
    SharedPreferences prefs, {
    required String targetVersion,
    required String currentVersion,
    required String source,
    DateTime? now,
  }) async {
    if (targetVersion.trim().isEmpty) return;
    await prefs.setString(
      _pendingInstallKey,
      jsonEncode({
        'target_version': targetVersion,
        'previous_version': currentVersion,
        'source': source,
        'started_at': (now ?? DateTime.now()).toIso8601String(),
      }),
    );
  }

  static Future<void> reconcileOnStartup(
    SharedPreferences prefs, {
    required String currentVersion,
    required void Function(String eventName, Map<String, dynamic> properties)
    track,
    required Future<bool> Function() flush,
  }) async {
    final raw = prefs.getString(_pendingInstallKey);
    if (raw == null || raw.isEmpty) return;

    String eventName;
    Map<String, dynamic> properties;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      eventName = 'update_install_not_applied';
      properties = {
        'current_version': currentVersion,
        'error_code': 'corrupt_pending_marker',
      };
      track(eventName, properties);
      if (await flush()) {
        await prefs.remove(_pendingInstallKey);
      }
      return;
    }

    final targetVersion = payload['target_version'] as String? ?? '';
    if (targetVersion.isEmpty) {
      track('update_install_not_applied', {
        'current_version': currentVersion,
        'error_code': 'missing_target_version',
      });
      if (await flush()) {
        await prefs.remove(_pendingInstallKey);
      }
      return;
    }

    final applied = _compareVersions(currentVersion, targetVersion) >= 0;
    eventName =
        applied ? 'update_install_completed' : 'update_install_not_applied';
    properties = {
      'target_version': targetVersion,
      'current_version': currentVersion,
      if (payload['previous_version'] is String)
        'previous_version': payload['previous_version'],
      if (payload['source'] is String) 'source': payload['source'],
      if (payload['started_at'] is String) 'started_at': payload['started_at'],
    };
    track(eventName, properties);
    if (await flush()) {
      await prefs.remove(_pendingInstallKey);
    }
  }

  static int _compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    final maxLen =
        aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < maxLen; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _parseVersion(String version) {
    return version
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}

class AutoUpdateNotifier extends StateNotifier<UpdateState> {
  AutoUpdateNotifier({
    this.onBeforeExit,
    http.Client? httpClient,
    Future<Directory> Function()? tempDirectoryProvider,
    ErrorReporterService? errorReporter,
    DownloadStartedTelemetry? onDownloadStarted,
    UpdateLifecycleTelemetry? onLifecycleEvent,
    UpdateInstallHandoffStarted? onInstallHandoffStarted,
    Duration streamIdleTimeout = const Duration(seconds: 45),
  }) : _httpClient = httpClient ?? SharedHttpClient.instance,
       _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory,
       _errorReporter = errorReporter,
       _onDownloadStarted = onDownloadStarted,
       _onLifecycleEvent = onLifecycleEvent,
       _onInstallHandoffStarted = onInstallHandoffStarted,
       _streamIdleTimeout = streamIdleTimeout,
       super(const UpdateState());

  final DownloadStartedTelemetry? _onDownloadStarted;
  final UpdateLifecycleTelemetry? _onLifecycleEvent;
  final UpdateInstallHandoffStarted? _onInstallHandoffStarted;

  /// Called before [exit(0)] to flush databases and release file handles.
  /// Without this, SQLite WAL files are left dirty — cloud-sync services
  /// (Dropbox, OneDrive) can then overwrite the main DB with a stale copy,
  /// causing data loss on next launch.
  final Future<void> Function()? onBeforeExit;

  /// Injected HTTP client — defaults to [SharedHttpClient.instance] in
  /// production so TLS sockets stay warm across binary + update flows.
  /// Tests inject a `MockClient` to deterministically stub responses.
  final http.Client _httpClient;

  /// Indirection for the temp directory so tests can point the download
  /// at an isolated `Directory.systemTemp.createTemp(...)` instead of
  /// the real user temp.
  final Future<Directory> Function() _tempDirectoryProvider;

  /// Max time allowed between body chunks once the server has returned
  /// headers. Without this, a CDN/proxy can return HTTP 200 and then stall
  /// forever while the UI stays in "downloading".
  final Duration _streamIdleTimeout;

  /// Synchronous re-entry guard. The original `state.isDownloading`
  /// check is not enough because the first state mutation only happens
  /// AFTER `await _tempDirectoryProvider()` (round-5 review). Multiple
  /// mandatory surfaces can fire within the same event
  /// loop turn before any of them reach the state assignment, double-
  /// firing telemetry and starting two parallel downloads writing the
  /// same target file. This bool flips before the first await and
  /// closes the window.
  bool _downloadInFlight = false;

  /// Optional Sentry breadcrumb sink. Null in tests / no-DSN builds.
  /// All call sites must use [safeBreadcrumb] so a broken reporter cannot
  /// derail the update flow.
  final ErrorReporterService? _errorReporter;

  /// Download update from [downloadUrl], verify SHA-256, and prepare for install.
  ///
  /// Hardened for real-world networks:
  /// - Streaming SHA-256 — no whole-file allocation, safe for 100MB+ installers.
  /// - HTTP Range resume — an interrupted download continues from the last byte
  ///   on disk instead of restarting from zero (critical for slow connections,
  ///   e.g. VidCombo users on Vietnamese mobile networks).
  /// - Case-insensitive hex compare — some servers emit uppercase digests.
  Future<void> downloadUpdate(
    String downloadUrl,
    String expectedSha256,
    String version, {
    String source = 'unknown',
  }) async {
    // Two layers: state-based check (covers the steady-state UpdateState
    // lifecycle) AND a synchronous bool flag (covers the await-window
    // race documented next to `_downloadInFlight`). The flag is the
    // authoritative guard for concurrent entry; the state check stays
    // for compatibility with code paths that observe the StateNotifier.
    if (_downloadInFlight || state.isDownloading || state.isInstalling) {
      return;
    }
    _downloadInFlight = true;

    // Telemetry single-source-of-truth: fire ONCE per real download
    // attempt, AFTER winning the guard. Callers must not emit their
    // own update_install_* event before this point — otherwise three
    // mandatory-flow call sites (startup, banner, dialog) double- and
    // triple-count the same actual download. Round 6 review caught
    // exactly this overcount.
    try {
      _onDownloadStarted?.call(version, source);
    } catch (_) {
      /* telemetry is non-critical */
    }

    try {
      final ext =
          Platform.isMacOS
              ? '.dmg'
              : Platform.isWindows
              ? '.exe'
              : '.AppImage';

      final tempDir = await _tempDirectoryProvider();
      final filePath =
          '${tempDir.path}/${BrandConfig.current.brand.name}_update_$version$ext';
      final file = File(filePath);

      // Inspect any existing artifact — it may be a complete prior download
      // we can short-circuit, or a partial we can resume.
      var resumeFrom = 0;
      if (await file.exists()) {
        resumeFrom = await file.length();
        if (expectedSha256.isNotEmpty && resumeFrom > 0) {
          final existingHash = await _computeSha256File(file);
          if (_hashEquals(existingHash, expectedSha256)) {
            state = UpdateState(
              status: UpdateStatus.readyToInstall,
              version: version,
              progress: 1.0,
              installerPath: filePath,
              totalBytes: resumeFrom,
              receivedBytes: resumeFrom,
              source: source,
            );
            appLogger.info('Update already downloaded and verified: $filePath');
            _emitLifecycleEvent(
              'update_download_verified',
              version: version,
              source: source,
              properties: {'already_present': true, 'bytes': resumeFrom},
            );
            return;
          }
          // Either partial or tampered — Range-resume reconciles byte count,
          // and the final hash check rejects any actual tampering.
        }
      }

      state = UpdateState(
        status: UpdateStatus.downloading,
        version: version,
        receivedBytes: resumeFrom,
        source: source,
      );

      // Stream download with progress using the pooled shared client so
      // the TLS handshake cost is paid once per process, not per update
      // check. `close()` on the shared singleton is a no-op — any
      // accidental dispose from this scope cannot break the binary or
      // version services that share the pool.
      final client = _httpClient;
      try {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        if (resumeFrom > 0) {
          request.headers['Range'] = 'bytes=$resumeFrom-';
        }
        // Bound the initial-response phase. A server that accepts the
        // TCP connection but never emits headers would otherwise hang the
        // update pipeline indefinitely; the OS-level TCP timeout is
        // typically several minutes with no user-visible signal. Once
        // the stream is flowing, chunk-level progress events give the
        // user the ability to cancel via UI.
        final response = await client
            .send(request)
            .timeout(
              const Duration(seconds: 30),
              onTimeout:
                  () =>
                      throw TimeoutException(
                        'Update server did not respond within 30 seconds.',
                      ),
            );

        final isPartial = response.statusCode == 206;
        final isFull = response.statusCode == 200;
        if (!isPartial && !isFull) {
          state = state.copyWith(
            status: UpdateStatus.failed,
            error: 'Download failed: HTTP ${response.statusCode}',
          );
          _emitLifecycleEvent(
            'update_download_failed',
            version: version,
            source: source,
            properties: {
              'error_code': 'http_${response.statusCode}',
              'http_status': response.statusCode,
            },
          );
          return;
        }

        if (isPartial && resumeFrom > 0) {
          safeBreadcrumb(
            _errorReporter,
            'auto_update_resume',
            data: {'resume_bytes': resumeFrom, 'version': version},
          );
        }

        // Server ignored our Range header — it sent the whole file. Start
        // fresh; we cannot splice the existing bytes with a full-file body.
        if (isFull && resumeFrom > 0) {
          appLogger.info(
            'Server did not honour Range header — restarting from byte 0',
          );
          resumeFrom = 0;
        }

        // For a 206 response, Content-Length is the REMAINING bytes; add
        // what is already on disk for the true total.
        final responseLen = response.contentLength ?? 0;
        final totalBytes = isPartial ? resumeFrom + responseLen : responseLen;
        var receivedBytes = resumeFrom;
        final sink = file.openWrite(
          mode: resumeFrom > 0 ? FileMode.writeOnlyAppend : FileMode.write,
        );

        try {
          final guardedStream = response.stream.timeout(
            _streamIdleTimeout,
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'Update download stalled for ${_streamIdleTimeout.inSeconds} seconds.',
                ),
              );
            },
          );

          await for (final chunk in guardedStream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            state = state.copyWith(
              progress: totalBytes > 0 ? receivedBytes / totalBytes : 0,
              totalBytes: totalBytes,
              receivedBytes: receivedBytes,
            );
          }
        } finally {
          await sink.close();
        }
      } finally {
        // `client.close()` intentionally omitted — the client is the
        // process-lifetime [SharedHttpClient.instance] and its close()
        // is a no-op anyway, but calling it here would be misleading.
      }

      // Verify SHA-256 — streaming read, no whole-file allocation.
      state = state.copyWith(status: UpdateStatus.verifying);
      // Integrity invariant (single chokepoint for ALL callers — startup,
      // dialog, banner): an update with no checksum is UNVERIFIABLE. Refuse to
      // install it rather than skip the hash check. The version.json fallback
      // carries no checksum; without this an empty hash fell straight through
      // to readyToInstall — an unverified install.
      if (expectedSha256.isEmpty) {
        await file.delete();
        appLogger.warning(
          'Refusing update $version from $source — no integrity checksum.',
        );
        state = state.copyWith(
          status: UpdateStatus.failed,
          error: 'Update cannot be verified (missing checksum)',
        );
        _emitLifecycleEvent(
          'update_download_failed',
          version: version,
          source: source,
          properties: {'error_code': 'missing_checksum'},
        );
        return;
      }
      final hash = await _computeSha256File(file);
      if (!_hashEquals(hash, expectedSha256)) {
        final failedLen = await file.length();
        safeBreadcrumb(
          _errorReporter,
          'binary_sha256_mismatch',
          data: {
            'kind': 'app_update',
            'version': version,
            'bytes': failedLen,
          },
        );
        await file.delete();
        state = state.copyWith(
          status: UpdateStatus.failed,
          error: 'Integrity check failed — file hash does not match',
        );
        _emitLifecycleEvent(
          'update_download_failed',
          version: version,
          source: source,
          properties: {'error_code': 'sha256_mismatch', 'bytes': failedLen},
        );
        return;
      }

      final finalLen = await file.length();
      state = UpdateState(
        status: UpdateStatus.readyToInstall,
        version: version,
        progress: 1.0,
        installerPath: filePath,
        totalBytes: finalLen,
        receivedBytes: finalLen,
        source: source,
      );

      appLogger.info('Update downloaded and verified: $filePath');
      _emitLifecycleEvent(
        'update_download_verified',
        version: version,
        source: source,
        properties: {'already_present': false, 'bytes': finalLen},
      );
    } catch (e, stackTrace) {
      appLogger.error('Update download failed', e, stackTrace);
      state = state.copyWith(status: UpdateStatus.failed, error: e.toString());
      _emitLifecycleEvent(
        'update_download_failed',
        version: version,
        source: source,
        properties: {'error_code': 'exception', 'error': e.toString()},
      );
    } finally {
      // Release the synchronous re-entry guard regardless of which
      // branch terminated the download (success / readyToInstall short
      // circuit / exception). Without this, a single failed download
      // would permanently lock the user out of every retry until
      // process restart.
      _downloadInFlight = false;
    }
  }

  /// Streaming SHA-256 over the whole file. Keeps memory usage O(chunk size)
  /// regardless of installer size — earlier `readAsBytes()` allocated the
  /// entire file twice (once in Dart, once in the hash converter).
  static Future<String> _computeSha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Hex-compare hashes case-insensitively — some distribution backends
  /// emit uppercase digests, which would otherwise cause a false mismatch.
  static bool _hashEquals(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  /// Install the downloaded update and restart the app.
  /// Platform-specific: macOS (DMG), Windows (InnoSetup), Linux (AppImage).
  Future<void> installAndRestart() async {
    if (kDebugMode) {
      appLogger.warning('Auto-update disabled in debug mode');
      state = state.copyWith(
        status: UpdateStatus.failed,
        error: 'Auto-update disabled in debug mode',
      );
      return;
    }

    final path = state.installerPath;
    if (path == null || !state.isReady) return;

    state = state.copyWith(status: UpdateStatus.installing);
    _emitLifecycleEvent(
      'update_install_started',
      version: state.version,
      source: state.source,
    );

    try {
      if (Platform.isMacOS) {
        await _installMacOS(path);
      } else if (Platform.isWindows) {
        await _installWindows(path);
      } else if (Platform.isLinux) {
        await _installLinux(path);
      }
    } catch (e, stackTrace) {
      appLogger.error('Update install failed', e, stackTrace);
      state = state.copyWith(
        status: UpdateStatus.failed,
        error: 'Install failed: $e',
      );
      _emitLifecycleEvent(
        'update_install_failed',
        version: state.version,
        source: state.source,
        properties: {'error_code': 'exception', 'error': e.toString()},
      );
    }
  }

  Future<void> _recordInstallHandoffStarted() async {
    final version = state.version;
    if (version != null && version.isNotEmpty) {
      try {
        await _onInstallHandoffStarted?.call(version, state.source);
      } catch (_) {
        /* marker is best-effort */
      }
    }
    _emitLifecycleEvent(
      'update_install_handoff_started',
      version: version,
      source: state.source,
    );
  }

  void _emitLifecycleEvent(
    String eventName, {
    String? version,
    String source = 'unknown',
    Map<String, dynamic>? properties,
  }) {
    try {
      _onLifecycleEvent?.call(eventName, {
        if (version != null) 'version': version,
        'source': source,
        'platform': Platform.operatingSystem,
        if (properties != null) ...properties,
      });
    } catch (_) {
      /* telemetry is non-critical */
    }
  }

  /// Flush databases and release file handles, then terminate.
  ///
  /// Plain [exit(0)] is a C-level `_exit` — no finalizers, no stream flushes,
  /// no file-descriptor cleanup. SQLite WAL/SHM files are left dirty on disk.
  /// If the Documents folder is backed by a cloud-sync service (Dropbox,
  /// OneDrive, Google Drive), the service may sync the stale main DB file
  /// while discarding the uncommitted WAL, effectively rolling back every
  /// write since the last checkpoint. Result: the user's download history
  /// vanishes on next launch.
  ///
  /// Calling [onBeforeExit] gives Drift's [AppDatabase.close()] a chance to
  /// checkpoint the WAL into the main file and delete the WAL/SHM pair,
  /// leaving a single self-contained `.db` file that syncs cleanly.
  Future<Never> _cleanupAndExit() async {
    try {
      await onBeforeExit?.call();
    } catch (e) {
      appLogger.warning('Pre-exit cleanup error (proceeding with exit): $e');
    }
    exit(0);
  }

  /// macOS: Mount DMG → copy .app to staging → unmount → replace via script → relaunch
  Future<void> _installMacOS(String dmgPath) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final mountPoint =
        '/tmp/${BrandConfig.current.brand.name}_update_mount_$ts';

    // 1. Mount DMG (nobrowse = don't show in Finder)
    final mountResult = await Process.run('hdiutil', [
      'attach',
      dmgPath,
      '-nobrowse',
      '-noautoopen',
      '-mountpoint',
      mountPoint,
    ]);

    if (mountResult.exitCode != 0) {
      throw Exception('Failed to mount DMG: ${mountResult.stderr}');
    }

    // 2. Find .app inside mounted DMG
    final mountDir = Directory(mountPoint);
    final appDirs =
        mountDir
            .listSync()
            .where((e) => e is Directory && e.path.endsWith('.app'))
            .toList();

    if (appDirs.isEmpty) {
      await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
      throw Exception('No .app bundle found in DMG');
    }

    final sourceApp = appDirs.first.path;

    // 3. Get current app bundle path
    // Platform.resolvedExecutable → .../Svid.app/Contents/MacOS/svid
    final currentExe = Platform.resolvedExecutable;
    final contentsIdx = currentExe.indexOf('/Contents/');
    if (contentsIdx == -1) {
      await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
      throw Exception('Cannot determine app bundle path');
    }
    final currentApp = currentExe.substring(0, contentsIdx);

    // 4. Create update script that runs after app exits
    final stagingDir = '/tmp/${BrandConfig.current.brand.name}_staging_$ts';
    final appName = sourceApp.split('/').last; // e.g., "{Brand}.app"
    final script = '''#!/bin/bash
# ${BrandConfig.current.appName} Auto-Update Script — macOS
# Waits for app to exit, replaces bundle, relaunches

PID=\$1
MOUNT="\$2"
SOURCE="\$3"
STAGING="\$4"
DEST="\$5"
APP_NAME="\$6"
DMG="\$7"

# 1. Copy from mount to staging (while mount is still available)
mkdir -p "\$STAGING"
cp -R "\$SOURCE" "\$STAGING/\$APP_NAME"
COPY_EXIT=\$?

# 2. Unmount DMG immediately (we have the copy)
hdiutil detach "\$MOUNT" -quiet 2>/dev/null
rm -f "\$DMG"

if [ \$COPY_EXIT -ne 0 ]; then
  echo "Failed to copy app from DMG"
  rm -rf "\$STAGING"
  exit 1
fi

# 3. Wait for app to exit (max 30 seconds)
WAITED=0
while kill -0 \$PID 2>/dev/null; do
  sleep 0.5
  WAITED=\$((WAITED + 1))
  if [ \$WAITED -gt 60 ]; then
    echo "Timeout waiting for app to exit"
    rm -rf "\$STAGING"
    exit 1
  fi
done

# 4. Replace app bundle
rm -rf "\$DEST"
mv "\$STAGING/\$APP_NAME" "\$DEST"
MV_EXIT=\$?

if [ \$MV_EXIT -ne 0 ]; then
  # Try with admin privileges (app in /Applications owned by root)
  osascript -e "do shell script \\"rm -rf '\$DEST' && mv '\$STAGING/\$APP_NAME' '\$DEST'\\" with administrator privileges" 2>/dev/null
  MV_EXIT=\$?
fi

rm -rf "\$STAGING"

if [ \$MV_EXIT -eq 0 ]; then
  # 5. Strip quarantine xattr — prevents Gatekeeper re-prompt after update
  xattr -cr "\$DEST" 2>/dev/null

  # 6. Launch updated app
  open "\$DEST"
fi

# Self-delete
rm -f "\$0"
''';

    final scriptPath = '/tmp/${BrandConfig.current.brand.name}_update_$ts.sh';
    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // 5. Launch update script detached
    final currentPid = pid;
    await Process.start(scriptPath, [
      '$currentPid',
      mountPoint,
      sourceApp,
      stagingDir,
      currentApp,
      appName,
      dmgPath,
    ], mode: ProcessStartMode.detached);

    appLogger.info('macOS update script launched, exiting app...');
    await _recordInstallHandoffStarted();

    // 6. Flush database, then exit — script takes over
    await _cleanupAndExit();
  }

  /// Windows: Run InnoSetup installer with silent flags.
  ///
  /// Strategy: DON'T exit the app — let the installer close us via
  /// Restart Manager (/CLOSEAPPLICATIONS). This way the installer can
  /// properly replace files and the [Run] section relaunches the new version.
  ///
  /// If we call exit(0) before the installer tracks our process, Restart
  /// Manager has nothing to close/restart and the update silently fails.
  Future<void> _installWindows(String installerPath) async {
    // Remove Zone.Identifier ADS to prevent SmartScreen/Smart App Control
    // blocking the installer. Downloaded files carry a Zone.3 mark ("internet
    // origin") that triggers Windows security prompts or outright blocks.
    // Binary downloads already do this — the app installer was missing it.
    try {
      await Process.run('cmd', [
        '/c',
        'del',
        '/f',
        '$installerPath:Zone.Identifier',
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Non-fatal: ADS may not exist or cmd may fail
    }

    await Process.start(installerPath, [
      '/VERYSILENT',
      '/SP-',
      '/SUPPRESSMSGBOXES',
      '/CLOSEAPPLICATIONS',
    ], mode: ProcessStartMode.detached);

    appLogger.info(
      'Windows installer launched — waiting for installer to close app...',
    );
    await _recordInstallHandoffStarted();

    // Don't exit — let the installer close us via Restart Manager.
    // The [Run] section (without skipifsilent) will relaunch the new version.
    // Timeout fallback: if installer hasn't closed us in 60s, exit manually.
    await Future.delayed(const Duration(seconds: 60));

    // Fallback: installer didn't close us (maybe failed). Exit so files unlock.
    appLogger.warning(
      'Installer did not close app within 60s — exiting as fallback',
    );
    await _cleanupAndExit();
  }

  /// Linux: Create update script → replace AppImage/binary → relaunch
  Future<void> _installLinux(String newBinaryPath) async {
    // For AppImage: $APPIMAGE env var has the real path
    // For regular binary: Platform.resolvedExecutable
    final currentPath =
        Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final script = '''#!/bin/bash
# ${BrandConfig.current.appName} Auto-Update Script — Linux

PID=\$1
NEW="\$2"
CURRENT="\$3"

# Wait for app to exit (max 30 seconds)
WAITED=0
while kill -0 \$PID 2>/dev/null; do
  sleep 0.5
  WAITED=\$((WAITED + 1))
  if [ \$WAITED -gt 60 ]; then
    echo "Timeout waiting for app to exit"
    exit 1
  fi
done

# Replace binary (atomic: cp to temp, then mv on same filesystem)
cp "\$NEW" "\${CURRENT}.new"
mv "\${CURRENT}.new" "\$CURRENT"
chmod +x "\$CURRENT"

# Clean up downloaded file
rm -f "\$NEW"

# Launch new version
"\$CURRENT" &

# Self-delete
rm -f "\$0"
''';

    final scriptPath = '/tmp/${BrandConfig.current.brand.name}_update_$ts.sh';
    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    final currentPid = pid;
    await Process.start(scriptPath, [
      '$currentPid',
      newBinaryPath,
      currentPath,
    ], mode: ProcessStartMode.detached);

    appLogger.info('Linux update script launched, exiting app...');
    await _recordInstallHandoffStarted();
    await _cleanupAndExit();
  }

  void reset() {
    state = const UpdateState();
  }
}

final autoUpdateProvider =
    StateNotifierProvider<AutoUpdateNotifier, UpdateState>((ref) {
      return AutoUpdateNotifier(
        onBeforeExit: () async {
          try {
            await ref.read(analyticsServiceProvider).flush();
          } catch (_) {
            // Best-effort — update handoff telemetry must never block exit.
          }
          try {
            final db = ref.read(databaseProvider);
            await db.close();
          } catch (_) {
            // Best-effort — if DB is already closed or provider is disposed,
            // proceed with exit anyway.
          }
        },
        errorReporter: ref.read(errorReporterServiceProvider),
        // Single source of truth for download-start telemetry. Maps the
        // caller-provided `source` string onto the correct funnel event so
        // mandatory-auto-flow vs explicit-click can still be distinguished
        // downstream. Read by analytics service (no UI dependency).
        onDownloadStarted: (version, source) {
          try {
            final eventName = switch (source) {
              'banner_click' => 'update_install_clicked',
              'dialog_click' => 'update_install_dialog_clicked',
              // Every mandatory auto path (startup, banner mandatory, dialog
              // mandatory) maps to one event — single counter, no overcount.
              'mandatory_auto' ||
              'startup_mandatory' => 'update_install_auto_started',
              _ => 'update_install_started',
            };
            ref.read(analyticsServiceProvider).track(eventName, {
              'version': version,
              'source': source,
            });
          } catch (_) {
            /* non-critical */
          }
        },
        onLifecycleEvent: (eventName, properties) {
          try {
            ref.read(analyticsServiceProvider).track(eventName, properties);
          } catch (_) {
            /* non-critical */
          }
        },
        onInstallHandoffStarted: (version, source) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            await UpdateInstallAckService.markHandoffStarted(
              prefs,
              targetVersion: version,
              currentVersion: AppConstants.appVersion,
              source: source,
            );
          } catch (_) {
            /* non-critical */
          }
        },
      );
    });

/// Format bytes to human-readable string (e.g., "45.2 MB")
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
