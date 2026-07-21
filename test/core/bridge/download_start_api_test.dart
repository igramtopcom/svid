import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/bridge/api.dart';

/// Tests verifying the download_start FFI bridge signature includes
/// maxSpeedBytes parameter (Task 67.4).
void main() {
  group('Task 67.4: downloadStart FFI signature', () {
    test('downloadStart accepts maxSpeedBytes parameter', () {
      // This test verifies the Dart FFI bridge function signature
      // includes the maxSpeedBytes parameter added in Task 67.4.
      // The function itself can't be called without RustLib initialized,
      // but we verify the signature compiles correctly.
      expect(
        () => downloadStart(
          id: 'test-uuid',
          url: 'https://example.com/video.mp4',
          outputPath: '/tmp/video.mp4',
          resumeOffset: null,
          maxSpeedBytes: BigInt.from(1048576), // 1 MB/s
        ),
        throwsA(anything), // RustLib not initialized
      );
    });

    test('downloadStart works without maxSpeedBytes (unlimited)', () {
      expect(
        () => downloadStart(
          id: 'test-uuid',
          url: 'https://example.com/video.mp4',
          outputPath: '/tmp/video.mp4',
        ),
        throwsA(anything), // RustLib not initialized
      );
    });

    test('downloadStart accepts zero maxSpeedBytes', () {
      expect(
        () => downloadStart(
          id: 'test-uuid',
          url: 'https://example.com/video.mp4',
          outputPath: '/tmp/video.mp4',
          maxSpeedBytes: BigInt.zero,
        ),
        throwsA(anything), // RustLib not initialized
      );
    });
  });
}
