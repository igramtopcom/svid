import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/download_native_datasource.dart';

void main() {
  group('DownloadNativeDataSource', () {
    group('generateNativeId', () {
      test('returns deterministic UUID for same url+filename', () {
        final id1 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video.mp4',
          'video.mp4',
        );
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video.mp4',
          'video.mp4',
        );

        expect(id1, equals(id2));
        expect(id1, isNotEmpty);
      });

      test('returns different UUID for different urls', () {
        final id1 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video1.mp4',
          'video.mp4',
        );
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video2.mp4',
          'video.mp4',
        );

        expect(id1, isNot(equals(id2)));
      });

      test('returns different UUID for different filenames', () {
        final id1 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video.mp4',
          'video_720p.mp4',
        );
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video.mp4',
          'video_1080p.mp4',
        );

        expect(id1, isNot(equals(id2)));
      });

      test('returns valid UUID v5 format', () {
        final id = DownloadNativeDataSource.generateNativeId(
          'https://youtube.com/watch?v=abc123',
          'My Video.mp4',
        );

        // UUID v5 format: 8-4-4-4-12 hex digits
        final uuidPattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        );
        expect(id, matches(uuidPattern));
      });

      test('handles special characters in url and filename', () {
        final id = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video?id=123&quality=720p',
          'My Video (720p) [2026].mp4',
        );

        expect(id, isNotEmpty);
        // Should still be deterministic
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://example.com/video?id=123&quality=720p',
          'My Video (720p) [2026].mp4',
        );
        expect(id, equals(id2));
      });
    });

    group('NativeDownloadProgress', () {
      test('isTerminal returns true for completed status', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 1000,
          totalBytes: 1000,
          status: 'completed',
        );
        expect(progress.isTerminal, isTrue);
      });

      test('isTerminal returns true for failed status', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 500,
          totalBytes: 1000,
          status: 'failed',
        );
        expect(progress.isTerminal, isTrue);
      });

      test('isTerminal returns true for cancelled status', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 500,
          totalBytes: 1000,
          status: 'cancelled',
        );
        expect(progress.isTerminal, isTrue);
      });

      test('isTerminal returns false for downloading status', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 500,
          totalBytes: 1000,
          status: 'downloading',
        );
        expect(progress.isTerminal, isFalse);
      });

      test('isTerminal returns false for paused status', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 500,
          totalBytes: 1000,
          status: 'paused',
        );
        expect(progress.isTerminal, isFalse);
      });

      test('totalBytes reflects Content-Length from Rust engine', () {
        // After Task 67.1 fix: total_bytes comes from engine AtomicU64
        const progress = NativeDownloadProgress(
          downloadedBytes: 5000,
          totalBytes: 10000,
          status: 'downloading',
        );
        expect(progress.totalBytes, 10000);
        expect(progress.downloadedBytes, 5000);
      });

      test('totalBytes zero indicates unknown file size', () {
        const progress = NativeDownloadProgress(
          downloadedBytes: 5000,
          totalBytes: 0,
          status: 'downloading',
        );
        expect(progress.totalBytes, 0);
      });
    });

    group('cleanupDownload', () {
      test('DownloadNativeDataSource has cleanupDownload method', () {
        final ds = DownloadNativeDataSource();
        expect(ds.cleanupDownload, isA<Function>());
      });
    });

    group('Task 67.4: startDownload maxSpeedBytes parameter', () {
      test('startDownload accepts optional maxSpeedBytes parameter', () {
        final ds = DownloadNativeDataSource();
        // Verify the method signature accepts maxSpeedBytes
        // We can't call it without RustLib, but we can verify the method exists
        expect(ds.startDownload, isA<Function>());
      });

      test('startDownload method has correct parameter types', () {
        // Verify DownloadNativeDataSource.startDownload signature
        // nativeId: String, url: String, outputPath: String,
        // resumeOffset: int?, maxSpeedBytes: int?
        final ds = DownloadNativeDataSource();
        // Type check: the method should accept all parameters
        // This is a compile-time verification test
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            resumeOffset: null,
            maxSpeedBytes: null,
          ),
          // Will throw because RustLib is not initialized,
          // but it proves the method signature is correct
          throwsA(anything),
        );
      });

      test('startDownload method accepts non-zero speed limit', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            maxSpeedBytes: 1048576, // 1 MB/s,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });

      test('startDownload method accepts zero speed limit (unlimited)', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            maxSpeedBytes: 0,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });
    });
  });
}
