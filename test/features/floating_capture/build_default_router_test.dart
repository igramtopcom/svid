import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_preview.dart';
import 'package:ssvid/features/floating_capture/domain/entities/capture_download_request.dart';
import 'package:ssvid/features/floating_capture/domain/services/capture_service.dart';
import 'package:ssvid/features/floating_capture/presentation/providers/floating_capture_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CaptureDownloadRequest sampleRequest() => CaptureDownloadRequest(
        preview: VideoPreview(
          rawUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
          platform: VideoPlatform.youtube,
          urlType: UrlType.video,
          itemId: 'abcdefghijk',
          title: 'T',
          uploader: 'U',
          thumbnailUrl: null,
          hasFetchedMetadata: true,
        ),
        requestedAt: DateTime(2026, 5, 5),
      );

  group('buildDefaultCaptureSideEffectRouter', () {
    test('omitting onDownload yields router that logs (no throw)',
        () async {
      final router = buildDefaultCaptureSideEffectRouter();
      // Must not throw — null callback path inside CaptureSideEffectRouter
      // logs and drops.
      await router.handle(StartDownloadRequested(sampleRequest()));
    });

    test('passed onDownload is invoked with the request', () async {
      CaptureDownloadRequest? captured;
      final router = buildDefaultCaptureSideEffectRouter(
        onDownload: (r) async => captured = r,
      );
      final req = sampleRequest();
      await router.handle(StartDownloadRequested(req));
      expect(captured, req);
    });

    test('default OpenExternalUrl handler exists (does not throw on bad URL)',
        () async {
      final router = buildDefaultCaptureSideEffectRouter();
      // url_launcher is mocked-out in unit tests — the default handler's
      // try/catch should swallow the platform-channel failure.
      await router.handle(const OpenExternalUrl('not a real url'));
    });

    test('OpenInAppUrl callback honoured when supplied', () async {
      String? captured;
      final router = buildDefaultCaptureSideEffectRouter(
        onOpenInApp: (u) async => captured = u,
      );
      await router.handle(const OpenInAppUrl('https://www.youtube.com/watch?v=abc'));
      expect(captured, 'https://www.youtube.com/watch?v=abc');
    });

    test('OpenCaptureSettings callback honoured when supplied', () async {
      var fired = 0;
      final router = buildDefaultCaptureSideEffectRouter(
        onOpenSettings: () async => fired++,
      );
      await router.handle(const OpenCaptureSettings());
      expect(fired, 1);
    });
  });
}
