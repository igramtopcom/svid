import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/clipboard_service.dart';
import '../../../../core/utils/validators.dart';
import '../../../downloads/domain/entities/video_info.dart';

/// Clipboard radar detection state
class ClipboardRadarState {
  final String? detectedUrl;
  final String? platform;
  final VideoInfo? videoInfo;
  final bool isFetching;
  final bool fetchFailed;

  const ClipboardRadarState({
    this.detectedUrl,
    this.platform,
    this.videoInfo,
    this.isFetching = false,
    this.fetchFailed = false,
  });

  bool get isDetected => detectedUrl != null;
  bool get hasRichInfo => videoInfo != null;

  ClipboardRadarState copyWith({
    String? detectedUrl,
    String? platform,
    VideoInfo? videoInfo,
    bool? isFetching,
    bool? fetchFailed,
  }) {
    return ClipboardRadarState(
      detectedUrl: detectedUrl ?? this.detectedUrl,
      platform: platform ?? this.platform,
      videoInfo: videoInfo ?? this.videoInfo,
      isFetching: isFetching ?? this.isFetching,
      fetchFailed: fetchFailed ?? this.fetchFailed,
    );
  }
}

/// Watches system clipboard for video URLs and exposes the detection
/// state so the home shell can auto-paste a copied URL into the input.
///
/// Speculative metadata pre-fetch was removed (see commit history) — it
/// double-extracted via yt-dlp and never shared its cache with the
/// manual-submit path, so it added latency + bandwidth without
/// improving the experience. Detection stays here; extraction runs
/// exactly once when the user clicks the CTA.
class ClipboardRadarNotifier extends StateNotifier<ClipboardRadarState> {
  Timer? _timer;
  String? _lastContent;
  bool _disposed = false;

  ClipboardRadarNotifier() : super(const ClipboardRadarState()) {
    _startWatching();
  }

  void _startWatching() {
    _checkClipboard();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkClipboard(),
    );
  }

  Future<void> _checkClipboard() async {
    if (_disposed) return;
    try {
      final raw = await ClipboardService.getText();
      if (_disposed) return;
      final text = raw?.trim();

      if (text == null || text.isEmpty) return;
      if (text == _lastContent) return;
      _lastContent = text;

      if (Validators.isLikelyMediaUrl(text)) {
        // URL detection only — drop the speculative metadata fetch that
        // used to fire `extractVideoInfoUseCaseProvider` here. That
        // pre-fetch caused double-extraction (radar + manual click both
        // ran yt-dlp) without sharing the result, and the right-panel
        // shimmer it powered confused users who saw a preview vanish
        // when they pressed "Bắt đầu". The auto-paste UX still works
        // off [detectedUrl]; full extraction runs once on submit.
        final platform = _detectPlatform(text);
        state = ClipboardRadarState(
          detectedUrl: text,
          platform: platform,
        );
      } else {
        state = const ClipboardRadarState();
      }
    } catch (_) {
      // Clipboard access can fail on some platforms
    }
  }

  static String _detectPlatform(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Web';
    final host = uri.host.toLowerCase();

    if (host.contains('youtube') || host.contains('youtu.be')) return 'YouTube';
    if (host.contains('tiktok')) return 'TikTok';
    if (host.contains('instagram')) return 'Instagram';
    if (host.contains('twitter') || host.contains('x.com')) return 'X';
    if (host.contains('facebook') || host.contains('fb.')) return 'Facebook';
    if (host.contains('vimeo')) return 'Vimeo';
    if (host.contains('reddit')) return 'Reddit';
    if (host.contains('twitch')) return 'Twitch';
    if (host.contains('soundcloud')) return 'SoundCloud';
    if (host.contains('dailymotion')) return 'Dailymotion';
    if (host.contains('bilibili')) return 'Bilibili';
    if (host.contains('pinterest')) return 'Pinterest';
    if (host.contains('rumble')) return 'Rumble';
    if (host.contains('odysee')) return 'Odysee';
    if (host.contains('bandcamp')) return 'Bandcamp';
    if (host.contains('nicovideo')) return 'Niconico';

    final parts = host.split('.');
    if (parts.length >= 2) {
      final domain = parts[parts.length - 2];
      return '${domain[0].toUpperCase()}${domain.substring(1)}';
    }
    return 'Web';
  }

  void dismiss() {
    if (_disposed) return;
    _lastContent = null;
    state = const ClipboardRadarState();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

final clipboardRadarProvider =
    StateNotifierProvider<ClipboardRadarNotifier, ClipboardRadarState>((ref) {
      return ClipboardRadarNotifier();
    });
