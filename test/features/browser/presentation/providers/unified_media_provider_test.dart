import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/browser/domain/entities/unified_media_item.dart';
import 'package:svid/features/browser/presentation/providers/media_detector_provider.dart';
import 'package:svid/features/browser/presentation/providers/unified_media_provider.dart';

void main() {
  group('unifiedMediaProvider', () {
    test('routes Facebook fbcdn media to direct Rust fallback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const pageUrl = 'https://www.facebook.com/reel/1715987549559649';
      const mediaUrl =
          'https://video-lga3-1.xx.fbcdn.net/v/t42.1790-2/video.mp4?oh=abc';
      container.read(browserPageUrlProvider.notifier).state = pageUrl;

      final captured = container
          .read(interceptedMediaProvider.notifier)
          .processMessage({
            'url': mediaUrl,
            'source': 'performance',
            'type': 'video',
            'pageTitle': 'Facebook reel',
            'pageUrl': pageUrl,
          });

      expect(captured, isNotNull);

      final items = container.read(unifiedMediaProvider);
      expect(items, hasLength(1));

      final item = items.single;
      expect(item.type, MediaItemType.directMediaFile);
      expect(item.usesRustEngine, isTrue);
      expect(item.usesYtdlp, isFalse);
      expect(item.platform, VideoPlatform.facebook);
      expect(item.downloadUrl, mediaUrl);
    });

    test('keeps non-Facebook platform CDN media as yt-dlp signal', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const pageUrl = 'https://www.tiktok.com/@user/video/1234567890';
      const mediaUrl = 'https://v16-webapp.tiktokcdn.com/video.mp4?x=1';
      container.read(browserPageUrlProvider.notifier).state = pageUrl;

      final captured = container
          .read(interceptedMediaProvider.notifier)
          .processMessage({
            'url': mediaUrl,
            'source': 'performance',
            'type': 'video',
            'pageTitle': 'TikTok video',
            'pageUrl': pageUrl,
          });

      expect(captured, isNotNull);

      final items = container.read(unifiedMediaProvider);
      expect(items, hasLength(1));

      final item = items.single;
      expect(item.type, MediaItemType.streamingSignal);
      expect(item.usesYtdlp, isTrue);
      expect(item.usesRustEngine, isFalse);
      expect(item.platform, VideoPlatform.tiktok);
      expect(item.pageUrl, pageUrl);
    });
  });
}
