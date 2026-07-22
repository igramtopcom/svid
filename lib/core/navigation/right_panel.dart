import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../core.dart';
import 'navigation_constants.dart';
import '../../features/browser/presentation/providers/browser_tab_providers.dart';
import '../../features/downloads/domain/entities/download_entity.dart';
import '../../features/downloads/domain/entities/download_error_code.dart';
import '../../features/downloads/presentation/providers/batch_selection_provider.dart';
import '../../features/downloads/presentation/providers/downloads_notifier.dart';
import '../../features/home/presentation/widgets/right_panel_item_view.dart';
import '../../features/player/presentation/screens/video_player_screen.dart';
import '../../features/player/presentation/screens/audio_player_screen.dart';
import '../../features/player/presentation/screens/image_viewer_screen.dart';
import 'right_panel_provider.dart';

/// Right panel — shows context-sensitive content
/// States: QuickStart (default), Detail (selected download)
class RightPanel extends ConsumerWidget {
  final void Function(String url)? onDownloadUrl;

  const RightPanel({super.key, this.onDownloadUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panelState = ref.watch(rightPanelProvider);

    // Multi-select takes precedence over the panel mode. When the user
    // long-presses to enter selection mode and ticks ≥2 items, the
    // sidebar surfaces a batch-aware summary instead of single-item
    // detail/player. A single selection still routes through the
    // standard `RightPanelMode.detail → RightPanelItemView` path so
    // the player surface stays available with one selection.
    final selectedIds = ref.watch(batchSelectionProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const lightPanelBg = Color(0xFFF9FAFB);
    const lightPanelBorder = Color(0xFFE5E7EB);

    // Glassmorphism: aurora bleeds through a frosted translucent wash so the
    // panel no longer reads as a separate island from the main canvas.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            // Lower alpha so cinematic aurora bleeds through — previous
            // 0.58/0.62 read as opaque island despite the backdrop blur.
            color:
                isDark
                    ? AppColors.darkBg.withValues(alpha: 0.38)
                    : lightPanelBg,
            border: Border(
              left: BorderSide(
                color:
                    isDark
                        ? AppColors.darkMuted.withValues(
                          alpha: AppOpacity.subtle,
                        )
                        : lightPanelBorder,
                width: 1,
              ),
            ),
          ),
          child: AnimatedSwitcher(
            // Short duration minimises the window where the outgoing
            // child's media_kit Player overlaps with the incoming
            // child's Player. PlayerManager auto-pauses overlapped
            // playback regardless, so the visual fade stays
            // pleasant — but a 50ms fade gives the embedded video
            // surface barely a frame to dispose vs 200ms of GPU
            // contention with rapidly clicked items.
            duration: const Duration(milliseconds: 80),
            child:
                selectedIds.isNotEmpty
                    ? RightPanelMultiSelectView(
                      // Sort id list so different selection orderings
                      // that resolve to the same set don't trigger a
                      // pointless rebuild + animation.
                      key: ValueKey(
                        'multi_${(selectedIds.toList()..sort()).join("_")}',
                      ),
                      selectedIds: selectedIds,
                    )
                    : switch (panelState.mode) {
                      RightPanelMode.quickStart => _QuickStartPanel(
                        key: const ValueKey('quickStart'),
                        onDownloadUrl: onDownloadUrl,
                      ),
                      RightPanelMode.detail =>
                        panelState.selectedDownload != null
                            ? RightPanelItemView(
                              // Key by download.id so swapping selection
                              // disposes the old player + state-aware
                              // body before constructing the new one.
                              key: ValueKey(
                                'item_${panelState.selectedDownload!.id}',
                              ),
                              download: panelState.selectedDownload!,
                            )
                            : _QuickStartPanel(
                              key: const ValueKey('quickStart'),
                              onDownloadUrl: onDownloadUrl,
                            ),
                      RightPanelMode.empty => const _EmptyPanel(
                        key: ValueKey('empty'),
                      ),
                    },
          ),
        ),
      ),
    );
  }
}

/// Quick Start panel — V2 mockup-aligned right rail.
///
/// Layout: 3 lightweight cards stacked vertically —
///   1. Quick start — 3-step onboarding (paste URL → extract → download)
///   2. Quick websites — 3×3 grid of platform shortcuts; tapping a
///      pill seeds the input field with the platform URL so the user
///      can refine in-place before extracting.
///   3. Tip card — drag-and-drop hint.
///
/// Removed from prior iteration:
///   - Clipboard radar shimmer / thumbnail / title preview (the
///     speculative auto-extract that double-fired yt-dlp; see
///     ClipboardRadarNotifier docstring).
///   - Session Pulse activity heartbeat + storage bar + commands menu.
///     Mockup has no equivalents and the animations cost render budget
///     for content the user rarely interacts with.
///   - Phím tắt list — moves to Settings → Keyboard shortcuts.
class _QuickStartPanel extends ConsumerWidget {
  final void Function(String url)? onDownloadUrl;

  const _QuickStartPanel({super.key, this.onDownloadUrl});

  // Platform shortcuts shown in the quick-websites 3×3 grid. Order
  // matches the V2 mockup. The 9th slot is "Thêm" (browser tab) so
  // platforms beyond the curated set are still reachable.
  static const List<_PlatformShortcut> _platforms = [
    _PlatformShortcut(
      name: 'YouTube',
      url: 'https://www.youtube.com',
      svgPath: 'assets/icons/platforms/youtube.svg',
      tint: Color(0xFFFF0000),
    ),
    _PlatformShortcut(
      name: 'TikTok',
      url: 'https://www.tiktok.com',
      svgPath: 'assets/icons/platforms/tiktok.svg',
      tint: Color(0xFF000000),
    ),
    _PlatformShortcut(
      name: 'Facebook',
      url: 'https://www.facebook.com',
      svgPath: 'assets/icons/platforms/facebook.svg',
      tint: Color(0xFF1877F2),
    ),
    _PlatformShortcut(
      name: 'Instagram',
      url: 'https://www.instagram.com',
      svgPath: 'assets/icons/platforms/instagram.svg',
      tint: Color(0xFFE4405F),
    ),
    _PlatformShortcut(
      name: 'X',
      url: 'https://www.x.com',
      svgPath: 'assets/icons/platforms/x.svg',
      tint: Color(0xFF000000),
    ),
    _PlatformShortcut(
      name: 'Reddit',
      url: 'https://www.reddit.com',
      svgPath: 'assets/icons/platforms/reddit.svg',
      tint: Color(0xFFFF4500),
    ),
    _PlatformShortcut(
      name: 'Pinterest',
      url: 'https://www.pinterest.com',
      svgPath: 'assets/icons/platforms/pinterest.svg',
      tint: Color(0xFFE60023),
    ),
    _PlatformShortcut(
      name: 'Vimeo',
      url: 'https://www.vimeo.com',
      svgPath: 'assets/icons/platforms/other.svg',
      tint: Color(0xFF1AB7EA),
    ),
    _PlatformShortcut(
      // Stored name is English baseline only — UI renders the localized
      // `AppLocalizations.rightPanelMoreSites` because `isOther` is true,
      // so this literal is never user-visible. Kept in English for code
      // consistency with the seeder + i18n shadow-fallback convention.
      name: 'More',
      url: '',
      svgPath: 'assets/icons/platforms/other.svg',
      tint: Color(0xFF757575),
      isOther: true,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tt = Theme.of(context).textTheme;

    return SizedBox.expand(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.mdLg,
          AppSpacing.lg,
          AppSpacing.mdLg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardSectionLabel(
              label: AppLocalizations.rightPanelQuickStart,
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.smMd),
            _OnboardingCard(isDark: isDark, cs: cs, tt: tt),

            const SizedBox(height: AppSpacing.mdLg),

            _CardSectionLabel(
              label: AppLocalizations.rightPanelQuickWebsites,
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.smMd),
            _PlatformsGrid(
              platforms: _platforms,
              onShortcutTap: (url) async {
                if (url.isEmpty) {
                  // "Thêm" — open browser tab on its default landing
                  // page so the user can discover platforms beyond the
                  // curated list.
                  ref
                      .read(navigationProvider.notifier)
                      .navigateToTab(NavigationConstants.browserIndex);
                  return;
                }
                // Spec §6.2 platform fork:
                //   macOS / Linux → in-app browser tab (webview_flutter)
                //   Windows       → system browser via url_launcher
                //                   (webview_flutter has no Windows support)
                if (Platform.isWindows) {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                  return;
                }
                ref.read(browserTabsProvider.notifier).addTab(url: url);
                ref
                    .read(navigationProvider.notifier)
                    .navigateToTab(NavigationConstants.browserIndex);
              },
              isDark: isDark,
            ),

            const SizedBox(height: AppSpacing.mdLg),

            _TipCard(isDark: isDark, cs: cs),
          ],
        ),
      ),
    );
  }
}

/// Lightweight platform shortcut model used by the right rail's
/// quick-websites grid. Local to this file — the home left-column
/// `popular_sites_grid.dart` keeps its own richer `PlatformInfo`.
class _PlatformShortcut {
  final String name;
  final String url;
  final String svgPath;
  final Color tint;
  final bool isOther;

  const _PlatformShortcut({
    required this.name,
    required this.url,
    required this.svgPath,
    required this.tint,
    this.isOther = false,
  });
}

class _CardSectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _CardSectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            // Neutral marker — accent (wine red) is reserved for the primary
            // Download CTA and the active tab, not decorative section dots.
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.buttonSecondary.copyWith(
            fontSize: 13,
            color:
                isDark
                    ? AppColors.darkLightText
                    : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;
  final TextTheme tt;
  const _OnboardingCard({
    required this.isDark,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        icon: Icons.content_paste_rounded,
        title: AppLocalizations.rightPanelStepPasteTitle,
        body: AppLocalizations.rightPanelStepPasteBody,
      ),
      (
        icon: Icons.tune_rounded,
        title: AppLocalizations.rightPanelStepChooseTitle,
        body: AppLocalizations.rightPanelStepChooseBody,
      ),
      (
        icon: Icons.download_rounded,
        title: AppLocalizations.rightPanelStepDownloadTitle,
        body: AppLocalizations.rightPanelStepDownloadBody,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.darkMuted.withValues(alpha: AppOpacity.subtle)
                  : cs.outlineVariant.withValues(alpha: AppOpacity.subtle),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _OnboardingStepRow(step: steps[i], isDark: isDark, cs: cs, tt: tt),
            if (i < steps.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _OnboardingStepRow extends StatelessWidget {
  final ({IconData icon, String title, String body}) step;
  final bool isDark;
  final ColorScheme cs;
  final TextTheme tt;
  const _OnboardingStepRow({
    required this.step,
    required this.isDark,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.hover,
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Icon(step.icon, size: 17, color: AppColors.accentHighlight),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: isDark ? AppColors.darkLightText : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step.body,
                style: tt.bodySmall?.copyWith(
                  color: AppColors.metaText(context),
                  fontSize: 11.5,
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlatformsGrid extends StatelessWidget {
  final List<_PlatformShortcut> platforms;
  final ValueChanged<String> onShortcutTap;
  final bool isDark;
  const _PlatformsGrid({
    required this.platforms,
    required this.onShortcutTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.18,
      children:
          platforms
              .map(
                (p) => _PlatformShortcutTile(
                  shortcut: p,
                  onTap: () => onShortcutTap(p.url),
                  isDark: isDark,
                ),
              )
              .toList(),
    );
  }
}

class _PlatformShortcutTile extends StatefulWidget {
  final _PlatformShortcut shortcut;
  final VoidCallback onTap;
  final bool isDark;
  const _PlatformShortcutTile({
    required this.shortcut,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_PlatformShortcutTile> createState() => _PlatformShortcutTileState();
}

class _PlatformShortcutTileState extends State<_PlatformShortcutTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logoColor =
        widget.isDark &&
                (widget.shortcut.name == 'TikTok' ||
                    widget.shortcut.name == 'X' ||
                    widget.shortcut.name == 'Vimeo')
            ? AppColors.darkLightText
            : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color:
                widget.isDark
                    ? (_hovered
                        ? AppColors.homeDarkCardHover
                        : AppColors.homeDarkCardBg)
                    : (_hovered
                        ? cs.surfaceContainerHigh
                        : cs.surfaceContainerLowest),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  widget.isDark
                      ? AppColors.darkMuted.withValues(alpha: AppOpacity.subtle)
                      : cs.outlineVariant.withValues(alpha: AppOpacity.subtle),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.shortcut.isOther
                  ? Icon(
                    Icons.more_horiz_rounded,
                    size: 23,
                    color: AppColors.metaText(context),
                  )
                  : SvgPicture.asset(
                    widget.shortcut.svgPath,
                    width: 23,
                    height: 23,
                    colorFilter:
                        logoColor == null
                            ? null
                            : ColorFilter.mode(logoColor, BlendMode.srcIn),
                    errorBuilder:
                        (_, __, ___) => Icon(
                          Icons.public_rounded,
                          size: 23,
                          color: logoColor ?? widget.shortcut.tint,
                        ),
                  ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.shortcut.isOther
                    ? AppLocalizations.rightPanelMoreSites
                    : widget.shortcut.name,
                style: AppTypography.metadata.copyWith(
                  color: AppColors.metaText(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;
  const _TipCard({required this.isDark, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color:
            isDark
                ? AppColors.darkMuted.withValues(alpha: AppOpacity.hover)
                : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: AppColors.metaText(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.rightPanelQuickTip,
              style: AppTypography.metadata.copyWith(
                color: AppColors.metaText(context),
                fontSize: 11.5,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Download detail panel — "The Dossier"
/// Nocturne Cinematic redesign: tonal layering, wine red accents, no borders.
///
/// Superseded by [RightPanelItemView] (state-aware item view with
/// embedded player for completed items + status-specific bodies).
/// Kept here for reference / potential UI agent revival of specific
/// metadata sections — removal can be a separate cleanup once the
/// new flow stabilises.
// ignore: unused_element
class _DownloadDetailPanel extends ConsumerWidget {
  final DownloadEntity download;

  // ignore: unused_element_parameter
  const _DownloadDetailPanel({super.key, required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFileMissing = ref
        .watch(downloadsNotifierProvider)
        .isFileMissing(download.id);

    return Column(
      children: [
        // Header
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                IconButton(
                  onPressed:
                      () =>
                          ref
                              .read(rightPanelProvider.notifier)
                              .showQuickStart(),
                  icon: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color:
                        isDark
                            ? AppColors.darkMetaText
                            : cs.onSurface.withValues(
                              alpha: AppOpacity.overlay,
                            ),
                  ),
                  tooltip: AppLocalizations.commonBack,
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppLocalizations.homeDownloadDetails.toUpperCase(),
                  style: tt.labelMedium?.copyWith(
                    color: isDark ? AppColors.darkLightText : cs.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),

                // Hero thumbnail with ambient glow
                if (download.thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdLg,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Ambient glow (dark mode only)
                        if (isDark)
                          Positioned(
                            bottom: -4,
                            left: 16,
                            right: 16,
                            child: Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(
                                  alpha: AppOpacity.scrim,
                                ),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const SizedBox.shrink(),
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: AppCachedImage(
                              imageUrl: download.thumbnail,
                              width: double.infinity,
                              height: 200,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: AppSpacing.mdLg),

                // Title cluster
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + status badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              download.displayTitle,
                              style: tt.titleMedium?.copyWith(
                                color:
                                    isDark
                                        ? AppColors.darkLightText
                                        : cs.onSurface,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _StatusBadge(download: download),
                        ],
                      ),
                      // Uploader
                      if (download.uploader != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          download.uploader!,
                          style: AppTypography.metadata.copyWith(
                            color:
                                isDark
                                    ? AppColors.darkMetaText
                                    : cs.onSurface.withValues(
                                      alpha: AppOpacity.medium,
                                    ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Progress zone (active/paused downloads)
                if (download.isActive || download.isPaused) ...[
                  const SizedBox(height: AppSpacing.mdLg),
                  _buildProgressZone(context),
                ],

                const SizedBox(height: AppSpacing.mdLg),

                // Metadata section — "The Intel"
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdLg,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.darkBase : AppColors.lightSurface2,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      children: [
                        if (download.qualityLabel != null)
                          _IntelRow(
                            icon: Icons.high_quality_outlined,
                            label: AppLocalizations.homeQuality,
                            value: download.qualityLabel!,
                            isFirst: true,
                          ),
                        if (download.fileExtension.isNotEmpty)
                          _IntelRow(
                            icon: Icons.description_outlined,
                            label: AppLocalizations.homeFormat,
                            value:
                                download.fileExtension
                                    .replaceAll('.', '')
                                    .toUpperCase(),
                          ),
                        if (download.formattedDuration != null)
                          _IntelRow(
                            icon: Icons.timer_outlined,
                            label: AppLocalizations.homeDuration,
                            value: download.formattedDuration!,
                          ),
                        if (download.totalBytes > 0)
                          _IntelRow(
                            icon: Icons.straighten_outlined,
                            label: AppLocalizations.homeFileSize,
                            value: FileUtils.formatBytes(download.totalBytes),
                          ),
                        _IntelRow(
                          icon: Icons.calendar_today_outlined,
                          label: AppLocalizations.homeDate,
                          value: Formatters.formatDate(download.createdAt),
                        ),
                        if (download.platform.isNotEmpty &&
                            download.platform != 'unknown')
                          _IntelRow(
                            icon: Icons.language,
                            label: AppLocalizations.homePlatform,
                            value: download.platform,
                          ),
                        _IntelRow(
                          icon: Icons.link,
                          label: 'URL',
                          value: download.url,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),

                // Error message
                if (download.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdLg,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.smMd),
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? AppColors.errorRed.withValues(
                                  alpha: AppOpacity.subtle,
                                )
                                : cs.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: cs.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              download.errorCode?.hint ?? 'Download failed',
                              style: tt.labelMedium?.copyWith(color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // File missing warning
                if (isFileMissing) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdLg,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.smMd),
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? AppColors.errorRed.withValues(
                                  alpha: AppOpacity.subtle,
                                )
                                : cs.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                size: 16,
                                color: cs.error,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  AppLocalizations.downloadsFileMissing,
                                  style: tt.labelMedium?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 28,
                            child: TextButton.icon(
                              onPressed: () async {
                                final notifier = ref.read(
                                  downloadsNotifierProvider.notifier,
                                );
                                final count =
                                    await notifier.deleteOrphanedDownloads();
                                if (count > 0 && context.mounted) {
                                  AppSnackBar.success(
                                    context,
                                    message:
                                        AppLocalizations.downloadsCleanMissingDone(
                                          count,
                                        ),
                                    duration: const Duration(seconds: 2),
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.cleaning_services_rounded,
                                size: 14,
                                color: cs.error,
                              ),
                              label: Text(
                                AppLocalizations.downloadsCleanMissing,
                                style: tt.labelSmall?.copyWith(color: cs.error),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdLg,
                  ),
                  child: _buildActions(context, ref, isFileMissing),
                ),
              ],
            ),
          ),
        ),

        // Bottom gradient accent line
        if (isDark)
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.brand.withValues(alpha: AppOpacity.quarter),
                  Colors.transparent,
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Progress Zone ────────────────────────────────────────────

  Widget _buildProgressZone(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdLg),
      child: Column(
        children: [
          // Progress bar — 3px, crimson with bloom
          Container(
            height: 3,
            decoration: BoxDecoration(
              color:
                  isDark ? AppColors.darkSurface3 : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: download.progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accentHighlight,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow:
                        isDark
                            ? [
                              BoxShadow(
                                color: AppColors.brand.withValues(
                                  alpha: AppOpacity.medium,
                                ),
                                blurRadius: 12,
                              ),
                            ]
                            : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${download.progressPercentage.toStringAsFixed(0)}%',
                    style: AppTypography.statusBadge.copyWith(
                      color: AppColors.accentHighlight,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${FileUtils.formatBytes(download.downloadedBytes)} / ${FileUtils.formatBytes(download.totalBytes)}',
                    style: AppTypography.compact.copyWith(
                      color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (download.speed > 0 &&
                      download.estimatedRemainingSeconds != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color: AppColors.accentHighlight,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          Formatters.formatDuration(
                            Duration(
                              seconds: download.estimatedRemainingSeconds!,
                            ),
                          ),
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withValues(
                              alpha: AppOpacity.nearOpaque,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (download.speed > 0) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      Formatters.formatSpeed(download.speed),
                      style: AppTypography.compact.copyWith(
                        color: cs.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Action Buttons ───────────────────────────────────────────

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    bool isFileMissing,
  ) {
    final notifier = ref.read(downloadsNotifierProvider.notifier);

    return Column(
      children: [
        // Primary action — full width wine red gradient (or pause/resume)
        if (download.isCompleted && !isFileMissing)
          _DossierButton(
            icon: Icons.play_arrow,
            label: AppLocalizations.homeOpen,
            isPrimary: true,
            onTap: () => _openPlayer(context),
          ),
        if (download.canPause)
          _DossierButton(
            icon: Icons.pause_rounded,
            label: AppLocalizations.downloadsPause,
            isPrimary: true,
            onTap: () => notifier.pauseDownload(download.id),
          ),
        if (download.canResume)
          _DossierButton(
            icon: Icons.play_arrow_rounded,
            label: AppLocalizations.downloadsResume,
            isPrimary: true,
            onTap: () => notifier.resumeDownload(download.id),
          ),
        if (download.canRetry)
          _DossierButton(
            icon: Icons.refresh_rounded,
            label: AppLocalizations.commonRetry,
            isPrimary: true,
            onTap: () => notifier.retryDownload(download.id),
          ),

        // Secondary actions — 2-column grid
        if (download.isCompleted && !isFileMissing) ...[
          const SizedBox(height: AppSpacing.smMd),
          Row(
            children: [
              Expanded(
                child: _DossierButton(
                  icon: Icons.folder_open_outlined,
                  label: AppLocalizations.downloadsOpenLocation,
                  onTap: () => _openFileLocation(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: _DossierButton(
                  icon: Icons.content_copy,
                  label: AppLocalizations.downloadsCopyUrl,
                  onTap: () => _copyUrl(context),
                ),
              ),
            ],
          ),
        ] else ...[
          // Single copy URL button when not completed
          const SizedBox(height: AppSpacing.smMd),
          _DossierButton(
            icon: Icons.content_copy,
            label: AppLocalizations.downloadsCopyUrl,
            onTap: () => _copyUrl(context),
          ),
        ],

        // Cancel (if active)
        if (download.canCancel) ...[
          const SizedBox(height: AppSpacing.smMd),
          _DossierButton(
            icon: Icons.stop_rounded,
            label: AppLocalizations.commonCancel,
            isDestructive: true,
            onTap: () => notifier.cancelDownload(download.id),
          ),
        ],

        // Delete — ghost destructive
        if (download.canDelete) ...[
          const SizedBox(height: AppSpacing.smMd),
          _DossierButton(
            icon: Icons.delete_outline,
            label: AppLocalizations.commonDelete,
            isDestructive: true,
            onTap: () => _showDeleteDialog(context, ref),
          ),
        ],
      ],
    );
  }

  void _openPlayer(BuildContext context) {
    if (!download.isCompleted) return;
    final filePath = p.join(download.savePath, download.filename);
    if (!File(filePath).existsSync()) return;

    if (FileUtils.isVideoFile(download.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(download: download),
        ),
      );
    } else if (FileUtils.isAudioFile(download.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioPlayerScreen(download: download),
        ),
      );
    } else if (FileUtils.isImageFile(download.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(download: download),
        ),
      );
    }
  }

  Future<void> _openFileLocation(BuildContext context, WidgetRef ref) async {
    final filePath = p.join(download.savePath, download.filename);
    if (!File(filePath).existsSync()) return;

    if (Platform.isMacOS) {
      await ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      );
    } else if (Platform.isWindows) {
      await ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      );
    } else if (Platform.isLinux) {
      await ProcessHelper.openDirectoryInFileManager(download.savePath);
    }
  }

  Future<void> _copyUrl(BuildContext context) async {
    await ClipboardService.setText(download.url);
    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.downloadsUrlCopied,
      );
    }
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? AppColors.darkBase : cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side:
                  isDark
                      ? BorderSide(
                        color: AppColors.darkMuted.withValues(
                          alpha: AppOpacity.subtle,
                        ),
                      )
                      : BorderSide.none,
            ),
            title: Text(
              AppLocalizations.downloadsDeleteDialogTitle,
              style:
                  isDark
                      ? Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.darkLightText,
                      )
                      : null,
            ),
            content: Text(
              AppLocalizations.downloadsDeleteDialogMessage(download.filename),
              style:
                  isDark
                      ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.darkMetaText,
                      )
                      : null,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref
                      .read(downloadsNotifierProvider.notifier)
                      .deleteDownload(download.id, deleteFile: false);
                  ref.read(rightPanelProvider.notifier).showQuickStart();
                },
                child: Text(AppLocalizations.downloadsDeleteRecordOnly),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref
                      .read(downloadsNotifierProvider.notifier)
                      .deleteDownload(download.id, deleteFile: true);
                  ref.read(rightPanelProvider.notifier).showQuickStart();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
                child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
              ),
            ],
          ),
    );
  }
}

/// Status badge — inline pill next to title
class _StatusBadge extends StatelessWidget {
  final DownloadEntity download;
  const _StatusBadge({required this.download});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;

    if (download.isCompleted) {
      bgColor = AppColors.statusCompletedContainer(context);
      textColor = AppColors.statusCompleted(context);
    } else if (download.isActive) {
      bgColor = AppColors.statusActiveContainer(context);
      textColor = AppColors.statusActive(context);
    } else if (download.isPaused) {
      bgColor = AppColors.statusPausedContainer(context);
      textColor = AppColors.statusPaused(context);
    } else if (download.isFailed) {
      bgColor = AppColors.statusFailedContainer(context);
      textColor = AppColors.statusFailed(context);
    } else {
      bgColor = AppColors.statusCancelledContainer(context);
      textColor = AppColors.statusCancelled(context);
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        download.status.displayLabel,
        style: AppTypography.compact.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Metadata row — "The Intel" style
class _IntelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;

  const _IntelRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : Border(
                  bottom: BorderSide(
                    color:
                        isDark
                            ? AppColors.darkMuted.withValues(
                              alpha: AppOpacity.subtle,
                            )
                            : Colors.black.withValues(
                              alpha: AppOpacity.divider,
                            ),
                    width: 0.5,
                  ),
                ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.muted(context)),
          const SizedBox(width: AppSpacing.smMd),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.metaText(context),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color:
                    isDark
                        ? AppColors.darkLightText
                        : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Action button — Dossier style
class _DossierButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDestructive;

  const _DossierButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPrimary) {
      return SizedBox(
        width: double.infinity,
        height: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brand, AppColors.brandDark],
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final fgColor =
        isDestructive
            ? cs.error.withValues(alpha: AppOpacity.secondary)
            : cs.onSurface.withValues(alpha: AppOpacity.strong);

    return SizedBox(
      width: double.infinity,
      height: 36,
      child: Material(
        color:
            isDestructive
                ? Colors.transparent
                : (isDark ? AppColors.darkBase : AppColors.lightSurface2),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          hoverColor:
              isDestructive
                  ? cs.error.withValues(alpha: AppOpacity.divider)
                  : (isDark ? AppColors.darkSurface1 : AppColors.lightSurface3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label.toUpperCase(),
                style: AppTypography.statusBadge.copyWith(
                  color: fgColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty panel — dormant terminal state
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ads_click,
              size: 32,
              color:
                  isDark
                      ? AppColors.darkMetaText
                      : Colors.black.withValues(alpha: AppOpacity.pressed),
            ),
            const SizedBox(height: AppSpacing.smMd),
            Text(
              AppLocalizations.homeSelectDownload,
              textAlign: TextAlign.center,
              style: AppTypography.metadata.copyWith(
                color: AppColors.muted(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
