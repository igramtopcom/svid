/// Regression tests for `YtDlpDataSource.ensureFFmpegOrRepair`.
///
/// Pre-fix the `StartDownloadUseCase` silently rewrote a DASH
/// `bestvideo+bestaudio` format string to plain `best` whenever
/// `YtDlpDataSource.hasFFmpeg` was false. On YouTube "best" is the
/// pre-muxed single stream, typically ~360p — so users who picked
/// "MP4 · Best" silently received a 360p file. The fix replaces
/// that silent degrade with an awaited repair gate; this file
/// pins the gate's behavior end-to-end without spawning real
/// binaries.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/binaries/binary_manager.dart';
import 'package:svid/core/binaries/binary_type.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

class _MockBinaryManager extends Mock implements BinaryManager {}

void main() {
  // appLogger touches a file backend through plugin channels, so
  // tests that exercise the gate's logging path need the test
  // binding initialized first or they emit a "Binding has not yet
  // been initialized" warning into the test report.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockBinaryManager binaryManager;
  late YtDlpDataSource dataSource;

  setUp(() {
    binaryManager = _MockBinaryManager();
    dataSource = YtDlpDataSource(binaryManager);
  });

  group('ensureFFmpegOrRepair', () {
    test('returns true immediately when FFmpeg is already cached', () async {
      // `_ffmpegPath` starts null on a fresh instance; seed a cached
      // path the same way `initialize()` would, then verify the
      // gate short-circuits without touching the BinaryManager.
      // (We can't poke a private field; the simplest reliable path
      // is to drive it through `triggerRepair` first.)
      when(
        () => binaryManager.triggerRepair(BinaryType.ffmpeg),
      ).thenAnswer((_) async => true);
      when(
        () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
      ).thenAnswer((_) async => '/path/to/ffmpeg');

      // First call performs the repair + caches the path.
      final firstResult = await dataSource.ensureFFmpegOrRepair();
      expect(firstResult, isTrue);
      expect(dataSource.hasFFmpeg, isTrue);

      // Second call must short-circuit — no second BinaryManager
      // round-trip. This is the per-download fast path.
      final secondResult = await dataSource.ensureFFmpegOrRepair();
      expect(secondResult, isTrue);
      verify(
        () => binaryManager.triggerRepair(BinaryType.ffmpeg),
      ).called(1); // only the first call
    });

    test(
      'triggers repair when FFmpeg missing and returns true on success',
      () async {
        when(
          () => binaryManager.triggerRepair(BinaryType.ffmpeg),
        ).thenAnswer((_) async => true);
        when(
          () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
        ).thenAnswer((_) async => '/restored/ffmpeg');

        final result = await dataSource.ensureFFmpegOrRepair();

        expect(result, isTrue);
        expect(
          dataSource.ffmpegPath,
          '/restored/ffmpeg',
          reason:
              'After successful repair the cached path must be refreshed '
              'so subsequent args-build sites pick up the new binary '
              'without an app restart.',
        );
        verify(() => binaryManager.triggerRepair(BinaryType.ffmpeg)).called(1);
        verify(() => binaryManager.getBinaryPath(BinaryType.ffmpeg)).called(1);
      },
    );

    test(
      'returns false when repair fails — no silent rewrite to "best"',
      () async {
        // The repair download itself failed (Defender block, disk
        // full, CDN down). The contract this test pins: we return
        // false, leave `_ffmpegPath` null, and let the caller
        // surface an actionable error. PRE-FIX the silent fallback
        // would have rewritten the format to `best` (→ 360p on
        // YouTube) here; that path no longer exists.
        when(
          () => binaryManager.triggerRepair(BinaryType.ffmpeg),
        ).thenAnswer((_) async => false);

        final result = await dataSource.ensureFFmpegOrRepair();

        expect(result, isFalse);
        expect(dataSource.hasFFmpeg, isFalse);
        // `getBinaryPath` must NOT be called when triggerRepair
        // returned false — caching a stale-null path is the
        // pre-fix behavior we are removing.
        verifyNever(() => binaryManager.getBinaryPath(BinaryType.ffmpeg));
      },
    );

    test(
      'returns false when triggerRepair succeeds but getBinaryPath still null',
      () async {
        // Edge case: BinaryManager reports the repair downloaded
        // OK, but the path resolver still cannot find the binary
        // (e.g. file landed but immediately quarantined post-write
        // by Defender). The gate must STILL return false rather
        // than reporting success on a missing path.
        when(
          () => binaryManager.triggerRepair(BinaryType.ffmpeg),
        ).thenAnswer((_) async => true);
        when(
          () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
        ).thenAnswer((_) async => null);

        final result = await dataSource.ensureFFmpegOrRepair();

        expect(result, isFalse);
        expect(dataSource.hasFFmpeg, isFalse);
      },
    );
  });

  group('ensureYtdlpBinaryReady', () {
    test(
      'repairs yt-dlp even when datasource was initialized with no binary path',
      () async {
        var getPathCalls = 0;
        when(() => binaryManager.getBinaryPath(BinaryType.ytDlp)).thenAnswer((
          _,
        ) async {
          getPathCalls++;
          return getPathCalls == 1 ? null : '/restored/yt-dlp';
        });
        when(
          () => binaryManager.triggerRepair(BinaryType.ytDlp),
        ).thenAnswer((_) async => true);

        final path = await dataSource.ensureYtdlpBinaryReadyForTest();

        expect(path, '/restored/yt-dlp');
        expect(dataSource.binaryPath, '/restored/yt-dlp');
        verify(() => binaryManager.triggerRepair(BinaryType.ytDlp)).called(1);
      },
    );

    test(
      'returns null when yt-dlp repair fails so caller surfaces terminal error',
      () async {
        when(
          () => binaryManager.getBinaryPath(BinaryType.ytDlp),
        ).thenAnswer((_) async => null);
        when(
          () => binaryManager.triggerRepair(BinaryType.ytDlp),
        ).thenAnswer((_) async => false);

        final path = await dataSource.ensureYtdlpBinaryReadyForTest();

        expect(path, isNull);
        expect(dataSource.binaryPath, isNull);
        verify(() => binaryManager.triggerRepair(BinaryType.ytDlp)).called(1);
      },
    );

    test(
      'download stream fails before subprocess logging when yt-dlp repair fails',
      () async {
        final tempSupport = await Directory.systemTemp.createTemp(
          'ytdlp_repair_fail_test_',
        );
        final originalDebugPrint = debugPrint;
        final logs = <String>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async {
                if (call.method == 'getApplicationSupportDirectory') {
                  return tempSupport.path;
                }
                return null;
              },
            );
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };

        addTearDown(() async {
          debugPrint = originalDebugPrint;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          if (await tempSupport.exists()) {
            await tempSupport.delete(recursive: true);
          }
        });

        when(() => binaryManager.initialize()).thenAnswer((_) async {});
        when(
          () => binaryManager.getBinaryPath(BinaryType.ytDlp),
        ).thenAnswer((_) async => null);
        when(
          () => binaryManager.getBinaryPath(BinaryType.ffmpeg),
        ).thenAnswer((_) async => '/ffmpeg');
        when(
          () => binaryManager.getBinaryPath(BinaryType.deno),
        ).thenAnswer((_) async => null);
        when(
          () => binaryManager.triggerRepair(BinaryType.ytDlp),
        ).thenAnswer((_) async => false);

        final events =
            await dataSource
                .downloadWithProgress(
                  url: 'https://example.com/video',
                  outputDir: tempSupport.path,
                )
                .toList();

        expect(events, hasLength(1));
        final error = events.single as YtDlpDownloadError;
        expect(error.error.message, YtDlpDataSource.ytdlpBinaryMissingMessage);
        expect(
          logs,
          isNot(
            contains(
              predicate<String>(
                (line) =>
                    line.contains('Starting download subprocess') ||
                    line.contains('Command: null'),
              ),
            ),
          ),
        );
        verify(() => binaryManager.triggerRepair(BinaryType.ytDlp)).called(1);
      },
    );
  });
}
