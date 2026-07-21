import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/youtube_search/domain/entities/youtube_search_result.dart';

void main() {
  YouTubeSearchResult make({
    String id = 'abc123',
    String title = 'Test Video',
    String url = 'https://youtube.com/watch?v=abc123',
    int? durationSeconds,
    int? viewCount,
    String? uploadDate,
    String? thumbnail,
  }) => YouTubeSearchResult(
    id: id,
    title: title,
    url: url,
    durationSeconds: durationSeconds,
    viewCount: viewCount,
    uploadDate: uploadDate,
    thumbnail: thumbnail,
  );

  group('YouTubeSearchResult', () {
    group('formattedDuration', () {
      test('returns empty string when null', () {
        expect(make().formattedDuration, '');
      });

      test('formats seconds only', () {
        expect(make(durationSeconds: 45).formattedDuration, '00:45');
      });

      test('formats minutes and seconds', () {
        expect(make(durationSeconds: 185).formattedDuration, '03:05');
      });

      test('formats hours', () {
        expect(make(durationSeconds: 3661).formattedDuration, '1:01:01');
      });
    });

    group('formattedViewCount', () {
      test('returns empty string when null', () {
        expect(make().formattedViewCount, '');
      });

      test('shows raw count under 1K', () {
        expect(make(viewCount: 500).formattedViewCount, '500 views');
      });

      test('formats thousands', () {
        expect(make(viewCount: 1500).formattedViewCount, '1.5K views');
      });

      test('formats millions', () {
        expect(make(viewCount: 2500000).formattedViewCount, '2.5M views');
      });

      test('formats billions', () {
        expect(make(viewCount: 3200000000).formattedViewCount, '3.2B views');
      });
    });

    group('formattedUploadDate', () {
      test('returns empty for null', () {
        expect(make().formattedUploadDate, '');
      });

      test('returns empty for empty string', () {
        expect(make(uploadDate: '').formattedUploadDate, '');
      });

      test('passes through relative format', () {
        expect(
          make(uploadDate: '3 days ago').formattedUploadDate,
          '3 days ago',
        );
      });

      test('passes through non-parseable string', () {
        expect(make(uploadDate: 'unknown').formattedUploadDate, 'unknown');
      });
    });

    group('highQualityThumbnail', () {
      test('returns null when thumbnail is null', () {
        expect(make().highQualityThumbnail, isNull);
      });

      test('upgrades YouTube thumbnail', () {
        final result = make(
          thumbnail: 'https://i.ytimg.com/vi/abc123/default.jpg',
        );
        expect(
          result.highQualityThumbnail,
          'https://img.youtube.com/vi/abc123/mqdefault.jpg',
        );
      });

      test('returns non-YouTube thumbnail as-is', () {
        final result = make(thumbnail: 'https://example.com/thumb.jpg');
        expect(result.highQualityThumbnail, 'https://example.com/thumb.jpg');
      });
    });

    test('freezed equality', () {
      final a = make(id: 'x', title: 't', url: 'u');
      final b = make(id: 'x', title: 't', url: 'u');
      expect(a, equals(b));
    });

    test('freezed copyWith', () {
      final original = make(title: 'Original');
      final copied = original.copyWith(title: 'Changed');
      expect(copied.title, 'Changed');
      expect(copied.id, original.id);
    });
  });
}
