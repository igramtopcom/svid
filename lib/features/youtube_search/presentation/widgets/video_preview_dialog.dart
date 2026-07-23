import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/core.dart';
import '../../../../core/services/webview_environment_service.dart';
import '../../domain/entities/youtube_search_result.dart';

/// Lightweight in-app "watch before you download" preview.
///
/// Plays the YouTube embed player in a modal so the user can check a trending
/// or search result without leaving Explore, then download it straight from the
/// dialog. On Windows this embeds `flutter_inappwebview` (WebView2); on other
/// platforms — where the app uses a different webview stack — it falls back to
/// opening the video in the system browser.
class VideoPreviewDialog extends StatefulWidget {
  final YouTubeSearchResult video;

  /// Invoked when the user taps Download inside the preview. The dialog closes
  /// first, then this runs (reuses the normal Explore download flow).
  final VoidCallback? onDownload;

  const VideoPreviewDialog({
    super.key,
    required this.video,
    this.onDownload,
  });

  static Future<void> show(
    BuildContext context,
    YouTubeSearchResult video, {
    VoidCallback? onDownload,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => VideoPreviewDialog(video: video, onDownload: onDownload),
    );
  }

  @override
  State<VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<VideoPreviewDialog> {
  bool _loading = true;

  // Load the full watch page, not the /embed player: many music videos (VEVO,
  // label/official channels) disable third-party embedding, which makes the
  // embed player fail with "Error 153". The watch page plays regardless.
  String get _watchUrl => widget.video.url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: isDark ? AppColors.homeDarkCardBg : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player (16:9)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: _buildPlayer(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.video.channel != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      widget.video.channel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            isDark
                                ? AppColors.homeDarkTextSecondary
                                : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(widget.video.url),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(AppLocalizations.youtubeSearchOpenInBrowser),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              isDark
                                  ? AppColors.homeDarkTextSecondary
                                  : cs.onSurfaceVariant,
                        ),
                        child: Text(AppLocalizations.commonClose),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed:
                            widget.onDownload == null
                                ? null
                                : () {
                                  Navigator.of(context).maybePop();
                                  widget.onDownload!();
                                },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(AppLocalizations.youtubeSearchDownload),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (!Platform.isWindows || WebViewEnvironmentService.instance == null) {
      // No embedded WebView2 here — offer a one-tap open in the system browser.
      return Center(
        child: FilledButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(widget.video.url),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(AppLocalizations.youtubeSearchOpenInBrowser),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        iaw.InAppWebView(
          webViewEnvironment: WebViewEnvironmentService.instance,
          initialUrlRequest: iaw.URLRequest(url: iaw.WebUri(_watchUrl)),
          initialSettings: iaw.InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            supportMultipleWindows: false,
            javaScriptCanOpenWindowsAutomatically: false,
            mediaPlaybackRequiresUserGesture: false,
          ),
          onLoadStop: (controller, url) {
            if (mounted) setState(() => _loading = false);
          },
          onReceivedError: (controller, request, error) {
            if (mounted && (request.isForMainFrame ?? false)) {
              setState(() => _loading = false);
            }
          },
          // Keep popups inside this view — avoids WebView2 crashes.
          onCreateWindow: (controller, action) async => false,
        ),
        if (_loading)
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}
