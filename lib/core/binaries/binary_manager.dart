import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'binary_downloader.dart';
import 'binary_info.dart';
import 'binary_type.dart';

/// Manages external binaries (yt-dlp, ffmpeg) lifecycle
/// - Checks if binaries exist
/// - Downloads on-demand
/// - Provides paths to binaries
/// - Handles updates
class BinaryManager {
  static BinaryManager? _instance;
  static final Map<BinaryType, String?> _cachedPaths = {};
  static final Map<BinaryType, String?> _cachedVersions = {};

  /// Init is gated on a Completer so concurrent callers all await the SAME
  /// in-flight initialization rather than racing past a half-populated
  /// `_cachedPaths`. Setting a plain `_initialized=true` before `Future.wait`
  /// completed let a second caller skip init and read empty caches.
  static Completer<void>? _initCompleter;
  static String? _pythonPath;

  final BinaryDownloader _downloader;
  String? _binDir;

  /// Python 3.10+ path detected on macOS (null if not available)
  static String? get pythonPath => _pythonPath;

  /// macOS CPU architecture: 'arm64' for Apple Silicon, 'amd64' for Intel
  static String get macOSArch {
    try {
      final result = Process.runSync('uname', ['-m']);
      final machine = result.stdout.toString().trim();
      return machine == 'arm64' ? 'arm64' : 'amd64';
    } catch (_) {
      return 'amd64';
    }
  }

  /// Whether gallery-dl is supported on this platform.
  /// gallery-dl_macos is ARM64-only (gdl-org/builds) — no x86_64 macOS binary exists.
  /// Intel Macs cannot run it (even with Rosetta 2 the PyInstaller binary fails).
  static bool get isGalleryDlSupported {
    if (!Platform.isMacOS) return true;
    return macOSArch == 'arm64';
  }

  /// Binary types that are required on this platform.
  /// Excludes gallery-dl on Intel Macs where no compatible binary exists.
  static List<BinaryType> get requiredBinaries {
    if (!isGalleryDlSupported) {
      return BinaryType.values.where((t) => t != BinaryType.galleryDl).toList();
    }
    return BinaryType.values;
  }

  BinaryManager._internal() : _downloader = BinaryDownloader();

  factory BinaryManager() {
    _instance ??= BinaryManager._internal();
    return _instance!;
  }

  /// Reset the singleton so each test starts from a clean state. Without
  /// this, tests share `_cachedPaths` / `_initCompleter` across runs and
  /// see flaky cross-test pollution. Production code must NEVER call
  /// this — the singleton is shared by design.
  @visibleForTesting
  static void resetForTest() {
    if (_instance != null) {
      _instance!._binDir = null;
    }
    _cachedPaths.clear();
    _repairFailureStreak.clear();
    telemetryListener = null;
    _initCompleter = null;
    _instance = null;
  }

  /// Initialize the binary manager (fast - only checks file existence)
  /// Version fetching is deferred until getVersion() is called.
  ///
  /// Concurrent callers share a single in-flight initialization — the
  /// completer only resolves AFTER existing-binary validation finishes, so
  /// no one sees an empty `_cachedPaths`.
  Future<void> initialize() async {
    final existing = _initCompleter;
    if (existing != null) {
      if (existing.isCompleted) {
        debugPrint('✅ [BinaryManager] Already initialized');
      }
      return existing.future;
    }
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      await _initializeInternal();
      completer.complete();
    } catch (e, st) {
      // Failed init must not become a sticky state — clear the gate so the
      // next caller can retry (e.g. after the user grants disk access).
      _initCompleter = null;
      completer.completeError(e, st);
      rethrow;
    }
  }

  Future<void> _initializeInternal() async {
    debugPrint('🔧 [BinaryManager] Initializing...');

    final appSupport = await getApplicationSupportDirectory();
    _binDir = path.join(appSupport.path, 'bin');

    // Ensure bin directory exists
    final binDir = Directory(_binDir!);
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }

    debugPrint('📁 [BinaryManager] Bin directory: $_binDir');

    // Windows: clean up leftover .download temp files from previous downloads.
    // These files are created during archive-based downloads and should be
    // deleted after extraction, but can survive if the app is killed mid-download
    // or if Windows Defender locks the file during deletion.
    if (Platform.isWindows) {
      try {
        final binDirEntries = Directory(_binDir!).listSync();
        for (final entry in binDirEntries) {
          if (entry is File && entry.path.endsWith('.download')) {
            try {
              final size = entry.lengthSync();
              entry.deleteSync();
              debugPrint(
                '🧹 [BinaryManager] Cleaned leftover temp file: '
                '${path.basename(entry.path)} (${(size / 1024 / 1024).toStringAsFixed(1)}MB)',
              );
            } catch (e) {
              debugPrint(
                '⚠️ [BinaryManager] Cannot delete temp file '
                '${path.basename(entry.path)}: $e',
              );
            }
          }
        }
      } catch (_) {}
    }

    // macOS: detect Python 3.10+ for fast yt-dlp zipapp execution (cached)
    if (Platform.isMacOS) {
      _pythonPath = await _detectPython310Cached();
      if (_pythonPath != null) {
        debugPrint('🐍 [BinaryManager] Python 3.10+ found: $_pythonPath');
      } else {
        debugPrint(
          '⚠️ [BinaryManager] Python 3.10+ not found, using PyInstaller binary',
        );
      }
    }

    // Check existing binaries in parallel (no subprocess calls — fast)
    await Future.wait(
      requiredBinaries.map((type) async {
        final binaryPath = path.join(_binDir!, type.filename);
        // DL-016 — adopt an orphaned .bak. `updateBinarySafely` renames
        // the live binary to .bak before downloading; a crash or failed
        // rollback (Windows File.rename onto an existing path fails)
        // strands the user with ONLY the .bak on disk — no binary until
        // a full manual re-download. Promote the backup at startup so
        // already-stricken field devices self-heal on next launch.
        if (!await File(binaryPath).exists()) {
          final bak = File('$binaryPath.bak');
          if (await bak.exists()) {
            try {
              await bak.rename(binaryPath);
              debugPrint(
                '♻️ [BinaryManager] Adopted orphaned ${type.filename}.bak '
                'as the live binary',
              );
              _emitTelemetry('binary_bak_adopted', {'binary': type.name});
            } catch (e) {
              debugPrint(
                '⚠️ [BinaryManager] Could not adopt ${type.filename}.bak: $e',
              );
            }
          }
        }
        if (await File(binaryPath).exists()) {
          if (await _validateBinary(type, binaryPath)) {
            _cachedPaths[type] = binaryPath;
          } else {
            // Do NOT delete — the file may have been truncated by antivirus
            // quarantine. Deleting makes recovery impossible. The download
            // flow will overwrite it with a fresh copy if needed.
            debugPrint(
              '⚠️ [BinaryManager] ${type.displayName} failed validation — will re-download',
            );
          }
        } else {
          debugPrint('❌ [BinaryManager] ${type.displayName} not found');
        }
      }),
    );

    // Pre-warm OS filesystem cache for yt-dlp binary.
    // The zipapp (1136 Python files) or PyInstaller bundle gets cached by the OS
    // after first read, reducing first extraction latency by ~1.3s.
    _preWarmYtdlp();
  }

  /// Fire-and-forget: run yt-dlp --version to warm OS filesystem cache.
  static void _preWarmYtdlp() {
    final ytdlpPath = _cachedPaths[BinaryType.ytDlp];
    if (ytdlpPath == null) return;

    unawaited(
      Process.run(ytdlpPath, ['--version'])
          .then((_) {
            debugPrint('🔥 [BinaryManager] yt-dlp filesystem cache pre-warmed');
          })
          .catchError((_) {
            // Non-critical — ignore errors
          }),
    );
  }

  /// Detect Python 3.10+ with SharedPreferences cache.
  /// Only re-detects if cached path no longer exists.
  static Future<String?> _detectPython310Cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_python_path');
      if (cached != null && await File(cached).exists()) {
        return cached;
      }
      final detected = await _detectPython310();
      if (detected != null) {
        await prefs.setString('cached_python_path', detected);
      } else {
        await prefs.remove('cached_python_path');
      }
      return detected;
    } catch (_) {
      return _detectPython310();
    }
  }

  /// Detect Python 3.10+ on macOS for fast yt-dlp zipapp execution.
  /// Checks common paths: Homebrew, python.org, system.
  static Future<String?> _detectPython310() async {
    const candidates = [
      '/opt/homebrew/bin/python3', // Homebrew Apple Silicon
      '/usr/local/bin/python3', // Homebrew Intel / python.org
      '/opt/homebrew/bin/python3.12',
      '/opt/homebrew/bin/python3.11',
      '/opt/homebrew/bin/python3.10',
      '/usr/local/bin/python3.12',
      '/usr/local/bin/python3.11',
      '/usr/local/bin/python3.10',
    ];

    for (final candidate in candidates) {
      if (!await File(candidate).exists()) continue;
      try {
        final result = await Process.run(candidate, ['--version']);
        if (result.exitCode == 0) {
          final version = result.stdout.toString().trim(); // "Python 3.x.y"
          final match = RegExp(r'Python\s+3\.(\d+)').firstMatch(version);
          if (match != null) {
            final minor = int.tryParse(match.group(1)!) ?? 0;
            if (minor >= 10) return candidate;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Get the bin directory path
  String get binDir => _binDir ?? '';

  /// Check if a binary is available
  Future<bool> isAvailable(BinaryType type) async {
    await _ensureInitialized();
    return _verifyCachedOnDisk(type);
  }

  /// Get the path to a binary (null if not available)
  Future<String?> getBinaryPath(BinaryType type) async {
    await _ensureInitialized();
    return await _verifyCachedOnDisk(type) ? _cachedPaths[type] : null;
  }

  /// DL-016 — cache-only availability was the root of the production
  /// missing-binary wave: a binary deleted AFTER init (AV retroactive
  /// quarantine, failed OTA rollback) left a stale path in
  /// `_cachedPaths`, so spawn sites crashed with ProcessException and
  /// `_runRepair`'s own health check skipped the repair as "already
  /// healthy". Verify the file is actually on disk; invalidate the
  /// cache when it vanished so repair/re-download can run.
  Future<bool> _verifyCachedOnDisk(BinaryType type) async {
    final cached = _cachedPaths[type];
    if (cached == null) return false;
    if (await File(cached).exists()) return true;
    _cachedPaths[type] = null;
    _cachedVersions[type] = null;
    debugPrint(
      '🚨 [BinaryManager] ${type.displayName} vanished from disk '
      '(was: $cached) — cache invalidated',
    );
    _emitTelemetry('binary_missing_detected', {'binary': type.name});
    return false;
  }

  /// DL-016 repair-outcome telemetry sink. Wired to the analytics
  /// pipeline by `binaryManagerProvider`; null in tests/headless. The
  /// server-side signal for the AV-quarantine hypothesis is the EVENT
  /// SEQUENCE per device: `repaired` followed by another
  /// `binary_missing_detected` = quarantine; `failed` = network/
  /// provisioning; one `repaired` then silence = transient.
  static void Function(String event, Map<String, String> props)?
  telemetryListener;

  static void _emitTelemetry(String event, Map<String, String> props) {
    try {
      telemetryListener?.call(event, props);
    } catch (_) {}
  }

  /// Get the version of a binary (null if not available)
  /// Lazily fetches version on first call
  Future<String?> getVersion(BinaryType type) async {
    await _ensureInitialized();

    // Return cached version if available
    if (_cachedVersions[type] != null) {
      return _cachedVersions[type];
    }

    // Lazily fetch version if binary exists but version not cached
    final binaryPath = _cachedPaths[type];
    if (binaryPath != null) {
      final version = await _getVersion(type, binaryPath);
      if (version != null) {
        _cachedVersions[type] = version;
        debugPrint('📦 [BinaryManager] ${type.displayName} version: $version');
      }
      return version;
    }

    return null;
  }

  /// Check which binaries are missing (only checks platform-required binaries)
  ///
  /// Optional binaries (gallery-dl) that the user previously skipped are
  /// excluded from the missing set for [_optionalSkipTtl] so the setup
  /// screen doesn't reappear on every cold start while upstream is broken.
  /// The skip mark is persisted in SharedPreferences keyed by binary type.
  Future<List<BinaryType>> getMissingBinaries() async {
    await _ensureInitialized();
    final missing = <BinaryType>[];
    for (final type in requiredBinaries) {
      // DL-016 (Codex review catch) — disk-verified like isAvailable/
      // getBinaryPath: a cache-only read here let the setup screen and
      // allBinariesAvailable() report a binary as healthy after AV
      // quarantine deleted the file post-init.
      if (await _verifyCachedOnDisk(type)) continue;

      // Optional binary: respect persisted skip if recent.
      final info = BinaryInfo.getLatest(type);
      if (info.optional) {
        final skippedAt = await _readOptionalSkipTimestamp(type);
        if (skippedAt != null &&
            DateTime.now().difference(skippedAt) < _optionalSkipTtl) {
          // User-acknowledged skip is still fresh — don't re-trigger setup.
          continue;
        }
      }

      missing.add(type);
    }
    return missing;
  }

  /// Time window during which a previously-skipped optional binary stays
  /// suppressed from the missing-list. After this elapses we retry once
  /// (upstream may have recovered) and re-skip if the chain still fails.
  /// 7 days balances "don't pester user" against "give upstream a chance
  /// to come back". Settings → Re-download lets the user retry sooner.
  static const Duration _optionalSkipTtl = Duration(days: 7);

  // Exposed to tests — the regression we're guarding against (setup
  // screen reappearing every launch on broken-upstream optional binary)
  // depends entirely on the persisted TTL window honouring the Skip
  // semantics, so the SharedPreferences key + TTL constant are part of
  // the contract.
  @visibleForTesting
  static Duration get optionalSkipTtlForTest => _optionalSkipTtl;

  @visibleForTesting
  static String optionalSkipKeyForTest(BinaryType type) =>
      _optionalSkipKey(type);

  static String _optionalSkipKey(BinaryType type) =>
      'binary_optional_skipped_${type.filename}';

  Future<DateTime?> _readOptionalSkipTimestamp(BinaryType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final iso = prefs.getString(_optionalSkipKey(type));
      if (iso == null || iso.isEmpty) return null;
      return DateTime.tryParse(iso);
    } catch (_) {
      return null;
    }
  }

  Future<void> _markOptionalSkipped(BinaryType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _optionalSkipKey(type),
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Persisting the skip is best-effort — if it fails the user just
      // sees the setup screen one more time, which is annoying but safe.
    }
  }

  /// Clear all persisted optional-skip marks. Call from Settings →
  /// "Re-download tools" so the user can force a retry without waiting
  /// for the [_optionalSkipTtl] window to elapse.
  Future<void> clearOptionalSkipMarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final type in BinaryType.values) {
        await prefs.remove(_optionalSkipKey(type));
      }
    } catch (_) {
      /* best-effort */
    }
  }

  /// Check if all required binaries are available
  Future<bool> allBinariesAvailable() async {
    final missing = await getMissingBinaries();
    return missing.isEmpty;
  }

  /// Download a specific binary with progress
  Stream<BinaryDownloadProgress> downloadBinary(BinaryType type) async* {
    await _ensureInitialized();

    debugPrint('📥 [BinaryManager] Downloading ${type.displayName}...');

    final info = BinaryInfo.getLatest(type);

    await for (final progress in _downloader.download(
      info: info,
      targetDir: _binDir!,
    )) {
      if (progress.status != BinaryDownloadStatus.completed) {
        yield progress;
        continue;
      }

      final binaryPath = path.join(_binDir!, type.filename);

      // Windows: post-download validation (remove ADS, verify execution)
      if (Platform.isWindows) {
        final winError = await _validateBinaryWindows(type, binaryPath);
        if (winError != null) {
          yield BinaryDownloadProgress.error(type, winError);
          return;
        }
      }

      // Publish the completed event only after the binary is executable and
      // cached. UI/history consumers often query getVersion() immediately
      // after `completed`; yielding too early records "unknown" versions.
      _cachedPaths[type] = binaryPath;

      final version = await _getVersion(type, binaryPath);
      _cachedVersions[type] = version;

      debugPrint(
        '✅ [BinaryManager] ${type.displayName} downloaded: $binaryPath',
      );
      if (version != null) {
        debugPrint('📦 [BinaryManager] Version: $version');
      }

      yield progress;
    }
  }

  /// Download all missing binaries with combined progress
  Stream<BinaryManagerProgress> downloadAllMissing() async* {
    final missing = await getMissingBinaries();

    final totalRequired = requiredBinaries.length;

    if (missing.isEmpty) {
      yield BinaryManagerProgress(
        currentBinary: null,
        currentProgress: null,
        completedCount: totalRequired,
        totalCount: totalRequired,
        status: BinaryManagerStatus.completed,
      );
      return;
    }

    var completedCount = totalRequired - missing.length;
    // Optional binaries (e.g. gallery-dl) whose mirror chain was exhausted.
    // Failures here are surfaced as warnings, not as a fatal first-launch
    // block — image download will be unavailable but video extraction
    // (yt-dlp + ffmpeg) keeps working. Without this fallback, an empty
    // upstream release (mikf/gallery-dl v1.32.0 published 2026-04-24 with
    // zero assets) bricks every Windows fresh install.
    final skippedOptional = <BinaryType>[];

    for (final type in missing) {
      final info = BinaryInfo.getLatest(type);

      yield BinaryManagerProgress(
        currentBinary: type,
        currentProgress: BinaryDownloadProgress.starting(type),
        completedCount: completedCount,
        totalCount: totalRequired,
        status: BinaryManagerStatus.downloading,
        skippedOptional: List.unmodifiable(skippedOptional),
      );

      await for (final progress in downloadBinary(type)) {
        final isErr = progress.status == BinaryDownloadStatus.error;

        // Optional-binary failure: hide the red-error UI state. The user
        // sees progress quietly skip to the next binary; the final
        // `completed` event carries the skipped list for any non-blocking
        // surface to render.
        final mappedStatus =
            isErr
                ? (info.optional
                    ? BinaryManagerStatus.downloading
                    : BinaryManagerStatus.error)
                : BinaryManagerStatus.downloading;

        yield BinaryManagerProgress(
          currentBinary: type,
          currentProgress: progress,
          completedCount: completedCount,
          totalCount: totalRequired,
          status: mappedStatus,
          error: (isErr && !info.optional) ? progress.error : null,
          skippedOptional: List.unmodifiable(skippedOptional),
        );

        if (progress.status == BinaryDownloadStatus.completed) {
          completedCount++;
        } else if (isErr) {
          if (info.optional) {
            skippedOptional.add(type);
            // Persist the skip so the setup screen doesn't re-trigger on
            // the next cold start (review feedback round 2: without
            // persistence, gallery-dl 404 keeps showing the setup wall
            // every launch even though the user already accepted the
            // degradation). TTL is 7 days — see _optionalSkipTtl.
            unawaited(_markOptionalSkipped(type));
            debugPrint(
              '⚠️ [BinaryManager] Optional binary ${type.displayName} '
              'failed (${progress.error}); continuing without it. '
              'Suppressed from setup for ${_optionalSkipTtl.inDays} days.',
            );
            break; // exit inner stream, continue outer loop
          }
          return; // required binary failed → halt first launch
        }
      }
    }

    yield BinaryManagerProgress(
      currentBinary: null,
      currentProgress: null,
      completedCount: completedCount,
      // Reduce denominator by skipped optional so progress reads as 100%
      // when the user-facing baseline (yt-dlp + ffmpeg) is ready.
      totalCount: totalRequired - skippedOptional.length,
      status: BinaryManagerStatus.completed,
      skippedOptional: List.unmodifiable(skippedOptional),
    );
  }

  /// Delete a binary
  Future<void> deleteBinary(BinaryType type) async {
    await _ensureInitialized();

    final binaryPath = _cachedPaths[type];
    if (binaryPath != null) {
      final file = File(binaryPath);
      if (await file.exists()) {
        await file.delete();
      }
      _cachedPaths[type] = null;
      _cachedVersions[type] = null;
      debugPrint('🗑️ [BinaryManager] Deleted ${type.displayName}');
    }
  }

  /// Force re-download a binary (for updates)
  Stream<BinaryDownloadProgress> updateBinary(BinaryType type) async* {
    await deleteBinary(type);
    yield* downloadBinary(type);
  }

  /// In-flight repair futures keyed by binary type. Multiple callers
  /// (e.g. several extractions failing simultaneously when Deno is
  /// missing) collapse to a single download — without this lock, a
  /// fan-out of N failures would race N parallel re-downloads,
  /// wasting bandwidth and racing on the temp file.
  static final Map<BinaryType, Future<bool>> _repairInFlight = {};

  /// DL-016 — consecutive failed-repair counter per binary. When AV
  /// keeps re-quarantining the binary (or the network is down), an
  /// uncapped repair would loop download→delete→download forever.
  /// After [_maxRepairAttempts] consecutive failures the repair
  /// short-circuits to `false` so callers surface the terminal
  /// "antivirus may have removed a component" guidance instead.
  /// Reset on any success or when the binary is found healthy.
  static final Map<BinaryType, int> _repairFailureStreak = {};
  static const int _maxRepairAttempts = 3;

  @visibleForTesting
  static int repairFailureStreakForTest(BinaryType type) =>
      _repairFailureStreak[type] ?? 0;

  @visibleForTesting
  static void setRepairFailureStreakForTest(BinaryType type, int value) {
    _repairFailureStreak[type] = value;
  }

  /// Background re-download for [type], typically called when a
  /// downstream consumer detects the binary is missing or unhealthy
  /// (e.g. yt-dlp emits "Signature solving failed" because Deno is
  /// absent). Idempotent — concurrent callers share a single Future.
  ///
  /// Returns `true` once the binary is healthy (either it already was,
  /// or the repair download completed). Returns `false` if the repair
  /// failed (network down, integrity mismatch, etc.); callers should
  /// surface a user-actionable error rather than auto-retrying.
  ///
  /// Safe to call as fire-and-forget:
  /// `unawaited(BinaryManager().triggerRepair(BinaryType.deno));`
  Future<bool> triggerRepair(BinaryType type) {
    final existing = _repairInFlight[type];
    if (existing != null) return existing;
    final future = _runRepair(type);
    _repairInFlight[type] = future;
    future.whenComplete(() => _repairInFlight.remove(type));
    return future;
  }

  Future<bool> _runRepair(BinaryType type) async {
    await _ensureInitialized();

    if (await isAvailable(type)) {
      debugPrint(
        '🔧 [BinaryManager] ${type.displayName} already healthy — '
        'repair skipped',
      );
      _repairFailureStreak[type] = 0;
      _emitTelemetry('binary_repair_outcome', {
        'binary': type.name,
        'outcome': 'already_healthy',
      });
      return true;
    }

    // DL-016 — capped attempts: see [_repairFailureStreak].
    final streak = _repairFailureStreak[type] ?? 0;
    if (streak >= _maxRepairAttempts) {
      debugPrint(
        '🛑 [BinaryManager] Repair for ${type.displayName} exhausted '
        '($streak consecutive failures) — surfacing terminal guidance',
      );
      _emitTelemetry('binary_repair_outcome', {
        'binary': type.name,
        'outcome': 'exhausted',
        'streak': '$streak',
      });
      return false;
    }

    debugPrint(
      '🔧 [BinaryManager] Repairing ${type.displayName} in background...',
    );

    var failureReason = 'download_error';
    try {
      await for (final progress in downloadBinary(type)) {
        if (progress.status == BinaryDownloadStatus.error) {
          debugPrint(
            '❌ [BinaryManager] Repair failed for ${type.displayName}: '
            '${progress.error}',
          );
          break;
        }
        if (progress.status == BinaryDownloadStatus.completed) {
          // Codex review follow-up — verify the repaired file actually
          // SURVIVED on disk: an AV that re-quarantines instantly would
          // otherwise produce a false `repaired` outcome and poison the
          // quarantine-vs-transient telemetry instrument.
          if (await _verifyCachedOnDisk(type)) {
            debugPrint(
              '✅ [BinaryManager] Repair completed for ${type.displayName}',
            );
            _repairFailureStreak[type] = 0;
            _emitTelemetry('binary_repair_outcome', {
              'binary': type.name,
              'outcome': 'repaired',
            });
            return true;
          }
          debugPrint(
            '🚨 [BinaryManager] Repair downloaded ${type.displayName} but '
            'the file vanished immediately — likely AV quarantine',
          );
          failureReason = 'vanished_after_download';
          break;
        }
      }
    } catch (e) {
      debugPrint(
        '❌ [BinaryManager] Repair crashed for ${type.displayName}: $e',
      );
      failureReason = 'crashed';
    }
    _repairFailureStreak[type] = streak + 1;
    _emitTelemetry('binary_repair_outcome', {
      'binary': type.name,
      'outcome': 'failed',
      'reason': failureReason,
      'streak': '${streak + 1}',
    });
    return false;
  }

  /// Safely update a binary with backup/rollback.
  /// 1. Rename existing binary to .bak
  /// 2. Download new binary
  /// 3. On success: delete .bak
  /// 4. On failure: restore .bak → original name
  Stream<BinaryDownloadProgress> updateBinarySafely(BinaryType type) async* {
    await _ensureInitialized();

    final binaryPath = _cachedPaths[type];
    final backupPath = binaryPath != null ? '$binaryPath.bak' : null;
    var downloadSucceeded = false;
    String? downloadError;

    // Step 1: Backup existing binary
    if (binaryPath != null) {
      final existingFile = File(binaryPath);
      if (await existingFile.exists()) {
        try {
          await existingFile.rename(backupPath!);
          debugPrint(
            '📦 [BinaryManager] Backed up ${type.displayName} to .bak',
          );
        } catch (e) {
          debugPrint('⚠️ [BinaryManager] Backup failed: $e');
          yield BinaryDownloadProgress.error(type, 'Backup failed: $e');
          return;
        }
      }
    }

    // Clear caches so downloadBinary works fresh
    _cachedPaths[type] = null;
    _cachedVersions[type] = null;

    // Step 2: Download new binary
    try {
      await for (final progress in downloadBinary(type)) {
        if (progress.status == BinaryDownloadStatus.error) {
          downloadError = progress.error;
          break;
        }

        yield progress;

        if (progress.status == BinaryDownloadStatus.completed) {
          downloadSucceeded = true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [BinaryManager] Download failed during safe update: $e');
      downloadError = e.toString();
    }

    // Step 3/4: Cleanup or rollback
    if (downloadSucceeded) {
      // Delete backup
      if (backupPath != null) {
        try {
          final backupFile = File(backupPath);
          if (await backupFile.exists()) {
            await backupFile.delete();
            debugPrint(
              '🗑️ [BinaryManager] Deleted backup for ${type.displayName}',
            );
          }
        } catch (e) {
          debugPrint('⚠️ [BinaryManager] Failed to delete backup: $e');
          // Non-critical — backup file left behind but new binary works
        }
      }
    } else {
      // Rollback: restore backup
      if (backupPath != null) {
        try {
          final backupFile = File(backupPath);
          if (await backupFile.exists()) {
            final originalPath = path.join(_binDir!, type.filename);
            // DL-016 — Windows File.rename fails onto an existing path:
            // a partial file left at the original name by the failed
            // download would permanently strand the .bak (binary
            // "missing" until manual reinstall). Clear it first.
            final partial = File(originalPath);
            if (await partial.exists()) {
              try {
                await partial.delete();
              } catch (_) {}
            }
            await backupFile.rename(originalPath);
            _cachedPaths[type] = originalPath;
            debugPrint(
              '♻️ [BinaryManager] Rolled back ${type.displayName} from backup',
            );
            // Restore version cache
            final version = await _getVersion(type, originalPath);
            _cachedVersions[type] = version;
          }
        } catch (e) {
          debugPrint('⚠️ [BinaryManager] Rollback failed: $e');
          // DL-016 — a failed rollback means the binary is now MISSING
          // on disk (only the .bak survives, adopted on next launch).
          // Surface the event so the fleet-level wave is measurable.
          _emitTelemetry('binary_rollback_failed', {'binary': type.name});
        }
      }
      final reason =
          downloadError == null || downloadError.isEmpty
              ? ''
              : ': $downloadError';
      final message =
          backupPath == null
              ? 'Update failed$reason'
              : 'Update failed, rolled back to previous version$reason';
      yield BinaryDownloadProgress.error(type, message);
    }
  }

  /// Get the last modified date of a binary
  Future<DateTime?> getLastUpdated(BinaryType type) async {
    await _ensureInitialized();
    final binaryPath = _cachedPaths[type];
    if (binaryPath == null) return null;

    try {
      final file = File(binaryPath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified;
      }
    } catch (e) {
      debugPrint(
        '⚠️ [BinaryManager] Failed to get last updated for ${type.displayName}: $e',
      );
    }
    return null;
  }

  /// Check if a binary needs update (older than specified days)
  Future<bool> needsUpdate(BinaryType type, {int maxAgeDays = 7}) async {
    final lastUpdated = await getLastUpdated(type);
    if (lastUpdated == null) return false; // Binary doesn't exist

    final age = DateTime.now().difference(lastUpdated);
    return age.inDays >= maxAgeDays;
  }

  /// Check and update binaries that are outdated
  /// Returns true if any updates were performed
  Future<bool> autoUpdate({int maxAgeDays = 7}) async {
    await _ensureInitialized();
    var updated = false;

    for (final type in requiredBinaries) {
      if (await needsUpdate(type, maxAgeDays: maxAgeDays)) {
        debugPrint(
          '🔄 [BinaryManager] Auto-updating ${type.displayName} (outdated)',
        );

        try {
          // Safe variant: backs up current binary, downloads new one, and
          // rolls back on failure. Never leaves the user with no binary —
          // the previous code used `updateBinary()` (delete-then-download)
          // which stranded users when the fresh download failed (XProtect
          // scan, network hiccup, Defender quarantine, etc.).
          await for (final progress in updateBinarySafely(type)) {
            if (progress.status == BinaryDownloadStatus.completed) {
              updated = true;
              debugPrint(
                '✅ [BinaryManager] Auto-update completed for ${type.displayName}',
              );
            } else if (progress.status == BinaryDownloadStatus.error) {
              debugPrint(
                '♻️ [BinaryManager] Auto-update rolled back for ${type.displayName}: '
                '${progress.error ?? "unknown error"}',
              );
            }
          }
        } catch (e) {
          debugPrint(
            '⚠️ [BinaryManager] Auto-update failed for ${type.displayName}: $e',
          );
          // Continue with other binaries
        }
      }
    }

    return updated;
  }

  Future<void> _ensureInitialized() async {
    // initialize() itself handles the completer gating — delegating here
    // means concurrent callers all converge on the same future.
    await initialize();
  }

  /// Validate that a binary is present and not corrupted.
  /// Uses size + executable permission checks only — NO subprocess calls.
  /// Running `--version` on PyInstaller binaries triggers macOS XProtect
  /// scanning (6-45s each), making cold start unacceptably slow.
  static Future<bool> _validateBinary(
    BinaryType type,
    String binaryPath,
  ) async {
    try {
      final file = File(binaryPath);
      if (!await file.exists()) {
        debugPrint(
          '⚠️ [BinaryManager] ${type.displayName} missing at $binaryPath',
        );
        return false;
      }
      final stat = await file.stat();

      // Type-aware size floor — catches truncated/partial downloads that
      // pass a generic non-zero check but are clearly incomplete. Each
      // binary's threshold is 50-70% of its expected production size.
      final minBytes = type.minHealthyBytes;
      if (stat.size < minBytes) {
        debugPrint(
          '⚠️ [BinaryManager] ${type.displayName} too small '
          '(${stat.size}B, need ≥${minBytes}B) — likely truncated download',
        );
        return false;
      }

      // Check executable permission (Unix: mode has execute bit)
      if (!Platform.isWindows) {
        final hasExecBit = (stat.mode & 0x49) != 0; // owner|group|other execute
        if (!hasExecBit) {
          debugPrint(
            '⚠️ [BinaryManager] ${type.displayName} not executable (mode=${stat.mode.toRadixString(8)})',
          );
          return false;
        }
      }

      debugPrint(
        '✅ [BinaryManager] ${type.displayName} validated (${(stat.size / 1024 / 1024).toStringAsFixed(1)}MB)',
      );
      return true;
    } catch (e) {
      debugPrint(
        '⚠️ [BinaryManager] ${type.displayName} validation failed: $e',
      );
      return false;
    }
  }

  /// Post-download validation on Windows.
  /// 1. Remove Zone.Identifier ADS (prevents SmartScreen prompt)
  /// 2. Run --version to verify binary executes
  /// Returns null on success, or an actionable error message on failure.
  static Future<String?> _validateBinaryWindows(
    BinaryType type,
    String binaryPath,
  ) async {
    // Step 1: Remove Zone.Identifier alternate data stream (NTFS).
    // This ADS is added by browsers/downloaders and triggers SmartScreen prompts.
    try {
      final adsPath = '$binaryPath:Zone.Identifier';
      final adsResult = await Process.run('cmd', [
        '/c',
        'del',
        '/f',
        adsPath,
      ]).timeout(const Duration(seconds: 5));
      debugPrint(
        '🛡️ [BinaryManager] Zone.Identifier removal: exit=${adsResult.exitCode}',
      );
    } catch (_) {
      // Non-fatal: ADS may not exist or cmd may fail
    }

    // Step 2: Verify binary can actually execute
    try {
      final versionFlag = type == BinaryType.ffmpeg ? '-version' : '--version';
      final result = await Process.run(binaryPath, [
        versionFlag,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) {
        debugPrint(
          '✅ [BinaryManager] ${type.displayName} execution verified on Windows',
        );
        return null; // Success
      }
      final stderr = result.stderr.toString().toLowerCase();
      if (stderr.contains('access is denied') ||
          stderr.contains('access denied')) {
        return '${type.displayName} is blocked by Windows security. '
            'Add an exception for this folder in your antivirus: '
            '${path.dirname(binaryPath)}';
      }
      return '${type.displayName} failed to run (exit code ${result.exitCode}). '
          'Your antivirus may have quarantined it. '
          'Add an exception for: ${path.dirname(binaryPath)}';
    } on TimeoutException {
      // Timeout likely means Windows Defender is scanning or has quarantined the binary.
      // Do NOT treat as success — FFmpeg may be non-functional.
      debugPrint(
        '⚠️ [BinaryManager] ${type.displayName} version check timed out (Windows) — binary may be blocked',
      );
      return '${type.displayName} timed out during verification. '
          'Windows Defender may be scanning or blocking it. '
          'Add an exception for: ${path.dirname(binaryPath)}';
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('access is denied') ||
          msg.contains('cannot find') ||
          msg.contains('is not recognized')) {
        return '${type.displayName} cannot execute. '
            'Windows Defender or antivirus may have blocked/quarantined it. '
            'Add an exception for: ${path.dirname(binaryPath)}';
      }
      debugPrint('⚠️ [BinaryManager] ${type.displayName} validation error: $e');
      // Non-fatal: binary may still work despite validation error
      return null;
    }
  }

  Future<String?> _getVersion(BinaryType type, String binaryPath) async {
    try {
      final versionFlag = type == BinaryType.ffmpeg ? '-version' : '--version';
      final result = await Process.run(binaryPath, [
        versionFlag,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) {
        return _formatVersionOutput(type, result.stdout.toString());
      }
    } on TimeoutException {
      debugPrint(
        '⚠️ [BinaryManager] ${type.displayName} version check timed out',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [BinaryManager] Failed to get ${type.displayName} version: $e',
      );
    }
    return null;
  }

  static String? _formatVersionOutput(BinaryType type, String output) {
    final firstLine = output.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return null;

    if (type == BinaryType.ffmpeg) {
      final match = RegExp(r'^ffmpeg version\s+([^\s]+)').firstMatch(firstLine);
      if (match != null) {
        return match.group(1)!.replaceFirst(RegExp(r'-https?://.*$'), '');
      }
    }

    return firstLine.length > 50 ? firstLine.substring(0, 50) : firstLine;
  }

  @visibleForTesting
  static String? formatVersionOutputForTest(BinaryType type, String output) {
    return _formatVersionOutput(type, output);
  }

  void dispose() {
    _downloader.dispose();
  }
}

/// Overall progress for downloading multiple binaries
class BinaryManagerProgress {
  final BinaryType? currentBinary;
  final BinaryDownloadProgress? currentProgress;
  final int completedCount;
  final int totalCount;
  final BinaryManagerStatus status;
  final String? error;

  /// Optional binaries whose mirror chain was exhausted during this run.
  /// First-launch is allowed to complete with these missing — features that
  /// depend on them (image/carousel download via gallery-dl) will be
  /// unavailable, but core video extraction continues working. UI surfaces
  /// can render a non-blocking notice when this list is non-empty on the
  /// terminal `completed` event.
  final List<BinaryType> skippedOptional;

  const BinaryManagerProgress({
    required this.currentBinary,
    required this.currentProgress,
    required this.completedCount,
    required this.totalCount,
    required this.status,
    this.error,
    this.skippedOptional = const [],
  });

  double get overallProgress =>
      totalCount > 0 ? completedCount / totalCount : 0;
  bool get isCompleted => status == BinaryManagerStatus.completed;
  bool get hasError => status == BinaryManagerStatus.error;
}

enum BinaryManagerStatus { checking, downloading, completed, error }
