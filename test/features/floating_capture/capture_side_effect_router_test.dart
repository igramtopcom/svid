import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/entities/video_preview.dart';
import 'package:svid/features/floating_capture/data/services/capture_side_effect_router.dart';
import 'package:svid/features/floating_capture/domain/entities/capture_download_request.dart';
import 'package:svid/features/floating_capture/domain/services/capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CaptureDownloadRequest sampleRequest({
    String url = 'https://www.youtube.com/watch?v=abcdefghijk',
  }) {
    return CaptureDownloadRequest(
      preview: VideoPreview(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.video,
        itemId: 'abcdefghijk',
        title: 'Sample',
        uploader: 'Channel',
        thumbnailUrl: null,
        hasFetchedMetadata: true,
      ),
      requestedAt: DateTime(2026, 5, 5, 12, 0),
    );
  }

  group('callback dispatch', () {
    test('StartDownloadRequested → onDownload called with request', () async {
      CaptureDownloadRequest? received;
      final router = CaptureSideEffectRouter(
        onDownload: (r) async => received = r,
      );
      final req = sampleRequest();
      await router.handle(StartDownloadRequested(req));
      expect(received, req);
    });

    test('OpenExternalUrl → onOpenExternal with url', () async {
      String? got;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (u) async => got = u,
      );
      await router.handle(const OpenExternalUrl('https://www.youtube.com/watch?v=abc'));
      expect(got, 'https://www.youtube.com/watch?v=abc');
    });

    test('OpenInAppUrl → onOpenInApp with url', () async {
      String? got;
      final router = CaptureSideEffectRouter(
        onOpenInApp: (u) async => got = u,
      );
      await router.handle(const OpenInAppUrl('https://www.youtube.com/playlist?list=PLrAXt'));
      expect(got, 'https://www.youtube.com/playlist?list=PLrAXt');
    });

    test('OpenMainAppWindow → onOpenMainApp invoked (no args)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenMainApp: () async => calls++,
      );
      await router.handle(const OpenMainAppWindow());
      expect(calls, 1);
    });

    test('OpenCaptureSettings → onOpenSettings invoked', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenSettings: () async => calls++,
      );
      await router.handle(const OpenCaptureSettings());
      expect(calls, 1);
    });

    test('OpenSavedFolder → onOpenSavedFolder with path', () async {
      String? got;
      final router = CaptureSideEffectRouter(
        onOpenSavedFolder: (p) async => got = p,
      );
      await router.handle(const OpenSavedFolder('/Users/x/Downloads/clip.mp4'));
      expect(got, '/Users/x/Downloads/clip.mp4');
    });

    test('PlaySavedFile → onPlaySavedFile with path', () async {
      String? got;
      final router = CaptureSideEffectRouter(
        onPlaySavedFile: (p) async => got = p,
      );
      await router.handle(const PlaySavedFile('/Users/x/Downloads/clip.mp4'));
      expect(got, '/Users/x/Downloads/clip.mp4');
    });

    test('OpenSavedFolder with empty path → callback NOT invoked '
        '(defensive guard against Process.run("open", ["-R", ""]))', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenSavedFolder: (_) async => calls++,
      );
      await router.handle(const OpenSavedFolder(''));
      expect(calls, 0);
    });

    test('PlaySavedFile with empty path → callback NOT invoked', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onPlaySavedFile: (_) async => calls++,
      );
      await router.handle(const PlaySavedFile(''));
      expect(calls, 0);
    });

    test('NotifyUrlDeduplicated → onNotifyDeduplicated with url '
        '(Phase 2D.2 — anh Quân Windows feedback)', () async {
      String? got;
      final router = CaptureSideEffectRouter(
        onNotifyDeduplicated: (u) async => got = u,
      );
      await router.handle(
        const NotifyUrlDeduplicated('https://www.youtube.com/watch?v=abc'),
      );
      expect(got, 'https://www.youtube.com/watch?v=abc');
    });

    test('NotifyUrlDeduplicated with empty url → callback NOT invoked '
        '(defensive)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onNotifyDeduplicated: (_) async => calls++,
      );
      await router.handle(const NotifyUrlDeduplicated(''));
      expect(calls, 0);
    });
  });

  group('null callbacks', () {
    test('null handlers do not throw, just log', () async {
      const router = CaptureSideEffectRouter();

      // None should throw despite having no callbacks attached.
      await router.handle(StartDownloadRequested(sampleRequest()));
      await router.handle(const OpenExternalUrl('https://www.youtube.com/watch?v=abc'));
      await router.handle(const OpenInAppUrl('https://y'));
      await router.handle(const OpenMainAppWindow());
      await router.handle(const OpenCaptureSettings());
      await router.handle(const OpenSavedFolder('/x/y'));
      await router.handle(const PlaySavedFile('/x/y'));
      await router.handle(const NotifyUrlDeduplicated('https://x'));
    });
  });

  group('error containment', () {
    test('callback throw is caught — does not propagate to caller',
        () async {
      final router = CaptureSideEffectRouter(
        onDownload: (_) async => throw Exception('boom'),
      );
      // Must not throw — failing handler shouldn't poison the listener.
      await expectLater(
        router.handle(StartDownloadRequested(sampleRequest())),
        completes,
      );
    });

    test('multiple effects after failure still dispatch', () async {
      var openExternalCalls = 0;
      final router = CaptureSideEffectRouter(
        onDownload: (_) async => throw StateError('one fails'),
        onOpenExternal: (_) async => openExternalCalls++,
      );
      await router.handle(StartDownloadRequested(sampleRequest()));
      await router.handle(const OpenExternalUrl('https://www.youtube.com/watch?v=abc'));
      expect(openExternalCalls, 1,
          reason: 'failure of one handler must not block the next');
    });
  });

  group('stream wiring shape', () {
    test('handle is a valid Stream listener (returns Future<void>)',
        () async {
      // Compile-time check: assigning router.handle to a Stream listener
      // would fail if the signature were wrong.
      Future<void> Function(CaptureSideEffect) listener =
          const CaptureSideEffectRouter().handle;
      await listener(const OpenMainAppWindow());
    });
  });

  // ===========================================================================
  // v2.2 — IPC URL allowlist (Codex P2 audit fix)
  // ===========================================================================

  group('v2.2 IPC URL allowlist', () {
    test('blocks non-http/https schemes (file://)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      await router.handle(const OpenExternalUrl('file:///etc/passwd'));
      expect(calls, 0, reason: 'file:// scheme must be rejected');
    });

    test('blocks javascript: scheme (XSS via popup IPC)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      await router.handle(
        const OpenExternalUrl('javascript:alert(document.cookie)'),
      );
      expect(calls, 0, reason: 'javascript: scheme must be rejected');
    });

    test('blocks unclassifiable URLs (unknown platform)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      // example.com is http(s) but not a recognized video platform → unknown
      await router.handle(const OpenExternalUrl('https://example.com/page'));
      expect(calls, 0,
          reason: 'unclassifiable URL host blocked by allowlist');
    });

    test('allows valid YouTube URL', () async {
      var got = '';
      final router = CaptureSideEffectRouter(
        onOpenExternal: (u) async => got = u,
      );
      await router.handle(
        const OpenExternalUrl('https://www.youtube.com/watch?v=abc'),
      );
      expect(got, 'https://www.youtube.com/watch?v=abc');
    });

    test('blocks malformed URL (parse failure)', () async {
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      await router.handle(const OpenExternalUrl('not a url at all'));
      expect(calls, 0);
    });
  });
}
