import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/intercepted_media.dart';
import '../../domain/services/cookie_inspector_service.dart';
import '../../domain/services/video_url_detector.dart';
import '../providers/content_filter_providers.dart';
import '../providers/media_detector_provider.dart';
import 'browser_bookmarks_panel.dart';
import 'browser_history_panel.dart';
import 'browser_security_indicators.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';

/// The browser's top toolbar containing navigation buttons, URL field,
/// bookmark toggle, history, bookmarks, external-open, and fullscreen buttons.
class BrowserToolbar extends ConsumerWidget {
  final TextEditingController urlController;
  final FocusNode urlFocusNode;
  final LayerLink layerLink;
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoading;
  final bool isBookmarked;
  final bool isFullscreen;
  final bool isExtracting;
  final VideoUrlDetection? detection;
  final AsyncValue<CookieSessionSummary?> sessionHealth;

  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onReloadOrStop;
  final VoidCallback onHome;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenExternal;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onPrefixDownloadTapped;
  final void Function(String url) onNavigateToUrl;
  final void Function(String url) onNavigateFromPanel;

  const BrowserToolbar({
    super.key,
    required this.urlController,
    required this.urlFocusNode,
    required this.layerLink,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoading,
    required this.isBookmarked,
    required this.isFullscreen,
    this.isExtracting = false,
    required this.detection,
    required this.sessionHealth,
    required this.onGoBack,
    required this.onGoForward,
    required this.onReloadOrStop,
    required this.onHome,
    required this.onToggleBookmark,
    required this.onOpenExternal,
    required this.onToggleFullscreen,
    this.onPrefixDownloadTapped,
    required this.onNavigateToUrl,
    required this.onNavigateFromPanel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUrl = urlController.text;
    final toolbarBg = AppColors.surface1(context);
    final fieldBg = AppColors.surface2(context);
    final outlineColor =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outline.withValues(alpha: AppOpacity.divider);
    final inputBorderColor =
        isDark
            ? AppColors.homeDarkInputBorder
            : cs.outline.withValues(alpha: AppOpacity.medium);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: toolbarBg,
        border: Border(bottom: BorderSide(color: outlineColor)),
      ),
      child: Row(
        children: [
          // Back
          IconButton(
            onPressed: canGoBack ? onGoBack : null,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            tooltip: AppLocalizations.browserBack,
            visualDensity: VisualDensity.compact,
          ),
          // Forward
          IconButton(
            onPressed: canGoForward ? onGoForward : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            tooltip: AppLocalizations.browserForward,
            visualDensity: VisualDensity.compact,
          ),
          // Refresh / Stop
          IconButton(
            onPressed: onReloadOrStop,
            icon: Icon(
              isLoading ? Icons.close_rounded : Icons.refresh_rounded,
              size: 20,
            ),
            tooltip:
                isLoading
                    ? AppLocalizations.browserStop
                    : AppLocalizations.browserRefresh,
            visualDensity: VisualDensity.compact,
          ),
          // Home
          IconButton(
            onPressed: onHome,
            icon: const Icon(Icons.home_rounded, size: 20),
            tooltip: AppLocalizations.browserHome,
            visualDensity: VisualDensity.compact,
          ),

          // Visual separator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: SizedBox(
              height: 20,
              child: VerticalDivider(
                width: 1,
                color:
                    isDark
                        ? AppColors.homeDarkBorderSubtle
                        : cs.outline.withValues(alpha: AppOpacity.subtle),
              ),
            ),
          ),

          // URL field
          Expanded(
            child: CompositedTransformTarget(
              link: layerLink,
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: urlController,
                  focusNode: urlFocusNode,
                  style: AppTypography.metadata.copyWith(
                    color: cs.onSurface,
                    fontWeight: AppTypography.medium,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.browserUrlPlaceholder,
                    hintStyle: AppTypography.buttonSecondary.copyWith(
                      color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                      fontWeight: FontWeight.w400,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(color: inputBorderColor, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(color: inputBorderColor, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(
                        color: AppColors.accentHighlight,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: fieldBg,
                    prefixIcon: _UrlBarPrefixIcon(
                      isVideoPage: detection != null && detection!.isVideoPage,
                      isExtracting: isExtracting,
                      onTap:
                          (detection != null && detection!.isVideoPage)
                              ? onPrefixDownloadTapped
                              : null,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 20,
                    ),
                  ),
                  onSubmitted: onNavigateToUrl,
                  onTap:
                      () =>
                          urlController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: urlController.text.length,
                          ),
                ),
              ),
            ),
          ),

          // Visual separator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: SizedBox(
              height: 20,
              child: VerticalDivider(
                width: 1,
                color:
                    isDark
                        ? AppColors.homeDarkBorderSubtle
                        : cs.outline.withValues(alpha: AppOpacity.subtle),
              ),
            ),
          ),

          // Bookmark toggle
          IconButton(
            onPressed: onToggleBookmark,
            icon: Icon(
              isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 20,
              color: isBookmarked ? AppColors.accentHighlight : null,
            ),
            tooltip:
                isBookmarked
                    ? AppLocalizations.browserRemoveBookmark
                    : AppLocalizations.browserAddBookmark,
            visualDensity: VisualDensity.compact,
          ),

          // History
          IconButton(
            onPressed:
                () => BrowserHistoryPanel.show(
                  context,
                  onNavigate: onNavigateFromPanel,
                ),
            icon: const Icon(Icons.history_rounded, size: 20),
            tooltip: AppLocalizations.browserHistory,
            visualDensity: VisualDensity.compact,
          ),

          // Bookmarks
          IconButton(
            onPressed:
                () => BrowserBookmarksPanel.show(
                  context,
                  onNavigate: onNavigateFromPanel,
                ),
            icon: const Icon(Icons.bookmarks_outlined, size: 20),
            tooltip: AppLocalizations.browserBookmarks,
            visualDensity: VisualDensity.compact,
          ),

          // Open external
          IconButton(
            onPressed: onOpenExternal,
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            tooltip: AppLocalizations.browserOpenExternal,
            visualDensity: VisualDensity.compact,
          ),

          // Fullscreen / immersive mode toggle
          IconButton(
            onPressed: onToggleFullscreen,
            icon: Icon(
              isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              size: 20,
            ),
            tooltip:
                isFullscreen
                    ? AppLocalizations.browserFullscreenExit
                    : AppLocalizations.browserFullscreenEnter,
            visualDensity: VisualDensity.compact,
          ),

          // Media sniff toggle (IDM mode)
          _MediaSniffButton(),

          // Security shield icon
          BrowserSecurityShield(currentUrl: currentUrl),

          // Session health indicator
          if (sessionHealth.valueOrNull != null)
            BrowserSessionHealthDot(summary: sessionHealth.valueOrNull!),
        ],
      ),
    );
  }
}

/// Animated prefix icon for the URL bar.
/// Shows globe (non-video) or tappable camcorder (video page detected).
/// Pulses when transitioning to video page, shows spinner when extracting.
class _UrlBarPrefixIcon extends StatefulWidget {
  final bool isVideoPage;
  final bool isExtracting;
  final VoidCallback? onTap;

  const _UrlBarPrefixIcon({
    required this.isVideoPage,
    required this.isExtracting,
    this.onTap,
  });

  @override
  State<_UrlBarPrefixIcon> createState() => _UrlBarPrefixIconState();
}

class _UrlBarPrefixIconState extends State<_UrlBarPrefixIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_UrlBarPrefixIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pulse when transitioning from non-video to video page
    if (widget.isVideoPage && !oldWidget.isVideoPage) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.isExtracting) {
      return const Padding(
        padding: EdgeInsets.only(left: AppSpacing.smMd, right: AppSpacing.sm),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (!widget.isVideoPage) {
      return Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.smMd,
          right: AppSpacing.sm,
        ),
        child: Icon(
          Icons.language_rounded,
          size: 16,
          color: cs.onSurface.withValues(alpha: AppOpacity.medium),
        ),
      );
    }

    return MouseRegion(
      cursor:
          widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
      child: Tooltip(
        message: AppLocalizations.browserDownloadVideo,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.smMd,
              right: AppSpacing.sm,
            ),
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Icon(
                Icons.videocam_rounded,
                size: 16,
                color: AppColors.accentHighlight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick toggle for IDM media sniffing mode.
/// Shows badge with detected media count when active.
class _MediaSniffButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(mediaSniffingEnabledProvider);
    final mediaList = ref.watch(interceptedMediaProvider);
    // Filter out segments for count display
    final count =
        mediaList
            .where((m) => m.category != MediaCategory.streamSegment)
            .length;

    return Badge(
      isLabelVisible: isEnabled && count > 0,
      label: Text('$count', style: AppTypography.mini.copyWith()),
      child: IconButton(
        onPressed: () {
          if (!isEnabled && !ref.read(isPremiumProvider)) {
            UpgradePromptDialog.showAndNavigate(
              context,
              ref,
              feature: PremiumFeature.browserShield,
            );
            return;
          }
          ref.read(mediaSniffingEnabledProvider.notifier).toggle();
        },
        icon: Icon(
          Icons.sensors_rounded,
          size: 20,
          color: isEnabled ? AppColors.accentHighlight : null,
        ),
        tooltip: AppLocalizations.browserMediaSniffEnabled,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
