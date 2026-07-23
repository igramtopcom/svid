import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/auth/data/native/native_cookie_extractor.dart';
import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../downloads/presentation/providers/extraction_provider.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/webview/app_webview.dart';
import '../../domain/entities/intercepted_media.dart';
import '../../domain/entities/unified_media_item.dart';
import '../providers/browser_providers.dart';
import '../providers/content_filter_providers.dart';
import '../providers/media_detector_provider.dart';
import '../providers/unified_media_provider.dart';

/// Right-side media panel that surfaces downloadable media detected on the page.
class MediaSniffPanel extends ConsumerStatefulWidget {
  final AppWebViewController? activeController;

  const MediaSniffPanel({super.key, this.activeController});

  static const double panelWidth = 320.0;
  static const double compactPanelWidth = 280.0;

  @override
  ConsumerState<MediaSniffPanel> createState() => _MediaSniffPanelState();
}

class _MediaSniffPanelState extends ConsumerState<MediaSniffPanel> {
  @override
  Widget build(BuildContext context) {
    // Panel visibility is driven by the user opening it (toolbar button),
    // NOT by whether the engine is running — the engine always runs.
    final isOpen = ref.watch(sniffPanelOpenProvider);
    if (!isOpen) return const SizedBox.shrink();

    final items = ref.watch(unifiedMediaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelWidth = _panelWidth(context);

    final downloadable = items.where((i) => i.isDownloadable).toList();

    // Panel was opened explicitly, so always show something: a scanning/empty
    // state rather than vanishing when nothing has been detected yet.
    if (downloadable.isEmpty) {
      return _buildScanningState(isDark);
    }

    // Classify: first video/page-link = PRIMARY, rest = SUPPORTING
    final primary = <UnifiedMediaItem>[];
    final supporting = <UnifiedMediaItem>[];

    for (final item in downloadable) {
      if (primary.isEmpty &&
          (item.type == MediaItemType.videoPageLink ||
              item.type == MediaItemType.streamingSignal ||
              (item.type == MediaItemType.directMediaFile &&
                  item.originalCategory != MediaCategory.audio))) {
        primary.add(item);
      } else {
        supporting.add(item);
      }
    }
    // If no video primary, promote first item
    if (primary.isEmpty && supporting.isNotEmpty) {
      primary.add(supporting.removeAt(0));
    }

    final baseBg = AppColors.surface1(context);
    final cardBg = AppColors.surface2(context);
    final headerBg = AppColors.surface2(context);
    final textPrimary =
        isDark
            ? AppColors.darkLightText
            : Theme.of(context).colorScheme.onSurface;
    final textSecondary =
        isDark
            ? AppColors.lightMuted
            : Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: AppOpacity.secondary);
    final textTertiary =
        isDark
            ? AppColors.lightMetaText
            : Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: AppOpacity.scrim);

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: baseBg,
        border: Border(
          left: BorderSide(
            color: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.hover,
            ),
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Panel Header ──
          _buildHeader(
            headerBg,
            textPrimary,
            textTertiary,
            downloadable.length,
          ),

          // ── Active Media Log ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.smMd,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Text(
                  AppLocalizations.browserMediaSniffEnabled,
                  style: AppTypography.mini.copyWith(
                    color: textTertiary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable content ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smMd,
                vertical: AppSpacing.xs,
              ),
              children: [
                // Primary media item(s)
                for (final item in primary)
                  _buildPrimaryTarget(
                    item,
                    cardBg,
                    textPrimary,
                    textSecondary,
                    textTertiary,
                  ),

                if (supporting.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.smMd,
                      bottom: AppSpacing.sm,
                      left: AppSpacing.xs,
                    ),
                    child: Text(
                      AppLocalizations.browserMediaSniffCount(
                        supporting.length,
                      ),
                      style: AppTypography.mini.copyWith(
                        color: textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  for (final item in supporting)
                    _buildSupportingItem(
                      item,
                      cardBg,
                      textPrimary,
                      textSecondary,
                      textTertiary,
                    ),
                ],
              ],
            ),
          ),

          // ── Footer ──
          _buildFooter(headerBg, textTertiary, downloadable, supporting.length),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(
    Color headerBg,
    Color textPrimary,
    Color textTertiary,
    int count,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smMd,
      ),
      color: headerBg,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight.withValues(
                alpha: AppOpacity.pressed,
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Center(
              child: Icon(
                Icons.sensors_rounded,
                size: 13,
                color: AppColors.accentHighlight,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.browserMediaSniffTitle,
            style: AppTypography.sectionHeader.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentHighlight,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              AppLocalizations.browserMediaSniffCount(count),
              style: AppTypography.mini.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              // Close the panel (keep detected media so re-opening still shows
              // it); the engine keeps running in the background.
              onPressed: () {
                ref.read(sniffPanelOpenProvider.notifier).state = false;
              },
              icon: const Icon(Icons.close_rounded, size: 14),
              tooltip: AppLocalizations.commonClose,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              color: textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Primary Target Card ──

  Widget _buildPrimaryTarget(
    UnifiedMediaItem item,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
  ) {
    final displayName = item.title ?? item.domain;
    final sizeText =
        item.estimatedSize != null
            ? FileUtils.formatBytes(item.estimatedSize!)
            : null;
    final platformName =
        item.platform != VideoPlatform.unknown ? item.platform.name : '';
    final hasPlatformIcon =
        platformName.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platformName);
    final platformColor =
        platformName.isNotEmpty
            ? PlatformStyleHelper.getColorForPlatform(platformName)
            : AppColors.accentHighlight;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(alpha: AppOpacity.subtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary badge bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smMd,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentHighlight.withValues(
                alpha: AppOpacity.hover,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentHighlight,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    _typeLabel(item),
                    style: AppTypography.mini.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const Spacer(),
                if (sizeText != null)
                  Text(
                    sizeText,
                    style: AppTypography.compact.copyWith(color: textSecondary),
                  ),
              ],
            ),
          ),

          // Thumbnail with platform overlay
          ClipRRect(
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brand.withValues(alpha: AppOpacity.quarter),
                    cardBg,
                    AppColors.accentMuted.withValues(alpha: AppOpacity.pressed),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.usesYtdlp
                            ? Icons.auto_awesome_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  ),
                  if (hasPlatformIcon)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Center(
                          child: PlatformIcon(platform: platformName, size: 13),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Title + metadata
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.smMd,
              AppSpacing.sm,
              AppSpacing.smMd,
              AppSpacing.xs,
            ),
            child: Text(
              displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.buttonPrimary.copyWith(
                fontWeight: FontWeight.w700,
                color: textPrimary,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ),

          // Quality badges row
          if (platformName.isNotEmpty || item.contentType != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.smMd,
                0,
                AppSpacing.smMd,
                AppSpacing.sm,
              ),
              child: Wrap(
                spacing: 4,
                children: [
                  if (platformName.isNotEmpty)
                    _badge(platformName, platformColor),
                  if (item.supportsRange == true)
                    _badge('Fast', AppColors.accentHighlight),
                  _badge(_typeLabel(item), textTertiary),
                ],
              ),
            ),

          // Download button
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.smMd,
              AppSpacing.xxs,
              AppSpacing.smMd,
              AppSpacing.smMd,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: FilledButton.icon(
                onPressed: () => _downloadItem(item),
                icon: Icon(
                  item.usesYtdlp
                      ? Icons.auto_awesome_rounded
                      : Icons.download_rounded,
                  size: 15,
                ),
                label: Text(
                  AppLocalizations.browserMediaSniffDownload,
                  style: AppTypography.statusBadge.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentHighlight,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Supporting Intel Item ──

  Widget _buildSupportingItem(
    UnifiedMediaItem item,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
  ) {
    final displayName = item.title ?? item.domain;
    final sizeText =
        item.estimatedSize != null
            ? FileUtils.formatBytes(item.estimatedSize!)
            : null;
    final isAudio = item.originalCategory == MediaCategory.audio;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: cardBg.withValues(alpha: AppOpacity.secondary),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (isAudio ? AppColors.infoBlue : AppColors.accentHighlight)
                  .withValues(alpha: AppOpacity.pressed),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              isAudio
                  ? Icons.audiotrack_rounded
                  : item.type == MediaItemType.hlsManifest
                  ? Icons.stream_rounded
                  : Icons.videocam_rounded,
              size: 16,
              color: isAudio ? AppColors.infoBlue : AppColors.accentHighlight,
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Name + size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.statusBadge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                    letterSpacing: 0,
                  ),
                ),
                if (sizeText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      sizeText,
                      style: AppTypography.mini.copyWith(color: textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            height: 28,
            child: OutlinedButton(
              onPressed: () => _downloadItem(item),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentHighlight,
                side: BorderSide(color: AppColors.brand, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                AppLocalizations.browserMediaSniffDownload,
                style: AppTypography.mini.copyWith(letterSpacing: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ──

  Widget _buildFooter(
    Color headerBg,
    Color textTertiary,
    List<UnifiedMediaItem> allItems,
    int supportingCount,
  ) {
    final ytdlpCount = allItems.where((i) => i.usesYtdlp).length;
    final directCount = allItems.where((i) => i.usesRustEngine).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.smMd,
      ),
      color: headerBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allItems.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                height: 34,
                child: FilledButton.icon(
                  onPressed: () => _downloadAll(allItems),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: Text(
                    AppLocalizations.browserMediaSniffDownloadAll,
                    style: AppTypography.statusBadge.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
              ),
            ),
          Text(
            '${AppLocalizations.browserMediaSniffCount(allItems.length)}${ytdlpCount > 0 ? ' · $ytdlpCount signals' : ''}${directCount > 0 ? ' · $directCount direct' : ''}',
            style: AppTypography.mini.copyWith(
              fontWeight: FontWeight.w500,
              color: textTertiary,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ── Scanning State (feed page) ──

  Widget _buildScanningState(bool isDark) {
    final baseBg = AppColors.surface1(context);
    final panelWidth = _panelWidth(context);
    final textTertiary =
        isDark
            ? AppColors.lightMetaText
            : Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: AppOpacity.scrim);

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: baseBg,
        border: Border(
          left: BorderSide(
            color: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.hover,
            ),
          ),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight.withValues(
                alpha: AppOpacity.divider,
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              Icons.sensors_rounded,
              size: 26,
              color: AppColors.accentHighlight.withValues(
                alpha: AppOpacity.scrim,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.browserMediaSniffEnabled,
            textAlign: TextAlign.center,
            style: AppTypography.compact.copyWith(
              fontWeight: FontWeight.w600,
              color: textTertiary,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.browserMediaSniffFeedTip,
            textAlign: TextAlign.center,
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w400,
              color: textTertiary.withValues(alpha: AppOpacity.nearOpaque),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.pressed),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        text,
        style: AppTypography.mini.copyWith(color: color, letterSpacing: 0),
      ),
    );
  }

  String _typeLabel(UnifiedMediaItem item) {
    return switch (item.type) {
      MediaItemType.videoPageLink => AppLocalizations.browserMediaSniffVideo,
      MediaItemType.directMediaFile =>
        item.originalCategory == MediaCategory.audio
            ? AppLocalizations.browserMediaSniffAudio
            : AppLocalizations.browserMediaSniffVideo,
      MediaItemType.hlsManifest => 'HLS',
      MediaItemType.streamingSignal => AppLocalizations.browserMediaSniffStream,
      MediaItemType.undownloadable => AppLocalizations.browserMediaSniffUnknown,
    };
  }

  // ── Download actions ──

  void _downloadItem(UnifiedMediaItem item) {
    if (!_ensureMediaSniffPremiumAccess()) return;

    switch (item.type) {
      case MediaItemType.videoPageLink:
        _startYtdlpExtraction(item.pageUrl!);
        break;
      case MediaItemType.streamingSignal:
        if (item.pageUrl != null) {
          _startYtdlpExtraction(item.pageUrl!);
        }
        break;
      case MediaItemType.directMediaFile:
      case MediaItemType.hlsManifest:
        _startDirectRustDownload(item);
        break;
      case MediaItemType.undownloadable:
        if (mounted) {
          AppSnackBar.info(
            context,
            message:
                'Streaming content — paste the page URL in the home screen to download',
          );
        }
        break;
    }
  }

  Future<void> _downloadAll(List<UnifiedMediaItem> items) async {
    if (!_ensureMediaSniffPremiumAccess()) return;

    final ytdlpItems = items.where((i) => i.usesYtdlp).toList();
    final directItems = items.where((i) => i.usesRustEngine).toList();

    if (ytdlpItems.isNotEmpty) {
      final pageUrls =
          ytdlpItems.map((i) => i.pageUrl).where((u) => u != null).toSet();
      for (final pageUrl in pageUrls) {
        _startYtdlpExtraction(pageUrl!);
        if (pageUrls.length > 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    for (final item in directItems) {
      await _startDirectRustDownload(item);
      if (directItems.length > 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  void _startYtdlpExtraction(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return;

    final path = uri.path;
    final isFeed =
        path == '/' ||
        path.isEmpty ||
        path == '/explore' ||
        path == '/reels' ||
        path == '/feed' ||
        path == '/home' ||
        path == '/foryou' ||
        path == '/following';

    final isProfileRoot =
        RegExp(r'^/[^/]+/?$').hasMatch(path) &&
        !RegExp(
          r'^/(p|reel|tv|watch|shorts|video|status|comments)/',
        ).hasMatch(path);

    if (isFeed || isProfileRoot) {
      if (mounted) {
        AppSnackBar.info(
          context,
          message: AppLocalizations.browserMediaSniffOpenSpecificVideo,
        );
      }
      return;
    }

    final extractionNotifier = ref.read(extractionProvider.notifier);
    final extractionState = ref.read(extractionProvider);

    if (extractionState.isExtracting) {
      if (mounted) {
        AppSnackBar.info(context, message: AppLocalizations.browserDownloading);
      }
      return;
    }

    if (mounted) {
      AppSnackBar.info(context, message: AppLocalizations.browserDownloading);
    }

    final settings = ref.read(settingsProvider);

    () async {
      String? cookiesFile;
      try {
        cookiesFile = await ref.read(cookiesFileForUrlProvider(pageUrl).future);
      } catch (_) {}
      if (!mounted) return;

      final cookiesFromBrowser =
          cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null;
      final stopOnLoginRequired =
          Platform.isWindows &&
          PlatformDetector.detectPlatform(pageUrl) == VideoPlatform.youtube &&
          cookiesFile == null &&
          cookiesFromBrowser == null;

      extractionNotifier.startExtraction(
        url: pageUrl,
        engine: settings.downloadEngine,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: ref.read(
          cookiesFromBrowserFallbackProvider,
        ),
        cookiesFromBrowserFallbackChain: ref.read(
          cookiesFromBrowserFallbackChainProvider,
        ),
        stopOnLoginRequired: stopOnLoginRequired,
      );
    }();
  }

  Future<void> _startDirectRustDownload(UnifiedMediaItem item) async {
    if (item.downloadUrl == null) return;

    try {
      final currentUrl = await _getPageUrl();
      if (!mounted) return;

      String? cookies;
      final pageDomain =
          currentUrl != null ? Uri.tryParse(currentUrl)?.host ?? '' : '';
      for (final domain in [pageDomain, item.domain]) {
        if (domain.isEmpty) continue;
        final nativeCookies = await NativeCookieExtractor.getCookiesForDomain(
          domain,
        );
        if (!mounted) return;
        if (nativeCookies.isNotEmpty) {
          cookies = nativeCookies.map((c) => '${c.name}=${c.value}').join('; ');
          break;
        }
      }

      final headers = <String, String>{};
      if (currentUrl != null && currentUrl.isNotEmpty) {
        headers['Referer'] = currentUrl;
        try {
          final uri = Uri.parse(currentUrl);
          headers['Origin'] = '${uri.scheme}://${uri.host}';
        } catch (_) {}
      }
      final headersJson = headers.isNotEmpty ? jsonEncode(headers) : null;

      final filename =
          item.filename ??
          _generateFilename(item.downloadUrl!, item.originalCategory);

      final settingsPath = ref.read(downloadPathProvider);
      final basePath =
          settingsPath.isNotEmpty
              ? settingsPath
              : (await getDownloadsDirectory())?.path ??
                  (await getApplicationDocumentsDirectory()).path;
      final subdirectory = _categorySubdirectory(item.originalCategory);
      final savePath = p.join(basePath, subdirectory);
      await FileUtils.ensureDirectoryExists(savePath);
      if (!mounted) return;

      final repository = ref.read(downloadRepositoryProvider);
      final createResult = await repository.createDownload(
        url: item.downloadUrl!,
        filename: filename,
        savePath: savePath,
        downloadMethod: 'rust',
        platform: 'idm',
        sourceUrl: currentUrl ?? '',
        title: item.title ?? filename,
      );

      createResult.when(
        success: (download) async {
          final startResult = await repository.startDownload(
            download.id,
            numSegments: _suggestSegments(item),
            headersJson: headersJson,
            cookiesString: cookies,
          );
          startResult.when(
            success: (_) {
              if (mounted) {
                AppSnackBar.success(
                  context,
                  message: AppLocalizations.browserDownloadStartedNotice(
                    item.title ?? filename,
                  ),
                );
              }
            },
            failure: (e) {
              if (mounted) AppSnackBar.error(context, message: '$e');
            },
          );
        },
        failure: (e) {
          if (mounted) AppSnackBar.error(context, message: '$e');
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint('unknown'),
        );
      }
    }
  }

  Future<String?> _getPageUrl() async {
    try {
      return await widget.activeController?.currentUrl();
    } catch (_) {
      return null;
    }
  }

  int _suggestSegments(UnifiedMediaItem item) {
    if (item.type == MediaItemType.hlsManifest) return 1;
    if (item.supportsRange != true) return 1;
    final category = item.originalCategory;
    if (category == MediaCategory.video) {
      if (item.estimatedSize != null &&
          item.estimatedSize! > 50 * 1024 * 1024) {
        return 8;
      }
      return 4;
    }
    if (category == MediaCategory.audio) return 2;
    return 1;
  }

  String _generateFilename(String url, MediaCategory? category) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final last = pathSegments.last;
        if (last.contains('.') && last.length < 200) {
          return last.split('?').first;
        }
      }
    } catch (_) {}
    final ext = switch (category) {
      MediaCategory.video => '.mp4',
      MediaCategory.audio => '.mp3',
      MediaCategory.hlsStream => '.mp4',
      _ => '.bin',
    };
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'media_$ts$ext';
  }

  String _categorySubdirectory(MediaCategory? category) {
    return switch (category) {
      MediaCategory.video => 'Videos',
      MediaCategory.audio => 'Audio',
      MediaCategory.hlsStream => 'Videos',
      _ => 'Downloads',
    };
  }

  bool _ensureMediaSniffPremiumAccess() {
    if (!ref.read(premiumBootstrapReadyProvider)) {
      if (mounted) {
        AppSnackBar.info(
          context,
          message: AppLocalizations.homeCheckingPremiumLicense,
        );
      }
      return false;
    }

    if (ref.read(isPremiumProvider)) return true;

    ref.read(mediaSniffingEnabledProvider.notifier).setValue(false);
    UpgradePromptDialog.showAndNavigate(
      context,
      ref,
      feature: PremiumFeature.browserShield,
    );
    return false;
  }

  double _panelWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 980
        ? MediaSniffPanel.compactPanelWidth
        : MediaSniffPanel.panelWidth;
  }
}
