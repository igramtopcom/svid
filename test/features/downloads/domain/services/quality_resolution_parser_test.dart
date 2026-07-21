import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/services/quality_resolution_parser.dart';

void main() {
  Quality video(String text) {
    return Quality(
      qualityText: text,
      size: '10 MB',
      encryptedUrl: 'ytdlp:$text',
      mediaType: MediaType.video,
    );
  }

  Quality audio(String text) {
    return Quality(
      qualityText: text,
      size: '5 MB',
      encryptedUrl: 'ytdlp:$text',
      mediaType: MediaType.audio,
    );
  }

  group('QualityResolutionParser.parseHeight', () {
    test('parses p-suffixed resolutions', () {
      expect(QualityResolutionParser.parseHeight('2160p60 HDR'), 2160);
      expect(QualityResolutionParser.parseHeight('MP4 1440p'), 1440);
      expect(QualityResolutionParser.parseHeight('1080p'), 1080);
    });

    test('parses K-resolution labels from extractor display text', () {
      expect(QualityResolutionParser.parseHeight('Best (4K)'), 2160);
      expect(QualityResolutionParser.parseHeight('Best (2K)'), 1440);
      expect(QualityResolutionParser.parseHeight('8K Ultra'), 4320);
      expect(QualityResolutionParser.parseHeight('4K60 HDR'), 2160);
    });

    test('parses dimensions using shorter side for portrait safety', () {
      expect(QualityResolutionParser.parseHeight('Video [3840x2160]'), 2160);
      expect(QualityResolutionParser.parseHeight('Video [1080x1920]'), 1080);
      expect(QualityResolutionParser.parseHeight('Video [2160×3840]'), 2160);
    });

    test('returns null for non-resolution labels', () {
      expect(
        QualityResolutionParser.parseHeight('Audio Stream - Opus'),
        isNull,
      );
      expect(QualityResolutionParser.parseHeight('Best'), isNull);
      expect(QualityResolutionParser.parseHeight(''), isNull);
    });
  });

  group('QualityResolutionParser.isAboveFreeLimit', () {
    test('blocks video labels above 1080p including Best 4K', () {
      expect(
        QualityResolutionParser.isAboveFreeLimit(video('Best (4K)')),
        true,
      );
      expect(QualityResolutionParser.isAboveFreeLimit(video('1440p')), true);
    });

    test('allows 1080p video and ignores audio labels', () {
      expect(QualityResolutionParser.isAboveFreeLimit(video('1080p')), false);
      expect(
        QualityResolutionParser.isAboveFreeLimit(audio('Audio 4Kbps')),
        false,
      );
    });
  });
}
