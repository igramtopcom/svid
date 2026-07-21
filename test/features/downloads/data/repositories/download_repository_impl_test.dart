import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:svid/core/database/app_database.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';

import '../../../../shared/mocks/mocks.dart';

/// Helper to create a test Download (Drift data class)
Download _makeDownload({
  int id = 1,
  String url = 'https://example.com/video.mp4',
  String filename = 'video.mp4',
  String savePath = '/tmp/downloads',
  String status = 'downloading',
  String downloadMethod = 'rust',
  int totalBytes = 10000,
  int downloadedBytes = 5000,
  int speed = 1000,
  int retryCount = 0,
  String userNote = '',
}) {
  return Download(
    id: id,
    url: url,
    filename: filename,
    savePath: savePath,
    status: status,
    totalBytes: totalBytes,
    downloadedBytes: downloadedBytes,
    speed: speed,
    platform: 'youtube',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    retryCount: retryCount,
    downloadMethod: downloadMethod,
    userNote: userNote,
    isWatched: false,
    sourceUrl: '',
    priority: 0,
  );
}

void main() {
  late MockDownloadLocalDataSource mockLocalDS;
  late MockYtDlpDataSource mockYtdlpDS;
  late MockDownloadNativeDataSource mockNativeDS;
  late DownloadRepositoryImpl repo;

  setUp(() {
    mockLocalDS = MockDownloadLocalDataSource();
    mockYtdlpDS = MockYtDlpDataSource();
    mockNativeDS = MockDownloadNativeDataSource();
    repo = DownloadRepositoryImpl(mockLocalDS, mockYtdlpDS, mockNativeDS);
  });

  group('startDownload', () {
    test('routes rust download to native datasource', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.startDownload(1);

      expect(result.isSuccess, isTrue);
      verify(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: download.url,
          outputPath: '${download.savePath}/${download.filename}',
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).called(1);
    });

    test('rejects ytdlp downloads with error', () async {
      final download = _makeDownload(downloadMethod: 'ytdlp');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);

      final result = await repo.startDownload(1);

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      );
    });

    test('returns failure when download not found', () async {
      when(() => mockLocalDS.getDownloadById(99)).thenAnswer((_) async => null);

      final result = await repo.startDownload(99);

      expect(result.isFailure, isTrue);
    });

    test('returns failure for unsupported download method', () async {
      final download = _makeDownload(downloadMethod: 'unknown');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(
          1,
          DownloadStatus.failed,
          errorMessage: any(named: 'errorMessage'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.startDownload(1);

      expect(result.isFailure, isTrue);
    });
  });

  group('pauseDownload', () {
    test('calls native pause for rust downloads', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockNativeDS.pauseDownload(any())).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.paused),
      ).thenAnswer((_) async {});

      final result = await repo.pauseDownload(1);

      expect(result.isSuccess, isTrue);
      verify(() => mockNativeDS.pauseDownload(any())).called(1);
      verify(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.paused),
      ).called(1);
    });

    test('skips native pause for ytdlp downloads', () async {
      final download = _makeDownload(downloadMethod: 'ytdlp');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.paused),
      ).thenAnswer((_) async {});

      final result = await repo.pauseDownload(1);

      expect(result.isSuccess, isTrue);
      verifyNever(() => mockNativeDS.pauseDownload(any()));
      verify(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.paused),
      ).called(1);
    });
  });

  group('resumeDownload', () {
    test(
      'calls native resume for rust downloads and sets downloading',
      () async {
        final download = _makeDownload(
          downloadMethod: 'rust',
          status: 'paused',
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(() => mockNativeDS.resumeDownload(any())).thenAnswer((_) async {});
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).thenAnswer((_) async {});

        final result = await repo.resumeDownload(1);

        expect(result.isSuccess, isTrue);
        verify(() => mockNativeDS.resumeDownload(any())).called(1);
        verify(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).called(1);
      },
    );

    test(
      'sets queued status for ytdlp downloads (restart via queue)',
      () async {
        final download = _makeDownload(
          downloadMethod: 'ytdlp',
          status: 'paused',
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
        ).thenAnswer((_) async {});

        final result = await repo.resumeDownload(1);

        expect(result.isSuccess, isTrue);
        verifyNever(() => mockNativeDS.resumeDownload(any()));
        verify(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
        ).called(1);
      },
    );

    test('resets exhausted retry budget before queuing ytdlp resume', () async {
      final download = _makeDownload(
        downloadMethod: 'ytdlp',
        status: 'failed',
        retryCount: 3,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockLocalDS.resetRetryCount(1)).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
      ).thenAnswer((_) async {});

      final result = await repo.resumeDownload(1);

      expect(result.isSuccess, isTrue);
      verifyNever(() => mockNativeDS.resumeDownload(any()));
      verifyInOrder([
        () => mockLocalDS.resetRetryCount(1),
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
      ]);
    });
  });

  group('cancelDownload', () {
    test('calls native cancel and cleanup for rust downloads', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockNativeDS.cancelDownload(any())).thenAnswer((_) async {});
      when(() => mockNativeDS.cleanupDownload(any())).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      final result = await repo.cancelDownload(1);

      expect(result.isSuccess, isTrue);
      verify(() => mockNativeDS.cancelDownload(any())).called(1);
      verify(() => mockNativeDS.cleanupDownload(any())).called(1);
    });

    test('calls ytdlp cancel for ytdlp downloads', () async {
      final download = _makeDownload(downloadMethod: 'ytdlp');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockYtdlpDS.cancelByDownloadId(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      final result = await repo.cancelDownload(1);

      expect(result.isSuccess, isTrue);
      verify(() => mockYtdlpDS.cancelByDownloadId(1)).called(1);
      verifyNever(() => mockNativeDS.cancelDownload(any()));
    });

    test('handles null download gracefully', () async {
      when(() => mockLocalDS.getDownloadById(99)).thenAnswer((_) async => null);
      when(
        () => mockLocalDS.updateDownloadStatus(99, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      final result = await repo.cancelDownload(99);

      expect(result.isSuccess, isTrue);
      verifyNever(() => mockNativeDS.cancelDownload(any()));
      verifyNever(() => mockYtdlpDS.cancelDownload(any()));
    });
  });

  group('startDownload - Rust engine without native datasource', () {
    test('returns failure when native datasource is null', () async {
      final repoNoNative = DownloadRepositoryImpl(mockLocalDS, mockYtdlpDS);
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);

      final result = await repoNoNative.startDownload(1);

      expect(result.isFailure, isTrue);
    });
  });

  group('Task 67.2: retryDownload', () {
    test('retries download when under max retries', () async {
      final download = _makeDownload(
        status: 'failed',
        downloadMethod: 'rust',
        retryCount: 0,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.retryDownload(1);

      expect(result.isSuccess, isTrue);
      verify(() => mockLocalDS.incrementRetryCount(1)).called(1);
    });

    test('rejects retry when max retries exceeded', () async {
      final download = _makeDownload(status: 'failed', retryCount: 3);
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(
          1,
          DownloadStatus.failed,
          errorMessage: any(named: 'errorMessage'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.retryDownload(1);

      expect(result.isFailure, isTrue);
      verify(
        () => mockLocalDS.updateDownloadStatus(
          1,
          DownloadStatus.failed,
          errorMessage: 'Maximum retry attempts reached',
        ),
      ).called(1);
      verifyNever(() => mockLocalDS.incrementRetryCount(any()));
    });

    test(
      'manual retry resets exhausted retry budget and starts again',
      () async {
        final download = _makeDownload(
          status: 'failed',
          downloadMethod: 'rust',
          retryCount: 3,
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(() => mockLocalDS.resetRetryCount(1)).thenAnswer((_) async {});
        when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).thenAnswer((_) async {});
        when(
          () => mockNativeDS.startDownload(
            nativeId: any(named: 'nativeId'),
            url: any(named: 'url'),
            outputPath: any(named: 'outputPath'),
            resumeOffset: any(named: 'resumeOffset'),
            numSegments: any(named: 'numSegments'),
            userAgent: any(named: 'userAgent'),
          ),
        ).thenAnswer((_) async {});

        final result = await repo.retryDownload(1, manualRetry: true);

        expect(result.isSuccess, isTrue);
        verify(() => mockLocalDS.resetRetryCount(1)).called(1);
        verify(() => mockLocalDS.incrementRetryCount(1)).called(1);
        verifyNever(
          () => mockLocalDS.updateDownloadStatus(
            1,
            DownloadStatus.failed,
            errorMessage: any(named: 'errorMessage'),
          ),
        );
      },
    );

    test('returns failure when download not found for retry', () async {
      when(() => mockLocalDS.getDownloadById(99)).thenAnswer((_) async => null);

      final result = await repo.retryDownload(99);

      expect(result.isFailure, isTrue);
    });

    test('allows retry at count 1 (under max 3)', () async {
      final download = _makeDownload(
        status: 'failed',
        downloadMethod: 'rust',
        retryCount: 1,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.retryDownload(1);

      expect(result.isSuccess, isTrue);
    });

    test('allows retry at count 2 (last attempt)', () async {
      final download = _makeDownload(
        status: 'failed',
        downloadMethod: 'rust',
        retryCount: 2,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.retryDownload(1);

      expect(result.isSuccess, isTrue);
    });
  });

  group('DL-001: retry finalize + save-folder guards', () {
    // The 19-matcher downloadWithProgress call, factored so `when`,
    // `verify`, and `verifyNever` all share one definition. Mirrors exactly
    // the named args `_retryYtdlpDownload` passes (defaults are NOT part of
    // the invocation, so they need no matchers).
    Stream<YtDlpProgressEvent> Function() retryStreamCall() =>
        () => mockYtdlpDS.downloadWithProgress(
          url: any(named: 'url'),
          outputDir: any(named: 'outputDir'),
          downloadId: any(named: 'downloadId'),
          outputTemplate: any(named: 'outputTemplate'),
          existingTempDir: any(named: 'existingTempDir'),
          format: any(named: 'format'),
          sortOptions: any(named: 'sortOptions'),
          videoFormat: any(named: 'videoFormat'),
          audioFormat: any(named: 'audioFormat'),
          audioBitrateKbps: any(named: 'audioBitrateKbps'),
          mergeFormatPriority: any(named: 'mergeFormatPriority'),
          remuxVideo: any(named: 'remuxVideo'),
          recodeVideo: any(named: 'recodeVideo'),
          extractAudio: any(named: 'extractAudio'),
          maxVideoHeight: any(named: 'maxVideoHeight'),
          targetVideoHeight: any(named: 'targetVideoHeight'),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          onTempDirCreated: any(named: 'onTempDirCreated'),
        );

    test(
      'retry reports complete but the output file is missing → marks failed '
      'with a finalization error (no monitor exception)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dl001_final_');
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        // Folder exists + writable (Guard B passes) but the final file never
        // landed — the stale-row / moved-mid-flight symptom that used to
        // throw PathNotFoundException at .length().
        final missingOutput = p.join(tempDir.path, 'video.mp4');

        final download = _makeDownload(
          status: 'failed',
          downloadMethod: 'ytdlp',
          savePath: tempDir.path,
          filename: 'video.mp4',
          retryCount: 0,
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).thenAnswer((_) async {});
        when(
          () => mockLocalDS.updateTempDirPath(1, null),
        ).thenAnswer((_) async {});
        // Deterministic settle signal: the fire-and-forget retry is awaited
        // to its terminal failed-status update instead of a fixed pump (which
        // races with the real Future.delayed backoff + real-FS exists()).
        final failedMarked = Completer<void>();
        when(
          () => mockLocalDS.updateDownloadStatus(
            1,
            DownloadStatus.failed,
            errorMessage: any(named: 'errorMessage'),
          ),
        ).thenAnswer((_) async {
          if (!failedMarked.isCompleted) failedMarked.complete();
        });
        when(retryStreamCall()).thenAnswer(
          (_) => Stream<YtDlpProgressEvent>.fromIterable([
            YtDlpDownloadComplete(missingOutput),
          ]),
        );

        final result = await repo.retryDownload(1);
        expect(result.isSuccess, isTrue);
        await failedMarked.future.timeout(const Duration(seconds: 5));
        await pumpEventQueue();

        final captured =
            verify(
              () => mockLocalDS.updateDownloadStatus(
                1,
                DownloadStatus.failed,
                errorMessage: captureAny(named: 'errorMessage'),
              ),
            ).captured;
        expect(captured, isNotEmpty);
        expect(captured.last.toString().toLowerCase(), contains('finalized'));
      },
    );

    test(
      'retry with an unrecreatable save folder fails early with a clear '
      'filesystem error and never launches yt-dlp',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dl001_dir_');
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        // A regular file sits where the save folder's parent must be a dir →
        // Directory.create(recursive: true) throws FileSystemException.
        final blocker = File(p.join(tempDir.path, 'blocker'));
        await blocker.writeAsString('x');
        final unrecreatable = p.join(blocker.path, 'downloads');

        final download = _makeDownload(
          status: 'failed',
          downloadMethod: 'ytdlp',
          savePath: unrecreatable,
          retryCount: 0,
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
        final failedMarked = Completer<void>();
        when(
          () => mockLocalDS.updateDownloadStatus(
            1,
            DownloadStatus.failed,
            errorMessage: any(named: 'errorMessage'),
          ),
        ).thenAnswer((_) async {
          if (!failedMarked.isCompleted) failedMarked.complete();
        });

        final result = await repo.retryDownload(1);
        expect(result.isSuccess, isTrue);
        await failedMarked.future.timeout(const Duration(seconds: 5));
        await pumpEventQueue();

        // An unusable destination must never launch yt-dlp.
        verifyNever(retryStreamCall());
        final captured =
            verify(
              () => mockLocalDS.updateDownloadStatus(
                1,
                DownloadStatus.failed,
                errorMessage: captureAny(named: 'errorMessage'),
              ),
            ).captured;
        expect(captured, isNotEmpty);
        expect(captured.last.toString().toLowerCase(), contains('folder'));
      },
    );

    test(
      'retry with a missing-but-recreatable save folder recreates it and '
      'proceeds to launch yt-dlp',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dl001_recr_');
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        // Subdir does not exist yet but is safely creatable under tempDir.
        final recreatable = p.join(tempDir.path, 'nested', 'downloads');
        expect(await Directory(recreatable).exists(), isFalse);

        final download = _makeDownload(
          status: 'failed',
          downloadMethod: 'ytdlp',
          savePath: recreatable,
          retryCount: 0,
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(() => mockLocalDS.incrementRetryCount(1)).thenAnswer((_) async {});
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).thenAnswer((_) async {});
        // Empty stream keeps the test on the guard behavior (folder recreate
        // + proceed) without driving the full completion branch. The launch
        // itself is the deterministic settle signal (no fixed pump race).
        final launched = Completer<void>();
        when(retryStreamCall()).thenAnswer((_) {
          if (!launched.isCompleted) launched.complete();
          return const Stream<YtDlpProgressEvent>.empty();
        });

        final result = await repo.retryDownload(1);
        expect(result.isSuccess, isTrue);
        await launched.future.timeout(const Duration(seconds: 5));
        await pumpEventQueue();

        // Guard recreated the folder and let the retry proceed.
        expect(await Directory(recreatable).exists(), isTrue);
        verify(retryStreamCall()).called(1);
        verify(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).called(1);
      },
    );
  });

  group('Task 67.1: cleanup after cancel', () {
    test('cancelDownload calls cleanupDownload after native cancel', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(() => mockNativeDS.cancelDownload(any())).thenAnswer((_) async {});
      when(() => mockNativeDS.cleanupDownload(any())).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      await repo.cancelDownload(1);

      verifyInOrder([
        () => mockNativeDS.cancelDownload(any()),
        () => mockNativeDS.cleanupDownload(any()),
      ]);
    });

    test('cancelDownload does not call cleanup for ytdlp downloads', () async {
      final download = _makeDownload(downloadMethod: 'ytdlp');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockYtdlpDS.cancelByDownloadId(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      await repo.cancelDownload(1);

      verifyNever(() => mockNativeDS.cleanupDownload(any()));
    });

    test('cancelDownload does not cleanup when download is null', () async {
      when(() => mockLocalDS.getDownloadById(99)).thenAnswer((_) async => null);
      when(
        () => mockLocalDS.updateDownloadStatus(99, DownloadStatus.cancelled),
      ).thenAnswer((_) async {});

      await repo.cancelDownload(99);

      verifyNever(() => mockNativeDS.cleanupDownload(any()));
    });

    test(
      'cancelDownload skips native cancel for queued rust downloads',
      () async {
        final download = _makeDownload(
          downloadMethod: 'rust',
          status: 'queued',
        );
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
        ).thenAnswer((_) async {});

        final result = await repo.cancelDownload(1);

        expect(result.isSuccess, isTrue);
        verifyNever(() => mockNativeDS.cancelDownload(any()));
        verifyNever(() => mockNativeDS.cleanupDownload(any()));
        verify(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.cancelled),
        ).called(1);
      },
    );
  });

  group('Task 67.4: startDownload passes speed limit', () {
    test(
      'startDownload calls native datasource without speed limit by default',
      () async {
        final download = _makeDownload(downloadMethod: 'rust');
        when(
          () => mockLocalDS.getDownloadById(1),
        ).thenAnswer((_) async => download);
        when(
          () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
        ).thenAnswer((_) async {});
        when(
          () => mockNativeDS.startDownload(
            nativeId: any(named: 'nativeId'),
            url: any(named: 'url'),
            outputPath: any(named: 'outputPath'),
            resumeOffset: any(named: 'resumeOffset'),
            maxSpeedBytes: any(named: 'maxSpeedBytes'),
            numSegments: any(named: 'numSegments'),
            userAgent: any(named: 'userAgent'),
          ),
        ).thenAnswer((_) async {});

        final result = await repo.startDownload(1);

        expect(result.isSuccess, isTrue);
        verify(
          () => mockNativeDS.startDownload(
            nativeId: any(named: 'nativeId'),
            url: download.url,
            outputPath: '${download.savePath}/${download.filename}',
            resumeOffset: any(named: 'resumeOffset'),
            numSegments: any(named: 'numSegments'),
            userAgent: any(named: 'userAgent'),
          ),
        ).called(1);
      },
    );
  });

  group('Task 67.5: recoverDownloadsOnStartup', () {
    test('resets downloading rust download to queued', () async {
      final download = _makeDownload(
        id: 1,
        status: 'downloading',
        downloadMethod: 'rust',
        downloadedBytes: 5000,
      );
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => [download]);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadProgress(
          id: any(named: 'id'),
          downloadedBytes: any(named: 'downloadedBytes'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 1),
        onFailure: (_) => fail('should succeed'),
      );
      verify(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
      ).called(1);
    });

    test('resets downloading ytdlp download to queued', () async {
      final download = _makeDownload(
        id: 2,
        status: 'downloading',
        downloadMethod: 'ytdlp',
        downloadedBytes: 0,
      );
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => [download]);
      when(
        () => mockLocalDS.updateDownloadStatus(2, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadProgress(
          id: any(named: 'id'),
          downloadedBytes: any(named: 'downloadedBytes'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 1),
        onFailure: (_) => fail('should succeed'),
      );
    });

    test('marks postProcessing downloads as failed', () async {
      final download = _makeDownload(
        id: 3,
        status: 'postProcessing',
        downloadMethod: 'rust',
      );
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => [download]);
      when(
        () => mockLocalDS.updateDownloadStatus(
          3,
          DownloadStatus.failed,
          errorMessage: any(named: 'errorMessage'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 0), // postProcessing not counted
        onFailure: (_) => fail('should succeed'),
      );
      verify(
        () => mockLocalDS.updateDownloadStatus(
          3,
          DownloadStatus.failed,
          errorMessage: 'App was interrupted during conversion',
        ),
      ).called(1);
    });

    test('resets pending and queued downloads to queued', () async {
      final pending = _makeDownload(id: 4, status: 'pending');
      final queued = _makeDownload(id: 5, status: 'queued');
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => [pending, queued]);
      when(
        () => mockLocalDS.updateDownloadStatus(4, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(5, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadProgress(
          id: any(named: 'id'),
          downloadedBytes: any(named: 'downloadedBytes'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 2),
        onFailure: (_) => fail('should succeed'),
      );
    });

    test(
      'marks stale queued download failed when retry budget is exhausted',
      () async {
        final exhausted = _makeDownload(
          id: 6,
          status: 'queued',
          downloadMethod: 'ytdlp',
          retryCount: 3,
        );
        when(
          () => mockLocalDS.getDownloadsByStatuses(any()),
        ).thenAnswer((_) async => [exhausted]);
        when(
          () => mockLocalDS.updateDownloadStatus(
            6,
            DownloadStatus.failed,
            errorMessage: any(named: 'errorMessage'),
          ),
        ).thenAnswer((_) async {});

        final result = await repo.recoverDownloadsOnStartup();

        expect(result.isSuccess, isTrue);
        result.fold(
          onSuccess: (count) => expect(count, 0),
          onFailure: (_) => fail('should succeed'),
        );
        verify(
          () => mockLocalDS.updateDownloadStatus(
            6,
            DownloadStatus.failed,
            errorMessage: 'Maximum retry attempts reached',
          ),
        ).called(1);
        verifyNever(
          () => mockLocalDS.updateDownloadStatus(6, DownloadStatus.queued),
        );
      },
    );

    test('handles mixed statuses correctly', () async {
      final downloading = _makeDownload(
        id: 1,
        status: 'downloading',
        downloadMethod: 'rust',
      );
      final postProc = _makeDownload(id: 2, status: 'postProcessing');
      final pending = _makeDownload(id: 3, status: 'pending');
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => [downloading, postProc, pending]);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(
          2,
          DownloadStatus.failed,
          errorMessage: any(named: 'errorMessage'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadStatus(3, DownloadStatus.queued),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.updateDownloadProgress(
          id: any(named: 'id'),
          downloadedBytes: any(named: 'downloadedBytes'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 2), // downloading + pending
        onFailure: (_) => fail('should succeed'),
      );
    });

    test('returns 0 when no stale downloads exist', () async {
      when(
        () => mockLocalDS.getDownloadsByStatuses(any()),
      ).thenAnswer((_) async => []);

      final result = await repo.recoverDownloadsOnStartup();

      expect(result.isSuccess, isTrue);
      result.fold(
        onSuccess: (count) => expect(count, 0),
        onFailure: (_) => fail('should succeed'),
      );
    });
  });

  group('Task 67.5: startDownload passes resume offset', () {
    test('passes downloadedBytes as resumeOffset for rust download', () async {
      final download = _makeDownload(
        downloadMethod: 'rust',
        downloadedBytes: 5000,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      await repo.startDownload(1);

      verify(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: download.url,
          outputPath: '${download.savePath}/${download.filename}',
          resumeOffset: 5000,
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).called(1);
    });

    test('passes null resumeOffset when downloadedBytes is 0', () async {
      final download = _makeDownload(
        downloadMethod: 'rust',
        downloadedBytes: 0,
      );
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).thenAnswer((_) async {});

      await repo.startDownload(1);

      verify(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: download.url,
          outputPath: '${download.savePath}/${download.filename}',
          resumeOffset: null,
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
        ),
      ).called(1);
    });
  });

  group('#164: startDownload passes proxyUrl to native datasource', () {
    test('passes proxyUrl when provided', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
          proxyUrl: any(named: 'proxyUrl'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.startDownload(
        1,
        proxyUrl: 'http://proxy.example.com:8080',
      );

      expect(result.isSuccess, isTrue);
      verify(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
          proxyUrl: 'http://proxy.example.com:8080',
        ),
      ).called(1);
    });

    test('passes null proxyUrl when not configured', () async {
      final download = _makeDownload(downloadMethod: 'rust');
      when(
        () => mockLocalDS.getDownloadById(1),
      ).thenAnswer((_) async => download);
      when(
        () => mockLocalDS.updateDownloadStatus(1, DownloadStatus.downloading),
      ).thenAnswer((_) async {});
      when(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
          proxyUrl: any(named: 'proxyUrl'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.startDownload(1);

      expect(result.isSuccess, isTrue);
      verify(
        () => mockNativeDS.startDownload(
          nativeId: any(named: 'nativeId'),
          url: any(named: 'url'),
          outputPath: any(named: 'outputPath'),
          resumeOffset: any(named: 'resumeOffset'),
          numSegments: any(named: 'numSegments'),
          userAgent: any(named: 'userAgent'),
          proxyUrl: null,
        ),
      ).called(1);
    });
  });
}
