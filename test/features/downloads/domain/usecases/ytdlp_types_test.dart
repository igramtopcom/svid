import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/gallerydl_datasource.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

void main() {
  group('YtDlpException', () {
    test('creates from error type string', () {
      final ex = YtDlpException.fromErrorType('NotFound', 'Video not found');
      expect(ex.type, YtDlpErrorType.notFound);
      expect(ex.message, 'Video not found');
    });

    test('maps all known error types', () {
      expect(YtDlpException.fromErrorType('NotFound', '').type, YtDlpErrorType.notFound);
      expect(YtDlpException.fromErrorType('GeoRestricted', '').type, YtDlpErrorType.geoRestricted);
      expect(YtDlpException.fromErrorType('LoginRequired', '').type, YtDlpErrorType.loginRequired);
      expect(YtDlpException.fromErrorType('AgeRestricted', '').type, YtDlpErrorType.ageRestricted);
      expect(
          YtDlpException.fromErrorType('FormatNotAvailable', '').type, YtDlpErrorType.formatNotAvailable);
      expect(YtDlpException.fromErrorType('NetworkError', '').type, YtDlpErrorType.networkError);
      expect(YtDlpException.fromErrorType('RateLimited', '').type, YtDlpErrorType.rateLimited);
    });

    test('returns unknown for unrecognized error type', () {
      expect(YtDlpException.fromErrorType('SomethingNew', '').type, YtDlpErrorType.unknown);
      expect(YtDlpException.fromErrorType(null, '').type, YtDlpErrorType.unknown);
    });

    test('defaults message to Unknown error when null', () {
      final ex = YtDlpException.fromErrorType('NotFound', null);
      expect(ex.message, 'Unknown error');
    });

    group('canFallbackToApi', () {
      test('returns true for recoverable errors', () {
        expect(YtDlpException(YtDlpErrorType.binaryNotFound, '').canFallbackToApi, isTrue);
        expect(YtDlpException(YtDlpErrorType.notFound, '').canFallbackToApi, isTrue);
        expect(YtDlpException(YtDlpErrorType.geoRestricted, '').canFallbackToApi, isTrue);
        expect(YtDlpException(YtDlpErrorType.loginRequired, '').canFallbackToApi, isTrue);
        expect(YtDlpException(YtDlpErrorType.timeout, '').canFallbackToApi, isTrue);
        expect(YtDlpException(YtDlpErrorType.rateLimited, '').canFallbackToApi, isTrue);
      });

      test('returns false for non-recoverable errors', () {
        expect(YtDlpException(YtDlpErrorType.ageRestricted, '').canFallbackToApi, isFalse);
        expect(YtDlpException(YtDlpErrorType.formatNotAvailable, '').canFallbackToApi, isFalse);
        expect(YtDlpException(YtDlpErrorType.networkError, '').canFallbackToApi, isFalse);
        expect(YtDlpException(YtDlpErrorType.unknown, '').canFallbackToApi, isFalse);
      });
    });

    test('toString includes type and message', () {
      final ex = YtDlpException(YtDlpErrorType.rateLimited, 'too many requests');
      expect(ex.toString(), contains('rateLimited'));
      expect(ex.toString(), contains('too many requests'));
    });
  });

  group('YtDlpFormat', () {
    test('isVideoOnly when vcodec set and acodec is none', () {
      final format = YtDlpFormat(
        formatId: '137',
        ext: 'mp4',
        height: 1080,
        vcodec: 'avc1',
        acodec: 'none',
      );
      expect(format.isVideoOnly, isTrue);
      expect(format.isAudioOnly, isFalse);
    });

    test('isAudioOnly when vcodec is none and acodec set', () {
      final format = YtDlpFormat(
        formatId: '140',
        ext: 'm4a',
        vcodec: 'none',
        acodec: 'mp4a',
      );
      expect(format.isAudioOnly, isTrue);
      expect(format.isVideoOnly, isFalse);
    });

    test('qualityLabel uses formatNote when available', () {
      final format = YtDlpFormat(
        formatId: '137',
        ext: 'mp4',
        height: 1080,
        formatNote: 'Premium 1080p',
      );
      expect(format.qualityLabel, 'Premium 1080p');
    });

    test('qualityLabel uses height when no formatNote', () {
      final format = YtDlpFormat(
        formatId: '137',
        ext: 'mp4',
        height: 720,
      );
      expect(format.qualityLabel, '720p');
    });

    test('qualityLabel includes fps when > 30', () {
      final format = YtDlpFormat(
        formatId: '303',
        ext: 'webm',
        height: 1080,
        fps: 60.0,
      );
      expect(format.qualityLabel, '1080p60');
    });
  });

  group('YtDlpChapterInfo', () {
    test('duration calculates correctly', () {
      final chapter = YtDlpChapterInfo(
        title: 'Intro',
        startTime: 0.0,
        endTime: 30.0,
      );
      expect(chapter.duration, const Duration(seconds: 30));
    });

    test('formattedStartTime with minutes only', () {
      final chapter = YtDlpChapterInfo(
        title: 'Ch1',
        startTime: 65.0,
        endTime: 120.0,
      );
      expect(chapter.formattedStartTime, '01:05');
    });

    test('formattedStartTime with hours', () {
      final chapter = YtDlpChapterInfo(
        title: 'Ch2',
        startTime: 3661.0,
        endTime: 4000.0,
      );
      expect(chapter.formattedStartTime, '01:01:01');
    });
  });

  group('GalleryDlItem', () {
    test('isImage for image extensions', () {
      final item = GalleryDlItem(index: 1, url: 'http://x.com/1.jpg', extension: 'jpg');
      expect(item.isImage, isTrue);
      expect(item.isVideo, isFalse);
    });

    test('isImage for png', () {
      final item = GalleryDlItem(index: 1, url: 'http://x.com/1.png', extension: 'png');
      expect(item.isImage, isTrue);
    });

    test('isVideo for mp4', () {
      final item = GalleryDlItem(index: 1, url: 'http://x.com/1.mp4', extension: 'mp4');
      expect(item.isVideo, isTrue);
      expect(item.isImage, isFalse);
    });

    test('isVideo for webm', () {
      final item = GalleryDlItem(index: 1, url: 'http://x.com/1.webm', extension: 'webm');
      expect(item.isVideo, isTrue);
    });
  });
}
