import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/youtube_channel/domain/entities/channel_info.dart';
import 'package:ssvid/features/youtube_channel/presentation/providers/youtube_channel_provider.dart';
import 'package:ssvid/features/youtube_channel/presentation/screens/channel_video_list_screen.dart';
import 'package:ssvid/features/youtube_playlist/domain/entities/playlist_video.dart';

class _FakeYouTubeChannelNotifier extends YouTubeChannelNotifier {
  _FakeYouTubeChannelNotifier(super.ref, YouTubeChannelState initial) {
    state = initial;
  }

  @override
  Future<void> loadMoreVideos() async {}
}

void main() {
  testWidgets('embedded extract does not pop the root navigator', (
    tester,
  ) async {
    const video = PlaylistVideo(
      id: 'video-1',
      title: 'Selected video',
      url: 'https://www.youtube.com/watch?v=video-1',
      durationSeconds: 60,
    );
    const initialState = YouTubeChannelState(
      channel: ChannelInfo(
        id: 'channel-1',
        title: 'Channel',
        webpageUrl: 'https://www.youtube.com/@channel',
      ),
      videos: [video],
      filteredVideos: [video],
      selectedVideoIds: {'video-1'},
      hasMore: false,
    );
    final selectedUrls = <List<String>>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          youtubeChannelProvider.overrideWith(
            (ref) => _FakeYouTubeChannelNotifier(ref, initialState),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: ChannelVideoListScreen(
                embedded: true,
                onDownloadSelected: selectedUrls.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('EXTRACT [1]'));
    await tester.pump();

    expect(selectedUrls, [
      ['https://www.youtube.com/watch?v=video-1'],
    ]);
    expect(find.byType(ChannelVideoListScreen), findsOneWidget);
  });
}
