import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

// Import DB with prefix to avoid name clash: Drift generates a `ConversionJob`
// data class from the `ConversionJobs` table, which clashes with our domain entity.
import '../../../../core/database/app_database.dart' as database;
import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/process_helper.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/conversion_job.dart';
import '../../domain/entities/conversion_status.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/output_format.dart';
import '../../domain/repositories/conversion_repository.dart';
import 'converter_providers.dart';

/// Provider for the conversion queue manager.
final conversionQueueProvider =
    StateNotifierProvider<ConversionQueueNotifier, List<ConversionJob>>((ref) {
      final repository = ref.watch(conversionRepositoryProvider);
      final appDb = ref.watch(databaseProvider);
      final isPremium = ref.watch(isPremiumProvider);
      final binaryManager = ref.watch(binaryManagerProvider);
      return ConversionQueueNotifier(
        repository,
        appDb,
        isPremium,
        binaryManager,
        isNotificationsEnabled:
            () => ref.read(settingsProvider).notificationsEnabled,
      );
    });

/// Manages the conversion queue: adding jobs, starting conversions,
/// tracking active jobs, auto-starting next in queue.
///
/// Concurrency limits:
/// - Free tier: 1 concurrent conversion
/// - Premium: up to 4 concurrent conversions (capped at CPU cores)
///
/// Handles three conversion paths:
/// - Normal convert (single input → single output)
/// - Stabilize (two-pass vidstab)
/// - Concat (multiple inputs → single output)
class ConversionQueueNotifier extends StateNotifier<List<ConversionJob>> {
  final ConversionRepository _repository;
  final database.AppDatabase _db;
  final bool _isPremium;
  final BinaryManager _binaryManager;
  final bool Function() _isNotificationsEnabled;

  /// Active conversion stream subscriptions keyed by job ID
  final Map<String, StreamSubscription<ConversionProgress>> _subscriptions = {};

  static const _uuid = Uuid();

  /// ETA smoothing: track last N ETA values per job for moving average
  final Map<String, List<int>> _etaHistory = {};
  static const _etaHistorySize = 8;
  static const _outputProbeTimeout = Duration(seconds: 15);

  ConversionQueueNotifier(
    this._repository,
    this._db,
    this._isPremium,
    this._binaryManager, {
    required bool Function() isNotificationsEnabled,
  }) : _isNotificationsEnabled = isNotificationsEnabled,
       super([]) {
    _loadFromDatabase();
  }

  /// Smooth ETA using a simple moving average to prevent jitter.
  Duration? _smoothEta(String jobId, Duration? rawEta) {
    if (rawEta == null) return null;

    final history = _etaHistory.putIfAbsent(jobId, () => []);
    history.add(rawEta.inSeconds);
    if (history.length > _etaHistorySize) history.removeAt(0);

    // Need at least 3 samples for meaningful smoothing
    if (history.length < 3) return rawEta;

    final avg = history.reduce((a, b) => a + b) / history.length;
    return Duration(seconds: avg.round());
  }

  /// Maximum concurrent conversions based on premium status
  int get maxConcurrent {
    if (!_isPremium) return 1;
    final cores = Platform.numberOfProcessors;
    return cores.clamp(1, 4);
  }

  /// Number of currently active (converting) jobs
  int get activeCount => state.where((j) => j.status.isActive).length;

  /// Add a file to the conversion queue.
  ///
  /// [outputDir] overrides the default output directory (input file's dir).
  Future<ConversionJob> addToQueue({
    required String inputPath,
    required ConversionConfig config,
    MediaInfo? mediaInfo,
    String? presetName,
    int? downloadId,
    String? outputDir,
  }) async {
    // Validate input file exists
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('Input file not found: $inputPath');
    }

    // Validate: can't create GIF/WebP from audio-only file
    if ((config.outputFormat == OutputFormat.gif ||
            config.outputFormat == OutputFormat.webp) &&
        mediaInfo != null &&
        !mediaInfo.hasVideo) {
      throw Exception(
        'Cannot create ${config.outputFormat.name.toUpperCase()} from audio-only file',
      );
    }

    final inputFilename = p.basename(inputPath);
    final inputSize = await inputFile.length();

    // Generate output path
    final outputPath = _generateOutputPath(
      inputPath,
      config,
      outputDir: outputDir,
    );
    final outputFilename = p.basename(outputPath);

    // 6A: Validate output directory exists and is writable
    final outputDirectory = Directory(p.dirname(outputPath));
    if (!await outputDirectory.exists()) {
      try {
        await outputDirectory.create(recursive: true);
      } catch (e) {
        throw Exception(
          'Cannot create output directory: ${outputDirectory.path}',
        );
      }
    }
    try {
      final testFile = File(p.join(outputDirectory.path, '.ssvid_write_test'));
      await testFile.writeAsString('');
      await testFile.delete();
    } catch (_) {
      throw Exception(
        'Output directory is not writable: ${outputDirectory.path}',
      );
    }

    // 9B: Duplicate job detection — block identical active conversions
    final isDuplicate = state.any(
      (j) =>
          j.inputPath == inputPath &&
          j.outputPath == outputPath &&
          j.status.isActive,
    );
    if (isDuplicate) {
      throw Exception(
        'This file is already being converted with the same settings',
      );
    }

    final job = ConversionJob(
      id: _uuid.v4(),
      inputPath: inputPath,
      outputPath: outputPath,
      inputFilename: inputFilename,
      outputFilename: outputFilename,
      status: ConversionStatus.queued,
      inputSize: inputSize,
      inputDuration: mediaInfo?.duration,
      presetName: presetName,
      config: config,
      downloadId: downloadId,
      createdAt: DateTime.now(),
    );

    // Save to database
    await _db.insertConversionJob(
      database.ConversionJobsCompanion(
        id: Value(job.id),
        inputPath: Value(job.inputPath),
        outputPath: Value(job.outputPath),
        inputFilename: Value(job.inputFilename),
        outputFilename: Value(job.outputFilename),
        status: Value(job.status.name),
        progress: Value(0.0),
        inputSize: Value(job.inputSize),
        durationMs: Value(job.inputDuration?.inMilliseconds),
        presetName: Value(job.presetName),
        configJson: Value(job.config.toJsonString()),
        downloadId: Value(job.downloadId),
        createdAt: Value(job.createdAt),
      ),
    );

    state = [...state, job];

    appLogger.info(
      '[ConversionQueue] Added job ${job.id}: $inputFilename -> $outputFilename',
    );

    // Try to start if slots available
    _processQueue();

    return job;
  }

  /// Cancel a conversion job.
  Future<void> cancelJob(String jobId) async {
    final index = state.indexWhere((j) => j.id == jobId);
    if (index < 0) return;

    final job = state[index];

    // Cancel active process
    _repository.cancelConversion(jobId);
    _subscriptions[jobId]?.cancel();
    _subscriptions.remove(jobId);

    // Update state
    final updated = job.copyWith(status: ConversionStatus.cancelled);
    final newState = List<ConversionJob>.from(state);
    newState[index] = updated;
    state = newState;

    // Update database
    await _db.updateConversionJobStatus(jobId, ConversionStatus.cancelled.name);

    // Clean up partial output
    await _deleteOutputArtifact(job);

    appLogger.info('[ConversionQueue] Cancelled job $jobId');

    // Process next in queue
    _processQueue();
  }

  /// Remove a completed/failed/cancelled job from the list.
  Future<void> removeJob(String jobId) async {
    _subscriptions[jobId]?.cancel();
    _subscriptions.remove(jobId);
    _repository.clearJobLog(jobId);

    state = state.where((j) => j.id != jobId).toList();
    await _db.deleteConversionJob(jobId);

    appLogger.debug('[ConversionQueue] Removed job $jobId');
  }

  /// Remove all completed jobs.
  Future<void> clearCompleted() async {
    final completed =
        state.where((j) => j.status == ConversionStatus.completed).toList();
    for (final job in completed) {
      _repository.clearJobLog(job.id);
      await _db.deleteConversionJob(job.id);
    }
    state = state.where((j) => j.status != ConversionStatus.completed).toList();
  }

  /// Move a queued job to the top of the queue (just below any active jobs).
  ///
  /// Only applies to jobs in the [ConversionStatus.queued] state — converting,
  /// completed, failed, and cancelled jobs are not reorderable. The new
  /// position is "first queued slot", so a single active job in front stays
  /// in front, and the moved job will be picked up next by [_processQueue].
  void moveJobToTop(String jobId) {
    final job = state.firstWhere(
      (j) => j.id == jobId,
      orElse: () => throw StateError('Job not found'),
    );
    if (job.status != ConversionStatus.queued) return;

    // Find the index of the first queued job (insertion point).
    final firstQueuedIndex = state.indexWhere(
      (j) => j.status == ConversionStatus.queued,
    );
    if (firstQueuedIndex < 0) return;

    final currentIndex = state.indexWhere((j) => j.id == jobId);
    if (currentIndex == firstQueuedIndex) return; // Already at top.

    final reordered = List<ConversionJob>.from(state);
    reordered.removeAt(currentIndex);
    // After removal, recompute target — if the removed job was after the
    // insertion point, the index doesn't shift. If it was before, it does.
    final insertAt =
        currentIndex < firstQueuedIndex
            ? firstQueuedIndex - 1
            : firstQueuedIndex;
    reordered.insert(insertAt, job);
    state = reordered;

    appLogger.debug('[ConversionQueue] Moved job $jobId to top of queue');
  }

  /// Move a queued job one position earlier in the queue (closer to the top).
  /// No-op if the job isn't queued or is already at the top of the queued
  /// section. Skips over active jobs — you can't insert above a converting job.
  void moveJobUp(String jobId) {
    final currentIndex = state.indexWhere((j) => j.id == jobId);
    if (currentIndex <= 0) return;
    final job = state[currentIndex];
    if (job.status != ConversionStatus.queued) return;

    // Find previous queued job.
    int prevQueuedIndex = -1;
    for (int i = currentIndex - 1; i >= 0; i--) {
      if (state[i].status == ConversionStatus.queued) {
        prevQueuedIndex = i;
        break;
      }
    }
    if (prevQueuedIndex < 0) return;

    final reordered = List<ConversionJob>.from(state);
    reordered.removeAt(currentIndex);
    reordered.insert(prevQueuedIndex, job);
    state = reordered;
  }

  /// Move a queued job one position later in the queue (further from the top).
  void moveJobDown(String jobId) {
    final currentIndex = state.indexWhere((j) => j.id == jobId);
    if (currentIndex < 0 || currentIndex >= state.length - 1) return;
    final job = state[currentIndex];
    if (job.status != ConversionStatus.queued) return;

    // Find next queued job.
    int nextQueuedIndex = -1;
    for (int i = currentIndex + 1; i < state.length; i++) {
      if (state[i].status == ConversionStatus.queued) {
        nextQueuedIndex = i;
        break;
      }
    }
    if (nextQueuedIndex < 0) return;

    final reordered = List<ConversionJob>.from(state);
    reordered.removeAt(currentIndex);
    reordered.insert(nextQueuedIndex, job);
    state = reordered;
  }

  /// Retry a failed (or cancelled) job from a clean slate.
  ///
  /// Before re-queueing, this:
  /// 1. Verifies the original input file still exists. If the user moved or
  ///    deleted it since the last attempt, the retry fails up-front with a
  ///    descriptive error instead of letting ffmpeg blow up mid-pipeline.
  /// 2. Deletes any stale partial output file from the previous attempt so
  ///    the retry starts from a known-empty target. ffmpeg's `-y` flag would
  ///    overwrite anyway, but a partial file on disk is misleading to the
  ///    user (looks like a successful conversion in their file manager) and
  ///    wastes space if the retry never gets that far.
  Future<void> retryJob(String jobId) async {
    final index = state.indexWhere((j) => j.id == jobId);
    if (index < 0) return;

    final job = state[index];
    if (job.status != ConversionStatus.failed &&
        job.status != ConversionStatus.cancelled) {
      return;
    }

    // 1. Verify input still exists.
    final inputFile = File(job.inputPath);
    if (!await inputFile.exists()) {
      appLogger.warning(
        '[ConversionQueue] Retry refused — input missing: ${job.inputPath}',
      );
      final failed = job.copyWith(
        status: ConversionStatus.failed,
        errorMessage: 'converter.errors.inputMissing',
        clearSpeed: true,
        clearEta: true,
      );
      final newState = List<ConversionJob>.from(state);
      newState[index] = failed;
      state = newState;
      await _db.updateConversionJobStatus(
        jobId,
        ConversionStatus.failed.name,
        errorMessage: 'converter.errors.inputMissing',
      );
      return;
    }

    // 2. Clean up stale partial output from previous attempt.
    try {
      await _deleteOutputArtifact(job);
      appLogger.debug(
        '[ConversionQueue] Cleaned partial output before retry: ${job.outputPath}',
      );
    } catch (e) {
      // Best-effort cleanup — don't block retry on filesystem errors.
      appLogger.warning(
        '[ConversionQueue] Could not clean partial output for $jobId: $e',
      );
    }

    // 3. Reset job state and re-queue.
    final updated = job.copyWith(
      status: ConversionStatus.queued,
      progress: 0.0,
      clearSpeed: true,
      clearEta: true,
      clearErrorMessage: true,
      clearStartedAt: true,
      clearCompletedAt: true,
    );

    final newState = List<ConversionJob>.from(state);
    newState[index] = updated;
    state = newState;

    await _db.updateConversionJobStatus(jobId, ConversionStatus.queued.name);

    _processQueue();
  }

  /// Open the output folder of a completed job.
  void openOutputFolder(String jobId) {
    final job = state.firstWhere(
      (j) => j.id == jobId,
      orElse: () => throw StateError('Job not found'),
    );
    final dir =
        _isDirectoryOutputJob(job) ? job.outputPath : p.dirname(job.outputPath);

    if (Platform.isMacOS) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    } else if (Platform.isLinux) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    }
  }

  /// Reveal (select) the output file in the native file manager.
  void revealOutputFile(String jobId) {
    final job = state.firstWhere(
      (j) => j.id == jobId,
      orElse: () => throw StateError('Job not found'),
    );
    final filePath = job.outputPath;

    if (Platform.isMacOS) {
      ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory:
            _isDirectoryOutputJob(job) ? filePath : p.dirname(filePath),
      ).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory:
            _isDirectoryOutputJob(job) ? filePath : p.dirname(filePath),
      ).ignore();
    } else if (Platform.isLinux) {
      // Linux: no universal "reveal file" — open the containing folder.
      ProcessHelper.openDirectoryInFileManager(
        _isDirectoryOutputJob(job) ? filePath : p.dirname(filePath),
      ).ignore();
    }
  }

  // ── Private ──────────────────────────────────────────────────

  /// Load existing jobs from database on initialization.
  Future<void> _loadFromDatabase() async {
    try {
      final rows = await _db.getAllConversionJobs();
      final jobs = rows.map((row) => _rowToJob(row)).toList();
      state = jobs;

      // 6D: Handle jobs interrupted by app crash — mark as failed, clean temp files
      for (int i = 0; i < state.length; i++) {
        if (state[i].status == ConversionStatus.converting ||
            state[i].status == ConversionStatus.probing) {
          final staleJob = state[i];

          // Clean up temp files from interrupted multi-pass operations
          _cleanupTempFiles(staleJob.outputPath);

          // Clean up partial output file
          await _deleteOutputArtifact(staleJob);

          final updated = staleJob.copyWith(
            status: ConversionStatus.failed,
            progress: 0.0,
            errorMessage: 'Interrupted — app was closed during conversion',
            completedAt: DateTime.now(),
          );
          final newState = List<ConversionJob>.from(state);
          newState[i] = updated;
          state = newState;
          await _db.updateConversionJobStatus(
            staleJob.id,
            ConversionStatus.failed.name,
            errorMessage: 'Interrupted — app was closed during conversion',
          );
          appLogger.info(
            '[ConversionQueue] Marked interrupted job as failed: ${staleJob.inputFilename}',
          );
        }
      }

      _processQueue();
    } catch (e) {
      appLogger.error('[ConversionQueue] Failed to load from DB', e);
    }
  }

  /// Process the queue: start conversions if slots are available.
  void _processQueue() {
    while (activeCount < maxConcurrent) {
      final nextJob = state.cast<ConversionJob?>().firstWhere(
        (j) => j!.status == ConversionStatus.queued,
        orElse: () => null,
      );
      if (nextJob == null) break;
      _startConversion(nextJob);
    }
  }

  /// Start converting a job.
  ///
  /// Routes to the appropriate conversion method:
  /// - concat: multiple input files → single output
  /// - stabilize: two-pass vidstab
  /// - normal: single input → single output
  void _startConversion(ConversionJob job) {
    final index = state.indexWhere((j) => j.id == job.id);
    if (index < 0) return;
    if (state[index].status != ConversionStatus.queued) return;

    // 6E: Re-validate input file still exists at execution time
    if (!File(job.inputPath).existsSync()) {
      _onError(job.id, 'Input file no longer exists: ${job.inputFilename}');
      return;
    }

    // Reserve the worker slot synchronously before any async hop. Without
    // this, `_processQueue()` can keep selecting the same queued job (or start
    // every queued job) while `getBinaryPath()` is still awaiting, which can
    // lock the UI thread and unleash too many ffmpeg processes at once.
    final reserved = state[index].copyWith(
      status: ConversionStatus.probing,
      progress: 0.0,
      clearSpeed: true,
      clearEta: true,
      clearErrorMessage: true,
      clearCompletedAt: true,
    );
    final newState = List<ConversionJob>.from(state);
    newState[index] = reserved;
    state = newState;

    _db.updateConversionJobStatus(job.id, ConversionStatus.probing.name);

    // 6B: Verify FFmpeg binary is still available on disk
    _verifyBinaryAndStart(reserved);
  }

  /// Async check for binary availability before starting conversion.
  Future<void> _verifyBinaryAndStart(ConversionJob job) async {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null || !File(ffmpegPath).existsSync()) {
      _onError(
        job.id,
        'FFmpeg binary not found — please restart the app to re-download',
      );
      return;
    }

    final index = state.indexWhere((j) => j.id == job.id);
    if (index < 0 || state[index].status != ConversionStatus.probing) {
      return;
    }

    var prepared = state[index];
    if (_isDirectoryOutputJob(prepared)) {
      final normalizedOutputPath = _normalizeSplitOutputPath(
        prepared.outputPath,
      );
      final normalizedOutputFilename = p.basename(normalizedOutputPath);
      if (normalizedOutputPath != prepared.outputPath ||
          normalizedOutputFilename != prepared.outputFilename) {
        prepared = prepared.copyWith(
          outputPath: normalizedOutputPath,
          outputFilename: normalizedOutputFilename,
        );
        final normalizedState = List<ConversionJob>.from(state);
        normalizedState[index] = prepared;
        state = normalizedState;
        await _db.updateConversionJobOutputTarget(
          prepared.id,
          outputPath: normalizedOutputPath,
          outputFilename: normalizedOutputFilename,
        );
      }
    }

    // Update status to converting
    final started = prepared.copyWith(
      status: ConversionStatus.converting,
      startedAt: DateTime.now(),
    );
    final newState = List<ConversionJob>.from(state);
    newState[index] = started;
    state = newState;

    _db.updateConversionJobProgress(
      job.id,
      status: ConversionStatus.converting.name,
      progress: 0.0,
      startedAt: DateTime.now(),
    );

    appLogger.info(
      '[ConversionQueue] Starting conversion for ${job.inputFilename}',
    );

    // Determine which conversion path to use
    Stream<ConversionProgress> progressStream;

    if (job.config.extractThumbnail) {
      // Thumbnail extraction (non-streaming, instant)
      _extractThumbnail(started);
      return;
    } else if (job.config.extractSubtitles) {
      // Subtitle extraction (non-streaming, instant)
      _extractSubtitles(started);
      return;
    } else if (job.config.splitInterval != null) {
      progressStream = _repository.splitVideo(
        jobId: started.id,
        inputPath: started.inputPath,
        outputDir: started.outputPath,
        intervalSeconds: started.config.splitInterval ?? 60,
        inputDuration: started.inputDuration,
      );
    } else if (job.config.isConcat && job.config.concatWithTransition) {
      // Concat with crossfade transitions
      progressStream = _repository.concatWithTransitions(
        jobId: started.id,
        inputFiles: [job.inputPath, ...?job.config.concatFiles],
        outputPath: job.outputPath,
        config: job.config,
        transitionDuration: job.config.transitionDuration ?? 1.0,
      );
    } else if (job.config.isConcat && job.config.concatFiles != null) {
      // Concat path
      progressStream = _repository.concatFiles(
        jobId: started.id,
        inputFiles: [job.inputPath, ...job.config.concatFiles!],
        outputPath: job.outputPath,
        config: job.config,
        totalDuration: job.inputDuration,
      );
    } else if (job.config.stabilize) {
      // Stabilization path
      progressStream = _repository.stabilizeFile(started);
    } else {
      // Normal conversion path
      progressStream = _repository.convertFile(started);
    }

    // Subscribe to progress stream
    final sub = progressStream.listen(
      (progress) {
        _onProgress(job.id, progress);
      },
      onError: (error) {
        _onError(job.id, error.toString());
      },
      onDone: () {
        // Stream completed
      },
    );

    _subscriptions[job.id] = sub;
  }

  /// Handle progress update from conversion stream.
  void _onProgress(String jobId, ConversionProgress progress) {
    final index = state.indexWhere((j) => j.id == jobId);
    if (index < 0) return;

    final job = state[index];
    if (job.status == ConversionStatus.cancelled) {
      return;
    }

    if (progress.error != null) {
      _onError(jobId, progress.error!);
      return;
    }

    if (progress.isComplete) {
      // 6C: Verify output file integrity before marking complete
      _verifyAndComplete(job, progress.outputSize);
      return;
    }

    // Regular progress update with ETA smoothing
    final smoothedEta = _smoothEta(jobId, progress.eta);
    final updated = job.copyWith(
      progress: progress.progress,
      speed: progress.speed,
      eta: smoothedEta,
      outputSize: progress.outputSize,
    );
    final newState = List<ConversionJob>.from(state);
    newState[index] = updated;
    state = newState;

    // Throttle DB updates (every ~5% to avoid excessive writes)
    final prevPercent = (job.progress * 20).round();
    final newPercent = (progress.progress * 20).round();
    if (newPercent > prevPercent) {
      _db.updateConversionJobProgress(
        jobId,
        status: ConversionStatus.converting.name,
        progress: progress.progress,
      );
    }
  }

  /// 6C: Verify output file integrity before marking a job as completed.
  Future<void> _verifyAndComplete(ConversionJob job, int? reportedSize) async {
    final currentIndex = state.indexWhere((j) => j.id == job.id);
    if (currentIndex < 0) return;

    final currentJob = state[currentIndex];
    if (currentJob.status == ConversionStatus.cancelled) {
      return;
    }

    if (_isDirectoryOutputJob(currentJob)) {
      final outputDir = Directory(currentJob.outputPath);
      if (!await outputDir.exists()) {
        _onError(currentJob.id, 'Output folder was not created');
        return;
      }

      final entries = await outputDir.list().toList();
      var outputSize = 0;
      var fileCount = 0;
      for (final entry in entries) {
        if (entry is! File) continue;
        final length = await entry.length();
        if (length <= 0) continue;
        fileCount++;
        outputSize += length;
      }

      if (fileCount == 0) {
        _onError(
          currentJob.id,
          'No output segments were created — split may have failed silently',
        );
        return;
      }

      await _markCompleted(currentJob, outputSize);
      return;
    }

    final outputFile = File(currentJob.outputPath);

    // Check file exists
    if (!outputFile.existsSync()) {
      _onError(currentJob.id, 'Output file was not created');
      return;
    }

    // Check not empty
    final outputSize = reportedSize ?? await outputFile.length();
    if (outputSize == 0) {
      _onError(
        currentJob.id,
        'Output file is empty (0 bytes) — conversion may have failed silently',
      );
      try {
        await outputFile.delete();
      } catch (_) {}
      return;
    }

    // For video/audio files, quick-probe to verify the container is valid
    if (currentJob.config.outputFormat.isVideo ||
        currentJob.config.outputFormat.isAudioOnly) {
      final isValid = await _quickProbeOutput(currentJob.outputPath);
      if (!isValid) {
        appLogger.warning(
          '[ConversionQueue] Output probe failed for ${currentJob.outputFilename} — marking complete anyway (probe may not support this format)',
        );
        // Don't fail — some formats (raw audio, image sequences) don't probe well
      }
    }

    await _markCompleted(currentJob, outputSize);
  }

  /// Quick ffprobe check to verify output file is a valid media container.
  /// Returns true if ffprobe can read format info, false otherwise.
  Future<bool> _quickProbeOutput(String path) async {
    try {
      final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
      if (ffmpegPath == null) return true; // Can't verify — assume OK

      // Derive ffprobe path from ffmpeg path
      final dir = p.dirname(ffmpegPath);
      final ffprobePath =
          Platform.isWindows
              ? p.join(dir, 'ffprobe.exe')
              : p.join(dir, 'ffprobe');

      if (!File(ffprobePath).existsSync()) {
        return true; // Can't verify — assume OK
      }

      final process = await ProcessHelper.start(ffprobePath, [
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_format',
        path,
      ]);
      final stdoutFuture =
          process.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
      final stderrFuture =
          process.stderr
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();

      try {
        final exitCode = await process.exitCode.timeout(_outputProbeTimeout);
        final stderr = await stderrFuture;
        await stdoutFuture;
        if (exitCode != 0 && stderr.trim().isNotEmpty) {
          appLogger.debug(
            '[ConversionQueue] Output probe failed for $path: ${stderr.trim()}',
          );
        }
        return exitCode == 0;
      } on TimeoutException {
        try {
          process.kill(ProcessSignal.sigterm);
        } catch (_) {}
        appLogger.warning(
          '[ConversionQueue] Output probe timed out for $path — skipping verification',
        );
        return true;
      }
    } catch (e) {
      appLogger.debug('[ConversionQueue] Quick probe failed: $e');
      return true; // On error, don't block completion
    }
  }

  /// 6D: Clean up temp files left by multi-pass operations (vidstab, GIF palette).
  void _cleanupTempFiles(String outputPath) {
    try {
      final dir = p.dirname(outputPath);
      final baseName = p.basenameWithoutExtension(outputPath);
      final tempSuffixes = ['_vidstab_pass1.trf', '_palette.png'];
      for (final suffix in tempSuffixes) {
        final tempFile = File(p.join(dir, '$baseName$suffix'));
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
          appLogger.debug(
            '[ConversionQueue] Cleaned temp file: ${tempFile.path}',
          );
        }
      }
    } catch (e) {
      appLogger.debug('[ConversionQueue] Temp cleanup error: $e');
    }
  }

  /// Handle conversion error.
  Future<void> _onError(String jobId, String error) async {
    final index = state.indexWhere((j) => j.id == jobId);
    if (index < 0) return;

    final job = state[index];
    if (job.status == ConversionStatus.cancelled) {
      return;
    }
    final failed = job.copyWith(
      status: ConversionStatus.failed,
      errorMessage: _sanitizeError(error),
      completedAt: DateTime.now(),
    );
    final newState = List<ConversionJob>.from(state);
    newState[index] = failed;
    state = newState;

    _db.updateConversionJobProgress(
      jobId,
      status: ConversionStatus.failed.name,
      progress: job.progress,
      errorMessage: _sanitizeError(error),
      completedAt: DateTime.now(),
    );

    _subscriptions[jobId]?.cancel();
    _subscriptions.remove(jobId);
    _etaHistory.remove(jobId);

    // Clean up partial output file and temp files
    await _deleteOutputArtifact(job);
    _cleanupTempFiles(job.outputPath);

    appLogger.error('[ConversionQueue] Failed: ${job.inputFilename} - $error');

    if (_isNotificationsEnabled()) {
      notificationService.show(
        title: '\u274C Conversion Failed',
        body: job.inputFilename,
      );
    }

    // Start next in queue
    _processQueue();
  }

  /// Convert raw ffmpeg error to user-friendly message with recovery suggestion.
  String _sanitizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('no space left') || lower.contains('disk full')) {
      return 'Disk full — free up space or choose a different output directory';
    }
    if (lower.contains('permission denied')) {
      return 'Permission denied — check that the output folder is writable';
    }
    if (lower.contains('no such file')) {
      return 'Input file not found — it may have been moved or deleted';
    }
    if (lower.contains('invalid data found') ||
        lower.contains('invalid argument')) {
      return 'Invalid data — the input file may be corrupt. Try re-downloading it';
    }
    if (lower.contains('codec not found') ||
        (lower.contains('encoder') && lower.contains('not found'))) {
      return 'Codec not available — try a different output format or codec in Advanced settings';
    }
    if (lower.contains('already exists') && lower.contains('overwrite')) {
      return 'Output file already exists';
    }
    if (lower.contains('out of memory') || lower.contains('cannot allocate')) {
      return 'Out of memory — try a lower resolution or close other applications';
    }
    if (lower.contains('broken pipe') || lower.contains('killed')) {
      return 'Process was terminated — conversion may have used too much memory';
    }
    // Keep short errors as-is, truncate long ones
    if (raw.length > 200) return '${raw.substring(0, 200)}...';
    return raw;
  }

  /// Generate a unique output file path based on config.
  ///
  /// [outputDir] overrides the default (same dir as input).
  String _generateOutputPath(
    String inputPath,
    ConversionConfig config, {
    String? outputDir,
  }) {
    final dir = outputDir ?? p.dirname(inputPath);
    final baseName = p.basenameWithoutExtension(inputPath);
    final ext =
        config.extractThumbnail
            ? 'jpg'
            : config.extractSubtitles
            ? 'srt'
            : config.outputFormat.extension;

    // Use descriptive suffix based on operation type
    String suffix;
    if (config.extractThumbnail) {
      final timestamp = config.thumbnailTimestamp ?? 0.0;
      suffix = 'thumb_${timestamp.toInt()}s';
    } else if (config.extractSubtitles) {
      final trackIndex = config.subtitleTrackIndex ?? 0;
      suffix = 'subtitles_$trackIndex';
    } else if (config.splitInterval != null) {
      var outputPath = p.join(dir, '${baseName}_segments');
      var counter = 1;
      while (Directory(outputPath).existsSync() ||
          File(outputPath).existsSync()) {
        outputPath = p.join(dir, '${baseName}_segments_$counter');
        counter++;
      }
      return outputPath;
    } else if (config.isConcat) {
      suffix = 'merged';
    } else if (config.trim != null) {
      suffix = 'trimmed';
    } else if (config.stabilize) {
      suffix = 'stabilized';
    } else if (config.denoise) {
      suffix = 'denoised';
    } else if (config.rotate != null) {
      suffix = 'rotated';
    } else if (config.crop != null) {
      suffix = 'cropped';
    } else if (config.removeAudio) {
      suffix = 'noaudio';
    } else if (config.watermarkPath != null) {
      suffix = 'watermarked';
    } else if (config.subtitlePath != null) {
      suffix = 'subtitled';
    } else if (config.colorEffect != null) {
      suffix = 'graded';
    } else if (config.hdrToSdr) {
      suffix = 'sdr';
    } else if (config.deinterlace) {
      suffix = 'deinterlaced';
    } else if (config.reverse) {
      suffix = 'reversed';
    } else if (config.sharpen) {
      suffix = 'sharpened';
    } else if (config.negate) {
      suffix = 'inverted';
    } else if (config.volumeDb != null) {
      suffix = 'volume';
    } else if (config.audioEqPreset != null) {
      suffix = 'eq';
    } else if (config.audioCompressor) {
      suffix = 'compressed';
    } else if (config.letterbox != null) {
      suffix = 'letterbox';
    } else if (config.loopCount != null) {
      suffix = 'loop${config.loopCount}x';
    } else if (config.channelLayout != null) {
      suffix = config.channelLayout!.replaceAll('.', '_');
    } else if (config.brightness != null || config.contrast != null) {
      suffix = 'adjusted';
    } else {
      suffix = 'converted';
    }

    var outputPath = p.join(dir, '${baseName}_$suffix.$ext');

    // Handle file collision
    var counter = 1;
    while (File(outputPath).existsSync()) {
      outputPath = p.join(dir, '${baseName}_${suffix}_$counter.$ext');
      counter++;
    }

    return outputPath;
  }

  /// Convert a Drift database row to our domain [ConversionJob].
  /// The Drift-generated class is `database.ConversionJob` (from `ConversionJobs` table).
  ConversionJob _rowToJob(database.ConversionJob row) {
    return ConversionJob(
      id: row.id,
      inputPath: row.inputPath,
      outputPath: row.outputPath,
      inputFilename: row.inputFilename,
      outputFilename: row.outputFilename,
      status: ConversionStatus.fromString(row.status),
      progress: row.progress,
      inputSize: row.inputSize,
      outputSize: row.outputSize,
      inputDuration:
          row.durationMs != null
              ? Duration(milliseconds: row.durationMs!)
              : null,
      presetName: row.presetName,
      config: ConversionConfig.fromJsonString(row.configJson),
      downloadId: row.downloadId,
      errorMessage: row.errorMessage,
      createdAt: row.createdAt,
      startedAt: row.startedAt,
      completedAt: row.completedAt,
    );
  }

  /// Extract a thumbnail (non-streaming operation).
  Future<void> _extractThumbnail(ConversionJob job) async {
    try {
      final timestamp = job.config.thumbnailTimestamp ?? 0.0;

      final result = await _repository.extractThumbnail(
        inputPath: job.inputPath,
        outputPath: job.outputPath,
        timestamp: timestamp,
        jobId: job.id,
      );

      if (_shouldIgnoreLateResult(job.id)) {
        return;
      }
      if (result != null) {
        _onProgress(
          job.id,
          ConversionProgress.completed(outputSize: File(result).lengthSync()),
        );
      } else {
        _onError(job.id, 'Thumbnail extraction failed');
      }
    } catch (e) {
      if (_shouldIgnoreLateResult(job.id)) {
        return;
      }
      _onError(job.id, e.toString());
    }
  }

  /// Extract subtitles (non-streaming operation).
  Future<void> _extractSubtitles(ConversionJob job) async {
    try {
      final trackIndex = job.config.subtitleTrackIndex ?? 0;

      final result = await _repository.extractSubtitles(
        inputPath: job.inputPath,
        outputPath: job.outputPath,
        trackIndex: trackIndex,
        jobId: job.id,
      );

      if (_shouldIgnoreLateResult(job.id)) {
        return;
      }
      if (result != null) {
        _onProgress(
          job.id,
          ConversionProgress.completed(outputSize: File(result).lengthSync()),
        );
      } else {
        _onError(job.id, 'No subtitles found in this file');
      }
    } catch (e) {
      if (_shouldIgnoreLateResult(job.id)) {
        return;
      }
      _onError(job.id, e.toString());
    }
  }

  bool _isDirectoryOutputJob(ConversionJob job) =>
      job.config.splitInterval != null;

  bool _shouldIgnoreLateResult(String jobId) {
    final job = state.cast<ConversionJob?>().firstWhere(
      (candidate) => candidate?.id == jobId,
      orElse: () => null,
    );
    return job == null || job.status == ConversionStatus.cancelled;
  }

  String _normalizeSplitOutputPath(String outputPath) {
    if (p.extension(outputPath).isEmpty) {
      return outputPath;
    }
    return p.join(
      p.dirname(outputPath),
      p.basenameWithoutExtension(outputPath),
    );
  }

  Future<void> _deleteOutputArtifact(ConversionJob job) async {
    try {
      if (_isDirectoryOutputJob(job)) {
        final dir = Directory(_normalizeSplitOutputPath(job.outputPath));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        return;
      }

      final file = File(job.outputPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _markCompleted(ConversionJob job, int outputSize) async {
    final index = state.indexWhere((j) => j.id == job.id);
    if (index < 0) return;

    final completed = job.copyWith(
      status: ConversionStatus.completed,
      progress: 1.0,
      outputSize: outputSize,
      completedAt: DateTime.now(),
      clearSpeed: true,
      clearEta: true,
    );
    final newState = List<ConversionJob>.from(state);
    newState[index] = completed;
    state = newState;

    _db.updateConversionJobProgress(
      job.id,
      status: ConversionStatus.completed.name,
      progress: 1.0,
      outputSize: outputSize,
      completedAt: DateTime.now(),
    );

    _subscriptions[job.id]?.cancel();
    _subscriptions.remove(job.id);
    _etaHistory.remove(job.id);

    appLogger.info(
      '[ConversionQueue] Completed: ${job.outputFilename} '
      '($outputSize bytes)',
    );

    if (_isNotificationsEnabled()) {
      notificationService.show(
        title: '\u2705 Conversion Complete',
        body: job.outputFilename,
      );
    }

    _cleanupTempFiles(job.outputPath);
    _processQueue();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
