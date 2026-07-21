import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ssvid/features/player/data/datasources/ffmpeg_datasource.dart';
import 'package:ssvid/features/player/domain/services/thumbnail_preview_service.dart';

class _MockFFmpegDatasource extends Mock implements FFmpegDatasource {}

void main() {
  late _MockFFmpegDatasource mockFFmpeg;
  late ThumbnailPreviewService service;

  setUp(() {
    mockFFmpeg = _MockFFmpegDatasource();
    service = ThumbnailPreviewService(mockFFmpeg);
  });

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  tearDown(() => service.dispose());

  // ── isAudioOnlyByExtension ─────────────────────────────────────────────

  group('isAudioOnlyByExtension', () {
    test('returns true for .mp3', () {
      expect(ThumbnailPreviewService.isAudioOnlyByExtension('/music/track.mp3'), isTrue);
    });

    test('returns true for .flac', () {
      expect(ThumbnailPreviewService.isAudioOnlyByExtension('/music/track.flac'), isTrue);
    });

    test('returns true for all audio extensions', () {
      for (final ext in ['.mp3', '.m4a', '.flac', '.opus', '.ogg', '.wav', '.aac']) {
        expect(
          ThumbnailPreviewService.isAudioOnlyByExtension('/file$ext'),
          isTrue,
          reason: ext,
        );
      }
    });

    test('returns false for .mp4', () {
      expect(ThumbnailPreviewService.isAudioOnlyByExtension('/video/clip.mp4'), isFalse);
    });

    test('returns false for .mkv', () {
      expect(ThumbnailPreviewService.isAudioOnlyByExtension('/video/movie.mkv'), isFalse);
    });

    test('returns false for file with no extension', () {
      expect(ThumbnailPreviewService.isAudioOnlyByExtension('/bin/data'), isFalse);
    });
  });

  // ── getFrameAt — cache hit ─────────────────────────────────────────────

  group('getFrameAt', () {
    const path = '/videos/test.mp4';
    final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]); // JPEG magic bytes

    test('calls FFmpeg on cache miss', () async {
      when(
        () => mockFFmpeg.extractFrameAt(path, const Duration(seconds: 5),
            timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => fakeBytes);

      final result = await service.getFrameAt(path, const Duration(seconds: 5));

      expect(result, equals(fakeBytes));
      verify(
        () => mockFFmpeg.extractFrameAt(path, const Duration(seconds: 5),
            timeout: any(named: 'timeout')),
      ).called(1);
    });

    test('returns null when FFmpeg returns null', () async {
      when(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => null);

      final result = await service.getFrameAt(path, const Duration(seconds: 3));
      expect(result, isNull);
    });

    test('caches result — FFmpeg called only once for same second', () async {
      when(
        () => mockFFmpeg.extractFrameAt(path, const Duration(seconds: 10),
            timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => fakeBytes);

      await service.getFrameAt(path, const Duration(seconds: 10));
      await service.getFrameAt(path, const Duration(seconds: 10));
      await service.getFrameAt(path, const Duration(seconds: 10, milliseconds: 500));

      // All three map to secondKey=10 → single FFmpeg call
      verify(
        () => mockFFmpeg.extractFrameAt(path, const Duration(seconds: 10),
            timeout: any(named: 'timeout')),
      ).called(1);
    });

    test('rounds position to nearest second for cache key', () async {
      when(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => fakeBytes);

      // 7200ms and 7800ms both round to secondKey=7
      await service.getFrameAt(path, const Duration(milliseconds: 7200));
      await service.getFrameAt(path, const Duration(milliseconds: 7800));

      verify(
        () => mockFFmpeg.extractFrameAt(path, const Duration(seconds: 7),
            timeout: any(named: 'timeout')),
      ).called(1);
    });

    test('returns null after dispose', () async {
      service.dispose();
      final result = await service.getFrameAt(path, const Duration(seconds: 1));
      expect(result, isNull);
      verifyNever(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      );
    });
  });

  // ── prewarm ────────────────────────────────────────────────────────────

  group('prewarm', () {
    const path = '/videos/test.mp4';
    final fakeBytes = Uint8List.fromList([0xFF, 0xD8]);

    test('calls FFmpeg for 10 evenly-spaced frames', () async {
      when(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => fakeBytes);

      await service.prewarm(path, const Duration(seconds: 110));

      // 10 frames, none at 0 or end
      verify(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).called(10);
    });

    test('does nothing for audio-only extension', () async {
      await service.prewarm('/music/track.mp3', const Duration(minutes: 5));
      verifyNever(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      );
    });

    test('does nothing for zero duration', () async {
      await service.prewarm(path, Duration.zero);
      verifyNever(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      );
    });

    test('stops if disposed mid-prewarm', () async {
      var callCount = 0;
      when(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 3) service.dispose();
        return fakeBytes;
      });

      await service.prewarm(path, const Duration(seconds: 200));
      // After dispose, loop exits — fewer than 10 calls
      expect(callCount, lessThan(10));
    });
  });

  // ── LRU eviction ──────────────────────────────────────────────────────

  group('LRU eviction', () {
    test('evicts oldest entry when cache exceeds 60', () async {
      var callCount = 0;
      when(
        () => mockFFmpeg.extractFrameAt(any(), any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async {
        callCount++;
        return Uint8List.fromList([callCount]);
      });

      // Fill cache with 60 unique seconds
      for (int i = 0; i < 60; i++) {
        await service.getFrameAt('/v.mp4', Duration(seconds: i));
      }
      expect(callCount, 60);

      // Add 61st entry — oldest (second=0) should be evicted
      await service.getFrameAt('/v.mp4', const Duration(seconds: 60));
      expect(callCount, 61);

      // Fetching second=0 again should hit FFmpeg (evicted)
      await service.getFrameAt('/v.mp4', Duration.zero);
      expect(callCount, 62);
    });
  });
}
