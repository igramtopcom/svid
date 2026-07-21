import 'package:flutter_test/flutter_test.dart';
import 'package:svid/bridge/api.dart' as native;
import 'package:svid/features/youtube_playlist/data/repositories/youtube_playlist_repository.dart';

void main() {
  group('YouTubePlaylistRepository native DTO mapping', () {
    test('maps native playlist metadata to domain entity', () {
      final dto = native.PlaylistInfoDto(
        id: 'PL123',
        title: 'Native Playlist',
        uploader: 'Uploader',
        uploaderId: 'UC123',
        thumbnail: 'https://img.example/playlist.jpg',
        description: 'Playlist description',
        videoCount: 42,
        webpageUrl: 'https://youtube.com/playlist?list=PL123',
      );

      final result = YouTubePlaylistRepository.mapNativePlaylistDto(dto);

      expect(result.id, 'PL123');
      expect(result.title, 'Native Playlist');
      expect(result.uploader, 'Uploader');
      expect(result.uploaderId, 'UC123');
      expect(result.thumbnail, 'https://img.example/playlist.jpg');
      expect(result.description, 'Playlist description');
      expect(result.videoCount, 42);
      expect(result.webpageUrl, 'https://youtube.com/playlist?list=PL123');
    });

    test('maps native playlist video fields to domain entity', () {
      final dto = native.PlaylistVideoDto(
        id: 'vid123',
        title: 'Native Playlist Video',
        url: 'https://youtube.com/watch?v=vid123',
        thumbnail: 'https://img.example/video.jpg',
        duration: BigInt.from(245),
        channel: 'Video Channel',
        channelId: 'UC456',
        viewCount: BigInt.from(12345678),
        uploadDate: '20260429',
      );

      final result = YouTubePlaylistRepository.mapNativeVideoDto(dto);

      expect(result.id, 'vid123');
      expect(result.title, 'Native Playlist Video');
      expect(result.url, 'https://youtube.com/watch?v=vid123');
      expect(result.thumbnail, 'https://img.example/video.jpg');
      expect(result.durationSeconds, 245);
      expect(result.channel, 'Video Channel');
      expect(result.channelId, 'UC456');
      expect(result.viewCount, 12345678);
      expect(result.uploadDate, '20260429');
    });
  });
}
