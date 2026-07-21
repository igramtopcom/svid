import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/presentation/widgets/media_info_helpers.dart';

void main() {
  group('formatCodecName', () {
    test('returns H.264 for h264', () {
      expect(formatCodecName('h264'), 'H.264');
    });

    test('returns VP9 for vp9', () {
      expect(formatCodecName('vp9'), 'VP9');
    });

    test('returns AV1 for av1', () {
      expect(formatCodecName('av1'), 'AV1');
    });

    test('returns AAC for aac', () {
      expect(formatCodecName('aac'), 'AAC');
    });

    test('returns Opus for opus', () {
      expect(formatCodecName('opus'), 'Opus');
    });

    test('returns — for null', () {
      expect(formatCodecName(null), '—');
    });

    test('returns — for empty string', () {
      expect(formatCodecName(''), '—');
    });

    test('returns uppercase for unknown codec', () {
      expect(formatCodecName('webm'), 'WEBM');
    });

    test('is case-insensitive', () {
      expect(formatCodecName('H264'), 'H.264');
      expect(formatCodecName('VP9'), 'VP9');
    });

    test('returns H.265 for hevc', () {
      expect(formatCodecName('hevc'), 'H.265');
    });
  });

  group('formatBitrate', () {
    test('formats normal bitrate with commas', () {
      expect(formatBitrate(5200), '5,200 kbps');
    });

    test('formats small bitrate without commas', () {
      expect(formatBitrate(320), '320 kbps');
    });

    test('returns — for null', () {
      expect(formatBitrate(null), '—');
    });

    test('returns — for zero', () {
      expect(formatBitrate(0), '—');
    });

    test('returns — for negative', () {
      expect(formatBitrate(-100), '—');
    });
  });

  group('formatSampleRate', () {
    test('formats 48000 Hz with commas', () {
      expect(formatSampleRate(48000), '48,000 Hz');
    });

    test('formats 44100 Hz with commas', () {
      expect(formatSampleRate(44100), '44,100 Hz');
    });

    test('returns — for null', () {
      expect(formatSampleRate(null), '—');
    });

    test('returns — for zero', () {
      expect(formatSampleRate(0), '—');
    });
  });

  group('formatResolution', () {
    test('formats 1920x1080', () {
      expect(formatResolution(1920, 1080), '1920×1080');
    });

    test('formats 3840x2160', () {
      expect(formatResolution(3840, 2160), '3840×2160');
    });

    test('returns — for null width', () {
      expect(formatResolution(null, 1080), '—');
    });

    test('returns — for null height', () {
      expect(formatResolution(1920, null), '—');
    });

    test('returns — for both null', () {
      expect(formatResolution(null, null), '—');
    });

    test('returns — for zero dimensions', () {
      expect(formatResolution(0, 0), '—');
    });
  });

  group('formatChannels', () {
    test('formats stereo with count', () {
      expect(formatChannels('stereo', 2), 'Stereo (2ch)');
    });

    test('formats mono with count', () {
      expect(formatChannels('mono', 1), 'Mono (1ch)');
    });

    test('formats layout only (no count)', () {
      expect(formatChannels('stereo', null), 'Stereo');
    });

    test('formats count only (no layout)', () {
      expect(formatChannels(null, 6), '6ch');
    });

    test('returns — for both null', () {
      expect(formatChannels(null, null), '—');
    });

    test('capitalizes layout', () {
      expect(formatChannels('surround', 6), 'Surround (6ch)');
    });
  });

  group('formatFileSize', () {
    test('formats GB', () {
      expect(formatFileSize(1073741824), '1.0 GB');
    });

    test('formats MB', () {
      expect(formatFileSize(5242880), '5.0 MB');
    });

    test('formats KB', () {
      expect(formatFileSize(10240), '10.0 KB');
    });

    test('formats bytes', () {
      expect(formatFileSize(512), '512 B');
    });

    test('returns — for null', () {
      expect(formatFileSize(null), '—');
    });

    test('returns — for zero', () {
      expect(formatFileSize(0), '—');
    });
  });
}
