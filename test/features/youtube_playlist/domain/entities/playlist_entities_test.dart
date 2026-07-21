import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/youtube_playlist/domain/entities/playlist_info.dart';
import 'package:svid/features/youtube_playlist/domain/entities/playlist_video.dart';

void main() {
  group('PlaylistInfo', () {
    PlaylistInfo make({
      String id = 'PL123',
      String title = 'Test Playlist',
      String webpageUrl = 'https://youtube.com/playlist?list=PL123',
      int? videoCount,
      String? thumbnail,
    }) =>
        PlaylistInfo(
          id: id,
          title: title,
          webpageUrl: webpageUrl,
          videoCount: videoCount,
          thumbnail: thumbnail,
        );

    group('formattedVideoCount', () {
      test('returns empty for null', () {
        expect(make().formattedVideoCount, '');
      });

      test('singular for 1', () {
        expect(make(videoCount: 1).formattedVideoCount, '1 video');
      });

      test('plural for many', () {
        expect(make(videoCount: 50).formattedVideoCount, '50 videos');
      });
    });

    group('highQualityThumbnail', () {
      test('returns null for null', () {
        expect(make().highQualityThumbnail, isNull);
      });

      test('upgrades YouTube thumbnail', () {
        final pl = make(
            thumbnail: 'https://i.ytimg.com/vi/abc/default.jpg');
        expect(pl.highQualityThumbnail,
            'https://i.ytimg.com/vi/abc/hqdefault.jpg');
      });

      test('returns non-YouTube as-is', () {
        final pl = make(thumbnail: 'https://example.com/img.jpg');
        expect(pl.highQualityThumbnail, 'https://example.com/img.jpg');
      });
    });
  });

  group('PlaylistVideo', () {
    PlaylistVideo make({
      String id = 'vid1',
      String title = 'Test Video',
      String url = 'https://youtube.com/watch?v=vid1',
      int? durationSeconds,
      int? viewCount,
      String? thumbnail,
    }) =>
        PlaylistVideo(
          id: id,
          title: title,
          url: url,
          durationSeconds: durationSeconds,
          viewCount: viewCount,
          thumbnail: thumbnail,
        );

    group('formattedDuration', () {
      test('returns empty for null', () {
        expect(make().formattedDuration, '');
      });

      test('formats short duration', () {
        expect(make(durationSeconds: 90).formattedDuration, '01:30');
      });

      test('formats with hours', () {
        expect(make(durationSeconds: 7200).formattedDuration, '2:00:00');
      });
    });

    group('formattedViewCount', () {
      test('returns empty for null', () {
        expect(make().formattedViewCount, '');
      });

      test('formats raw count', () {
        expect(make(viewCount: 999).formattedViewCount, '999 views');
      });

      test('formats K', () {
        expect(make(viewCount: 45000).formattedViewCount, '45.0K views');
      });

      test('formats M', () {
        expect(
            make(viewCount: 1200000).formattedViewCount, '1.2M views');
      });
    });

    group('highQualityThumbnail', () {
      test('returns null for null', () {
        expect(make().highQualityThumbnail, isNull);
      });

      test('upgrades YouTube thumbnail', () {
        final v = make(
            thumbnail: 'https://i.ytimg.com/vi/vid1/default.jpg');
        expect(v.highQualityThumbnail,
            'https://img.youtube.com/vi/vid1/hqdefault.jpg');
      });
    });
  });
}
