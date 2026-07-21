import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/bridge/api.dart' as native;
import 'package:ssvid/features/youtube_channel/data/repositories/youtube_channel_repository.dart';

void main() {
  group('YouTubeChannelRepository native DTO mapping', () {
    test('maps native channel metadata to domain entity', () {
      final dto = native.ChannelInfoDto(
        id: 'UC123',
        title: 'Native Channel',
        uploader: 'Uploader',
        uploaderId: '@native',
        thumbnail: 'https://img.example/avatar.jpg',
        description: 'Channel description',
        subscriberCount: BigInt.from(9876543),
        videoCount: 321,
        webpageUrl: 'https://youtube.com/@native',
      );

      final result = YouTubeChannelRepository.mapNativeChannelDto(dto);

      expect(result.id, 'UC123');
      expect(result.title, 'Native Channel');
      expect(result.uploader, 'Uploader');
      expect(result.uploaderId, '@native');
      expect(result.thumbnail, 'https://img.example/avatar.jpg');
      expect(result.description, 'Channel description');
      expect(result.subscriberCount, 9876543);
      expect(result.videoCount, 321);
      expect(result.webpageUrl, 'https://youtube.com/@native');
    });

    test('maps native channel video fields to playlist video entity', () {
      final dto = native.PlaylistVideoDto(
        id: 'latest123',
        title: 'Latest Native Video',
        url: 'https://youtube.com/watch?v=latest123',
        thumbnail: 'https://img.example/latest.jpg',
        duration: BigInt.from(600),
        channel: 'Native Channel',
        channelId: 'UC123',
        viewCount: BigInt.from(555000),
        uploadDate: '20260501',
      );

      final result = YouTubeChannelRepository.mapNativeVideoDto(dto);

      expect(result.id, 'latest123');
      expect(result.title, 'Latest Native Video');
      expect(result.url, 'https://youtube.com/watch?v=latest123');
      expect(result.thumbnail, 'https://img.example/latest.jpg');
      expect(result.durationSeconds, 600);
      expect(result.channel, 'Native Channel');
      expect(result.channelId, 'UC123');
      expect(result.viewCount, 555000);
      expect(result.uploadDate, '20260501');
    });
  });
}
