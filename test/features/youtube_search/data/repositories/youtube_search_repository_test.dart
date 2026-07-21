import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/bridge/api.dart' as native;
import 'package:ssvid/features/youtube_search/data/repositories/youtube_search_repository.dart';

void main() {
  group('YouTubeSearchRepository native DTO mapping', () {
    test('maps all native search fields to domain entity', () {
      final dto = native.YouTubeSearchResultDto(
        id: 'abc123',
        title: 'Native Search Result',
        channel: 'Channel Name',
        channelId: 'UC123',
        thumbnail: 'https://img.example/thumb.jpg',
        duration: BigInt.from(3661),
        viewCount: BigInt.from(3200000000),
        uploadDate: '20260430',
        url: 'https://youtube.com/watch?v=abc123',
        description: 'Native description',
      );

      final result = YouTubeSearchRepository.mapNativeSearchDto(dto);

      expect(result.id, 'abc123');
      expect(result.title, 'Native Search Result');
      expect(result.channel, 'Channel Name');
      expect(result.channelId, 'UC123');
      expect(result.thumbnail, 'https://img.example/thumb.jpg');
      expect(result.durationSeconds, 3661);
      expect(result.viewCount, 3200000000);
      expect(result.uploadDate, '20260430');
      expect(result.url, 'https://youtube.com/watch?v=abc123');
      expect(result.description, 'Native description');
    });
  });
}
