import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/services/quality_fallback_service.dart';

void main() {
  late QualityFallbackService service;

  setUp(() {
    service = const QualityFallbackService();
  });

  Quality video(String text, {String? vcodec, double? tbr, double? fps}) {
    return Quality(
      qualityText: text,
      size: '10 MB',
      encryptedUrl: 'ytdlp:$text',
      mediaType: MediaType.video,
      vcodec: vcodec,
      tbr: tbr,
      fps: fps,
    );
  }

  Quality audio(String text, {String? acodec, double? tbr}) {
    return Quality(
      qualityText: text,
      size: '5 MB',
      encryptedUrl: 'ytdlp:$text',
      mediaType: MediaType.audio,
      acodec: acodec,
      tbr: tbr,
    );
  }

  // ==================== parseHeight ====================

  group('parseHeight', () {
    test('parses standard resolution strings', () {
      expect(QualityFallbackService.parseHeight('MP4 1080p [1920x1080]'), 1080);
      expect(QualityFallbackService.parseHeight('720p'), 720);
      expect(QualityFallbackService.parseHeight('480p H.264'), 480);
      expect(QualityFallbackService.parseHeight('360p'), 360);
      expect(QualityFallbackService.parseHeight('2160p'), 2160);
    });

    test('parses K-resolution shortcuts', () {
      expect(QualityFallbackService.parseHeight('4K HDR'), 2160);
      expect(QualityFallbackService.parseHeight('Best (4K)'), 2160);
      expect(QualityFallbackService.parseHeight('2K Video'), 1440);
      expect(QualityFallbackService.parseHeight('8K Ultra'), 4320);
    });

    test('parses dimension strings using the shorter side', () {
      expect(QualityFallbackService.parseHeight('Video [3840x2160]'), 2160);
      expect(QualityFallbackService.parseHeight('Video [1080x1920]'), 1080);
    });

    test('returns null for non-resolution strings', () {
      expect(QualityFallbackService.parseHeight('Audio Only'), isNull);
      expect(QualityFallbackService.parseHeight('Best'), isNull);
      expect(QualityFallbackService.parseHeight(''), isNull);
    });
  });

  // ==================== parseAudioBitrate ====================

  group('parseAudioBitrate', () {
    test('parses standard bitrate strings', () {
      expect(QualityFallbackService.parseAudioBitrate('MP3 320kbps'), 320);
      expect(QualityFallbackService.parseAudioBitrate('AAC 256k'), 256);
      expect(QualityFallbackService.parseAudioBitrate('128 kbps'), 128);
      expect(QualityFallbackService.parseAudioBitrate('192kb/s'), 192);
    });

    test('returns null for non-bitrate strings', () {
      expect(QualityFallbackService.parseAudioBitrate('Best Audio'), isNull);
      expect(QualityFallbackService.parseAudioBitrate('1080p'), isNull);
    });
  });

  // ==================== findBestMatch ====================

  group('findBestMatch', () {
    test('returns null for empty available list', () {
      final result = service.findBestMatch(video('1080p'), []);
      expect(result, isNull);
    });

    test('returns null when no same-mediaType qualities exist', () {
      final result = service.findBestMatch(video('1080p'), [
        audio('320kbps'),
        audio('256kbps'),
      ]);
      expect(result, isNull);
    });

    test('returns exact match with isFallback=false', () {
      final available = [
        video('720p', vcodec: 'h264'),
        video('1080p', vcodec: 'h264'),
        video('480p', vcodec: 'h264'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.isFallback, isFalse);
      expect(result.quality.qualityText, '1080p');
    });

    test('falls back to closest lower resolution (same codec)', () {
      final available = [
        video('720p', vcodec: 'h264'),
        video('480p', vcodec: 'h264'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
      expect(result.quality.qualityText, '720p');
      expect(result.reason, contains('1080p'));
      expect(result.reason, contains('720p'));
    });

    test('falls back to closest higher resolution when lower unavailable', () {
      final available = [
        video('1440p', vcodec: 'h264'),
        video('2160p', vcodec: 'h264'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
      expect(result.quality.qualityText, '1440p');
    });

    test('prefers same codec over different codec at same resolution', () {
      final available = [
        video('720p', vcodec: 'vp9'),
        video('720p', vcodec: 'h264'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.quality.vcodec, 'h264');
    });

    test('falls back to different codec when same codec unavailable', () {
      final available = [
        video('720p', vcodec: 'vp9'),
        video('480p', vcodec: 'vp9'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.quality.qualityText, '720p');
    });

    test('handles audio quality fallback', () {
      final available = [
        audio('MP3 256kbps', acodec: 'mp3', tbr: 256),
        audio('MP3 192kbps', acodec: 'mp3', tbr: 192),
        audio('MP3 128kbps', acodec: 'mp3', tbr: 128),
      ];

      final result = service.findBestMatch(
        audio('MP3 320kbps', acodec: 'mp3', tbr: 320),
        available,
      );
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
      expect(result.quality.qualityText, 'MP3 256kbps');
    });

    test('handles audio fallback with tbr when no bitrate in text', () {
      final available = [
        audio('Audio Medium', acodec: 'aac', tbr: 128),
        audio('Audio Low', acodec: 'aac', tbr: 64),
      ];

      final result = service.findBestMatch(
        audio('Audio High', acodec: 'aac', tbr: 256),
        available,
      );
      expect(result, isNotNull);
      expect(result!.quality.qualityText, 'Audio Medium');
    });

    test('returns first of same type for image/subtitle', () {
      final imageQuality = Quality(
        qualityText: 'Image HD',
        size: '2 MB',
        encryptedUrl: 'url1',
        mediaType: MediaType.image,
      );
      final available = [
        Quality(
          qualityText: 'Image SD',
          size: '1 MB',
          encryptedUrl: 'url2',
          mediaType: MediaType.image,
        ),
      ];

      final result = service.findBestMatch(imageQuality, available);
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
      expect(result.quality.qualityText, 'Image SD');
    });
  });

  // ==================== buildFallbackChain ====================

  group('buildFallbackChain', () {
    test('returns empty list for no matching mediaType', () {
      final chain = service.buildFallbackChain(video('1080p'), [
        audio('320kbps'),
      ]);
      expect(chain, isEmpty);
    });

    test('exact match is first in chain', () {
      final preferred = video('1080p', vcodec: 'h264');
      final available = [
        video('720p', vcodec: 'h264'),
        video('1080p', vcodec: 'h264'),
        video('480p', vcodec: 'vp9'),
      ];

      final chain = service.buildFallbackChain(preferred, available);
      expect(chain.length, 3);
      expect(chain.first.qualityText, '1080p');
    });

    test('orders by codec match then resolution proximity', () {
      final preferred = video('1080p', vcodec: 'h264');
      final available = [
        video('720p', vcodec: 'h264'),
        video('720p', vcodec: 'vp9'),
        video('480p', vcodec: 'h264'),
        video('480p', vcodec: 'vp9'),
      ];

      final chain = service.buildFallbackChain(preferred, available);
      expect(chain.length, 4);

      // h264 720p should be before vp9 720p (same resolution, codec match bonus)
      final h264_720 = chain.indexWhere(
        (q) => q.qualityText == '720p' && q.vcodec == 'h264',
      );
      final vp9_720 = chain.indexWhere(
        (q) => q.qualityText == '720p' && q.vcodec == 'vp9',
      );
      expect(h264_720, lessThan(vp9_720));
    });

    test('includes all candidates in chain', () {
      final available = [
        video('2160p'),
        video('1080p'),
        video('720p'),
        video('480p'),
        video('360p'),
      ];

      final chain = service.buildFallbackChain(video('1080p'), available);
      expect(chain.length, 5);
    });
  });

  // ==================== Edge Cases ====================

  group('edge cases', () {
    test('handles quality text without resolution', () {
      final available = [video('Best Quality'), video('Good Quality')];

      final result = service.findBestMatch(video('Best Quality'), available);
      expect(result, isNotNull);
      expect(result!.isFallback, isFalse);
      expect(result.quality.qualityText, 'Best Quality');
    });

    test('handles quality text without resolution and no exact match', () {
      final available = [video('Good Quality'), video('Low Quality')];

      final result = service.findBestMatch(video('Best Quality'), available);
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
    });

    test('handles null codec gracefully', () {
      final available = [video('720p'), video('480p')];

      final result = service.findBestMatch(video('1080p'), available);
      expect(result, isNotNull);
      expect(result!.quality.qualityText, '720p');
    });

    test('prefers lower resolution over higher as fallback', () {
      final available = [
        video('720p', vcodec: 'h264'),
        video('1440p', vcodec: 'h264'),
      ];

      // Both are 360p away from 1080p, but lower gets slight preference
      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      expect(result!.quality.qualityText, '720p');
    });

    test('single available quality returns that quality', () {
      final available = [video('360p')];

      final result = service.findBestMatch(video('1080p'), available);
      expect(result, isNotNull);
      expect(result!.isFallback, isTrue);
      expect(result.quality.qualityText, '360p');
    });

    test('codec normalization works for avc1/h264/h.264', () {
      final available = [
        video('720p', vcodec: 'avc1.640028'),
        video('720p', vcodec: 'vp9'),
      ];

      final result = service.findBestMatch(
        video('1080p', vcodec: 'h264'),
        available,
      );
      expect(result, isNotNull);
      // avc1 normalizes to h264, so it should be preferred
      expect(result!.quality.vcodec, 'avc1.640028');
    });
  });
}
