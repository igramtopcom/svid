import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/presentation/providers/auth_providers.dart';
import '../../domain/services/browser_cookie_auto_capture_service.dart';
import '../../domain/services/page_video_scanner_service.dart';
import '../../domain/services/video_url_detector.dart';

/// Initial URL for the browser — set before navigating to browser tab
final browserInitialUrlProvider = StateProvider<String>((ref) {
  return 'https://www.google.com';
});

/// Current video detection result — updated on page navigation
final browserVideoDetectionProvider = StateProvider<VideoUrlDetection?>((ref) {
  return null;
});

/// List of video links detected on the current page via DOM scanning.
final browserDetectedVideosProvider =
    StateProvider<List<DetectedVideoLink>>((ref) {
  return [];
});

/// Auto-captures platform session cookies from the WebView store into the
/// PlatformCookie DB when the user finishes a login flow. Single instance
/// per app — internal throttle + dedupe map is state worth keeping.
final browserCookieAutoCaptureServiceProvider =
    Provider<BrowserCookieAutoCaptureService>((ref) {
  final saveUseCase = ref.watch(savePlatformCookiesUseCaseProvider);
  return BrowserCookieAutoCaptureService(saveUseCase);
});
