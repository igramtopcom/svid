import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/binaries/binary_type.dart';
import 'package:ssvid/features/downloads/domain/services/file_integrity_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_integrity_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // Helper: create a temp file with given bytes
  Future<File> createFile(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  // Null resolver: simulates FFmpeg not installed
  Future<String?> nullResolver(BinaryType _) async => null;

  // ──────────────────────────────────────────────────────────────────────────
  // Basic checks (file existence / size)
  // ──────────────────────────────────────────────────────────────────────────

  group('basic checks', () {
    test('returns failed when file does not exist', () async {
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile('${tempDir.path}/nonexistent.mp4');
      expect(result.isValid, isFalse);
      expect(result.reason, contains('does not exist'));
    });

    test('returns failed when file is empty', () async {
      final file = await createFile('empty.mp4', []);
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('empty'));
    });

    test('non-media file with content passes', () async {
      final file = await createFile('subtitle.srt', [0x31, 0x0A]);
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      expect(result.isValid, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Video — FFmpeg unavailable (fail open)
  // ──────────────────────────────────────────────────────────────────────────

  group('video container check', () {
    test('fails open when FFmpeg binary is not available', () async {
      final file = await createFile('video.mp4', List.filled(100, 0x00));
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      // No FFmpeg → fail open (ok)
      expect(result.isValid, isTrue);
    });

    test('fails open when FFmpeg path does not exist on disk', () async {
      final file = await createFile('video.mkv', List.filled(100, 0x00));
      final svc = FileIntegrityService.forTest(
        (_) async => '/nonexistent/ffmpeg',
      );
      final result = await svc.verifyFile(file.path);
      // Exception during Process.run → fail open
      expect(result.isValid, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Audio — magic byte checks
  // ──────────────────────────────────────────────────────────────────────────

  group('MP3 magic bytes', () {
    test('accepts ID3-tagged MP3 (49 44 33)', () async {
      final file = await createFile('audio.mp3', [
        0x49,
        0x44,
        0x33,
        0x03,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('accepts raw MPEG sync MP3 (FF FB)', () async {
      final file = await createFile('audio.mp3', [0xFF, 0xFB, 0x90, 0x64]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('accepts MPEG sync FF F3', () async {
      final file = await createFile('audio.mp3', [0xFF, 0xF3, 0x90, 0x64]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('rejects invalid MP3 magic bytes', () async {
      final file = await createFile('audio.mp3', [
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('.mp3'));
    });
  });

  group('WAV magic bytes', () {
    test('accepts RIFF WAV (52 49 46 46)', () async {
      final file = await createFile('audio.wav', [
        0x52,
        0x49,
        0x46,
        0x46,
        0xE4,
        0x38,
        0x00,
        0x00,
        0x57,
        0x41,
        0x56,
        0x45,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('rejects invalid WAV header', () async {
      final file = await createFile('audio.wav', [0x00, 0x00, 0x00, 0x00]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isFalse);
    });
  });

  group('FLAC magic bytes', () {
    test('accepts fLaC header (66 4C 61 43)', () async {
      final file = await createFile('audio.flac', [
        0x66,
        0x4C,
        0x61,
        0x43,
        0x00,
        0x00,
        0x00,
        0x22,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('rejects invalid FLAC header', () async {
      final file = await createFile('audio.flac', [0xDE, 0xAD, 0xBE, 0xEF]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isFalse);
    });
  });

  group('OGG magic bytes', () {
    test('accepts OggS header (4F 67 67 53)', () async {
      final file = await createFile('audio.ogg', [
        0x4F,
        0x67,
        0x67,
        0x53,
        0x00,
        0x02,
        0x00,
        0x00,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });
  });

  group('M4A ftyp atom', () {
    // ISO BMFF: bytes 0-3 = box size, bytes 4-7 = 'ftyp' (66 74 79 70)
    test('accepts M4A with ftyp at offset 4', () async {
      // Realistic M4A header: size=28, 'ftyp', 'M4A ', version, compatible brands
      final bytes = Uint8List(28);
      bytes[0] = 0x00;
      bytes[1] = 0x00;
      bytes[2] = 0x00;
      bytes[3] = 0x1C; // size=28
      bytes[4] = 0x66;
      bytes[5] = 0x74;
      bytes[6] = 0x79;
      bytes[7] = 0x70; // ftyp
      bytes[8] = 0x4D;
      bytes[9] = 0x34;
      bytes[10] = 0x41;
      bytes[11] = 0x20; // M4A_
      final file = await createFile('audio.m4a', bytes);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('rejects M4A without ftyp atom', () async {
      final file = await createFile(
        'audio.m4a',
        [0x00, 0x00, 0x00, 0x08, 0x6D, 0x64, 0x61, 0x74], // mdat, not ftyp
      );
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('M4A'));
    });

    test('rejects M4A file shorter than 8 bytes', () async {
      final file = await createFile('audio.m4a', [0x00, 0x00, 0x00]);
      final svc = FileIntegrityService.forTest(nullResolver);
      final result = await svc.verifyFile(file.path);
      expect(result.isValid, isFalse);
    });
  });

  group('WMA magic bytes', () {
    test('accepts WMA ASF header (30 26 B2 75)', () async {
      final file = await createFile('audio.wma', [
        0x30,
        0x26,
        0xB2,
        0x75,
        0x8E,
        0x66,
        0xCF,
        0x11,
      ]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });
  });

  group('AAC magic bytes', () {
    test('accepts ADTS AAC-LC (FF F1)', () async {
      final file = await createFile('audio.aac', [0xFF, 0xF1, 0x50, 0x80]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });

    test('accepts ADTS AAC mpeg4 (FF F9)', () async {
      final file = await createFile('audio.aac', [0xFF, 0xF9, 0x50, 0x80]);
      final svc = FileIntegrityService.forTest(nullResolver);
      expect((await svc.verifyFile(file.path)).isValid, isTrue);
    });
  });

  // The "1440p+ download has no audio" customer report is the canonical
  // failure mode these tests pin: yt-dlp picks VP9+Opus DASH for high-res
  // YouTube, ffmpeg's MP4 merge cannot embed Opus, the audio track is
  // silently dropped, and the user gets a video file with no sound. The
  // integrity check must catch that — not by rerunning ffprobe, but by
  // inspecting the JSON ffprobe already produced.
  group('ffprobe stream presence — catches silent merge fail', () {
    final svc = FileIntegrityService.forTest(nullResolver);

    test('passes when both video and audio streams are present', () {
      const ffprobeJson = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "120.000"}
}''';
      final result = svc.parseStreamsAndValidateForTest(
        ffprobeJson,
        '/tmp/video_1080p.mp4',
      );
      expect(result.isValid, isTrue);
    });

    test('FAILS FATAL when video file has no audio stream', () {
      // Smoking-gun shape — video-only output produced by a failed
      // VP9+Opus → MP4 merge. Must be FATAL so the orchestrator marks
      // the download failed instead of "completed" with a silent file.
      const ffprobeJson = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "vp9"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "120.000"}
}''';
      final result = svc.parseStreamsAndValidateForTest(
        ffprobeJson,
        '/tmp/video_1440p.mp4',
      );
      expect(result.isValid, isFalse);
      expect(
        result.isFatal,
        isTrue,
        reason:
            'audio missing must be FATAL so start_download_usecase '
            'fails the download instead of completing it as silent file',
      );
      expect(result.reason, contains('no audio'));
      expect(
        result.reason,
        contains('MKV'),
        reason: 'message must steer the user to the working path (MKV)',
      );
    });

    test('passes when video-only output intentionally has no audio', () {
      const ffprobeJson = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "vp9"}
  ],
  "format": {"format_name": "webm", "duration": "120.000"}
}''';
      final result = svc.parseStreamsAndValidateForTest(
        ffprobeJson,
        '/tmp/video_only.webm',
        requireAudioStream: false,
      );
      expect(result.isValid, isTrue);
      expect(result.isFatal, isFalse);
    });

    test(
      'FAILS FATAL when file has no video stream (audio-only mislabeled)',
      () {
        const ffprobeJson = '''
{
  "streams": [
    {"codec_type": "audio", "codec_name": "aac"}
  ]
}''';
        final result = svc.parseStreamsAndValidateForTest(
          ffprobeJson,
          '/tmp/broken.mp4',
        );
        expect(result.isValid, isFalse);
        expect(result.isFatal, isTrue);
        expect(result.reason, contains('no video stream'));
      },
    );

    test('passes (fail open) on malformed JSON', () {
      final result = svc.parseStreamsAndValidateForTest(
        'this-is-not-json',
        '/tmp/x.mp4',
      );
      expect(
        result.isValid,
        isTrue,
        reason: 'environmental issues must NOT block downloads',
      );
    });

    test('passes (fail open) when streams key is missing', () {
      // Older ffprobe builds and edge-case containers may omit `streams`
      // even on valid files. Don't second-guess.
      const ffprobeJson = '{"format": {"format_name": "mov,mp4"}}';
      final result = svc.parseStreamsAndValidateForTest(
        ffprobeJson,
        '/tmp/x.mp4',
      );
      expect(result.isValid, isTrue);
    });

    // DL-011: truncated-but-has-video slip-through (the "completed but
    // plays empty, few-dozen KB" defect from the 17x4K Windows test).
    test('DL-011 FATAL: video present but duration < 0.5s (truncated)', () {
      const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "0.083"}
}''';
      final r = svc.parseStreamsAndValidateForTest(json, '/tmp/partial.mp4');
      expect(r.isValid, isFalse);
      expect(r.isFatal, isTrue);
      expect(r.reason, contains('incomplete'));
    });

    test('DL-011 FATAL: unmeasurable duration AND file < 50KB (tiny stub)', () {
      const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "N/A"}
}''';
      final r = svc.parseStreamsAndValidateForTest(
        json,
        '/tmp/stub.mp4',
        fileSize: 30 * 1024,
      );
      expect(r.isValid, isFalse);
      expect(r.isFatal, isTrue);
      expect(r.reason, contains('incomplete'));
    });

    test('DL-011 fail-open: unmeasurable duration but reasonably-sized file',
        () {
      const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4"}
}''';
      final r = svc.parseStreamsAndValidateForTest(
        json,
        '/tmp/ok.mp4',
        fileSize: 5 * 1024 * 1024,
      );
      expect(
        r.isValid,
        isTrue,
        reason: 'unmeasurable duration + sane size must NOT be sunk',
      );
    });

    test('DL-011 regression: a real short clip (2s, 200KB) still passes', () {
      const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "2.000"}
}''';
      final r = svc.parseStreamsAndValidateForTest(
        json,
        '/tmp/short.mp4',
        fileSize: 200 * 1024,
      );
      expect(r.isValid, isTrue);
    });

    test('DL-011 boundary: duration exactly 0.5s passes (>= floor)', () {
      const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"format_name": "mov,mp4", "duration": "0.5"}
}''';
      final r = svc.parseStreamsAndValidateForTest(json, '/tmp/edge.mp4');
      expect(r.isValid, isTrue);
    });

    test('multiple audio streams (e.g. multi-language) still pass', () {
      const ffprobeJson = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "audio", "codec_name": "aac"},
    {"codec_type": "audio", "codec_name": "aac"},
    {"codec_type": "subtitle", "codec_name": "mov_text"}
  ]
}''';
      final result = svc.parseStreamsAndValidateForTest(
        ffprobeJson,
        '/tmp/multi_audio.mp4',
      );
      expect(result.isValid, isTrue);
    });
  });
}
