import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';

void main() {
  group('YtDlpDataSource audio quality args', () {
    test('uses best-quality mode when no bitrate is selected', () {
      expect(YtDlpDataSource.audioQualityArgForTest(null), '0');
      expect(YtDlpDataSource.audioQualityArgForTest(0), '0');
      expect(YtDlpDataSource.audioQualityArgForTest(-1), '0');
    });

    test('emits explicit kbps target for dialog bitrate selections', () {
      expect(YtDlpDataSource.audioQualityArgForTest(320), '320K');
      expect(YtDlpDataSource.audioQualityArgForTest(192), '192K');
      expect(YtDlpDataSource.audioQualityArgForTest(64), '64K');
    });

    test('enforces explicit lossy bitrate targets after stream-copy', () {
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'm4a',
          audioBitrateKbps: 320,
        ),
        isTrue,
      );
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'mp3',
          audioBitrateKbps: 128,
        ),
        isTrue,
      );
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'opus',
          audioBitrateKbps: 192,
        ),
        isTrue,
      );
    });

    test('does not enforce bitrate for best-quality or lossless outputs', () {
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'm4a',
          audioBitrateKbps: null,
        ),
        isFalse,
      );
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'wav',
          audioBitrateKbps: 320,
        ),
        isFalse,
      );
      expect(
        YtDlpDataSource.shouldEnforceAudioBitrateForTest(
          audioFormat: 'flac',
          audioBitrateKbps: 320,
        ),
        isFalse,
      );
    });

    test('uses bitrate tolerance to avoid redundant recodes', () {
      expect(
        YtDlpDataSource.audioBitrateCloseEnoughForTest(
          actualKbps: 128,
          targetKbps: 128,
        ),
        isTrue,
      );
      expect(
        YtDlpDataSource.audioBitrateCloseEnoughForTest(
          actualKbps: 128,
          targetKbps: 320,
        ),
        isFalse,
      );
    });

    test(
      'Wave B (AUD-4): bitrate is a CEILING — never up-convert a '
      'stream-copy (m4a-from-AAC at 128k stays copied even with the '
      '320k dialog default; the old check re-encoded it to a '
      'fabricated 320k with generation loss + 2.4x bloat)',
      () {
        // actual BELOW target → keep the copy (the broken cell, fixed)
        expect(
          YtDlpDataSource.shouldRecodeAudioBitrateForTest(
            audioFormat: 'm4a',
            audioBitrateKbps: 320,
            actualBitrateKbps: 128,
          ),
          isFalse,
        );
        // exact match → keep
        expect(
          YtDlpDataSource.shouldRecodeAudioBitrateForTest(
            audioFormat: 'm4a',
            audioBitrateKbps: 128,
            actualBitrateKbps: 128,
          ),
          isFalse,
        );
        // actual ABOVE ceiling beyond tolerance → recode DOWN (the
        // genuine size contract survives)
        expect(
          YtDlpDataSource.shouldRecodeAudioBitrateForTest(
            audioFormat: 'm4a',
            audioBitrateKbps: 128,
            actualBitrateKbps: 320,
          ),
          isTrue,
        );
        // within tolerance above ceiling (max(6, 8%) = 10 at 128k) → keep
        expect(
          YtDlpDataSource.shouldRecodeAudioBitrateForTest(
            audioFormat: 'm4a',
            audioBitrateKbps: 128,
            actualBitrateKbps: 136,
          ),
          isFalse,
        );
        // probe failure fails OPEN — a 15s ffprobe timeout must never
        // trigger a blind full re-encode
        expect(
          YtDlpDataSource.shouldRecodeAudioBitrateForTest(
            audioFormat: 'm4a',
            audioBitrateKbps: 320,
            actualBitrateKbps: null,
          ),
          isFalse,
        );
      },
    );

    test('builds ffmpeg recode args for AAC targets', () {
      expect(
        YtDlpDataSource.audioBitrateRecodeArgsForTest(
          inputPath: '/tmp/in.m4a',
          outputPath: '/tmp/out.m4a',
          audioFormat: 'm4a',
          bitrateKbps: 128,
        ),
        containsAllInOrder([
          '-i',
          '/tmp/in.m4a',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '/tmp/out.m4a',
        ]),
      );
    });

    test('maps AAC audio extract output to the m4a scan extension', () {
      expect(YtDlpDataSource.audioScanExtensionForTest('aac'), 'm4a');
      expect(YtDlpDataSource.audioScanExtensionForTest('m4a'), 'm4a');
      expect(YtDlpDataSource.audioScanExtensionForTest('mp3'), 'mp3');
    });
  });
}
