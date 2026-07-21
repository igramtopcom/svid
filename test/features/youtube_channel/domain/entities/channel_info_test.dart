import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/youtube_channel/domain/entities/channel_info.dart';

void main() {
  ChannelInfo make({
    String id = 'UC123',
    String title = 'Test Channel',
    String webpageUrl = 'https://www.youtube.com/@testchannel',
    String? uploaderId,
    String? thumbnail,
    int? subscriberCount,
    int? videoCount,
  }) =>
      ChannelInfo(
        id: id,
        title: title,
        webpageUrl: webpageUrl,
        uploaderId: uploaderId,
        thumbnail: thumbnail,
        subscriberCount: subscriberCount,
        videoCount: videoCount,
      );

  group('ChannelInfo', () {
    group('channelHandle', () {
      test('extracts from URL with @', () {
        final ch = make(webpageUrl: 'https://www.youtube.com/@johndoe');
        expect(ch.channelHandle, '@johndoe');
      });

      test('handles URL with path after handle', () {
        final ch =
            make(webpageUrl: 'https://www.youtube.com/@johndoe/videos');
        expect(ch.channelHandle, '@johndoe');
      });

      test('falls back to uploaderId', () {
        final ch = make(
          webpageUrl: 'https://www.youtube.com/channel/UC123',
          uploaderId: 'johndoe',
        );
        expect(ch.channelHandle, '@johndoe');
      });

      test('preserves @ prefix on uploaderId', () {
        final ch = make(
          webpageUrl: 'https://www.youtube.com/channel/UC123',
          uploaderId: '@johndoe',
        );
        expect(ch.channelHandle, '@johndoe');
      });

      test('returns null when no handle available', () {
        final ch = make(
          webpageUrl: 'https://www.youtube.com/channel/UC123',
        );
        expect(ch.channelHandle, isNull);
      });
    });

    group('FormattedChannelMixin', () {
      test('formattedSubscriberCount for millions', () {
        expect(make(subscriberCount: 2500000).formattedSubscriberCount,
            '2.5M subscribers');
      });

      test('formattedSubscriberCount for thousands', () {
        expect(make(subscriberCount: 5200).formattedSubscriberCount,
            '5.2K subscribers');
      });

      test('formattedSubscriberCount for small counts', () {
        expect(make(subscriberCount: 42).formattedSubscriberCount,
            '42 subscribers');
      });

      test('formattedSubscriberCount for null', () {
        expect(make().formattedSubscriberCount, '');
      });

      test('formattedVideoCount', () {
        expect(make(videoCount: 150).formattedVideoCount, '150 videos');
      });

      test('formattedVideoCount for null', () {
        expect(make().formattedVideoCount, '');
      });

      test('highQualityThumbnail upgrades quality', () {
        final ch = make(
            thumbnail: 'https://yt3.ggpht.com/hqdefault/photo.jpg');
        expect(ch.highQualityThumbnail,
            'https://yt3.ggpht.com/maxresdefault/photo.jpg');
      });

      test('highQualityThumbnail returns null for null', () {
        expect(make().highQualityThumbnail, isNull);
      });
    });
  });
}
