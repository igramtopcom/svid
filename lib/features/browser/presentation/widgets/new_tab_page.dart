import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../domain/entities/browser_bookmark.dart';
import '../../domain/entities/browser_history_entry.dart';
import '../providers/browser_tab_providers.dart';
import '../providers/content_filter_providers.dart';

/// New tab command center with search, recent downloads, and quick access.
class NewTabPage extends ConsumerWidget {
  const NewTabPage({
    super.key,
    required this.onNavigate,
    required this.onSearch,
  });

  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onSearch;

  static const _defaultPlatforms = [
    _PlatformSite('https://www.youtube.com', 'YouTube', 'youtube'),
    _PlatformSite('https://www.instagram.com', 'Instagram', 'instagram'),
    _PlatformSite('https://x.com', 'X', 'x'),
    _PlatformSite('https://www.reddit.com', 'Reddit', 'reddit'),
    _PlatformSite('https://vimeo.com', 'Vimeo', 'vimeo'),
    _PlatformSite('https://soundcloud.com', 'SoundCloud', 'soundcloud'),
    _PlatformSite('https://www.facebook.com', 'Facebook', 'facebook'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyService = ref.watch(browserHistoryServiceProvider);
    final bookmarkService = ref.watch(browserBookmarkServiceProvider);
    final downloadsState = ref.watch(downloadsNotifierProvider);

    // Recent completed downloads (last 4)
    final recentDownloads =
        downloadsState.downloads
            .where((d) => d.status == DownloadStatus.completed)
            .take(4)
            .toList();

    // Top visited sites for quick access
    final topSites = _getTopVisitedSites(historyService.entries, 8);
    final displaySites = _mergeWithDefaults(topSites, 8);

    // Download stats for telemetry bar
    final totalDownloads = downloadsState.downloads.length;
    final totalBytes = downloadsState.downloads
        .where((d) => d.status == DownloadStatus.completed)
        .fold<int>(0, (sum, d) => sum + d.totalBytes);

    final cardBg = AppColors.surface2(context);
    final elevatedBg = AppColors.surface1(context);
    final textPrimary = isDark ? AppColors.darkLightText : cs.onSurface;
    final textSecondary =
        isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurface.withValues(alpha: AppOpacity.secondary);
    final textTertiary =
        isDark
            ? AppColors.homeDarkTextMuted
            : cs.onSurface.withValues(alpha: AppOpacity.scrim);

    return Container(
      color: AppColors.surface1(context),
      child: Column(
        children: [
          // Main scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Center(
                        child: _MissionControlSearch(
                          onSearch: onSearch,
                          onNavigate: onNavigate,
                          cardBg: cardBg,
                          textSecondary: textSecondary,
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            AppLocalizations.newTabSearchHint,
                            style: AppTypography.compact.copyWith(
                              color: textTertiary,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 640;
                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: Recent Downloads
                                Expanded(
                                  flex: 3,
                                  child: _RecentDownloadsSection(
                                    downloads: recentDownloads,
                                    cardBg: cardBg,
                                    textPrimary: textPrimary,
                                    textSecondary: textSecondary,
                                    textTertiary: textTertiary,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xl),
                                // Right: Platforms
                                Expanded(
                                  flex: 2,
                                  child: _PlatformsSection(
                                    sites: displaySites,
                                    onNavigate: onNavigate,
                                    cardBg: cardBg,
                                    elevatedBg: elevatedBg,
                                    textPrimary: textPrimary,
                                    textSecondary: textSecondary,
                                    textTertiary: textTertiary,
                                  ),
                                ),
                              ],
                            );
                          }
                          // Narrow: stack vertically
                          return Column(
                            children: [
                              _RecentDownloadsSection(
                                downloads: recentDownloads,
                                cardBg: cardBg,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                textTertiary: textTertiary,
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              _PlatformsSection(
                                sites: displaySites,
                                onNavigate: onNavigate,
                                cardBg: cardBg,
                                elevatedBg: elevatedBg,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                                textTertiary: textTertiary,
                              ),
                            ],
                          );
                        },
                      ),

                      // Recent bookmarks
                      if (bookmarkService.bookmarks.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        _BookmarksSection(
                          bookmarks: bookmarkService.bookmarks.take(6).toList(),
                          onNavigate: onNavigate,
                          textTertiary: textTertiary,
                          textSecondary: textSecondary,
                          cardBg: cardBg,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── System Telemetry Bar ──
          _TelemetryBar(
            totalDownloads: totalDownloads,
            totalBytes: totalBytes,
            elevatedBg: elevatedBg,
            textTertiary: textTertiary,
          ),
        ],
      ),
    );
  }

  static List<_QuickAccessSite> _getTopVisitedSites(
    List<BrowserHistoryEntry> entries,
    int count,
  ) {
    final seen = <String, _QuickAccessSite>{};
    for (final entry in entries) {
      if (entry.url.isEmpty ||
          entry.url == 'about:blank' ||
          entry.url.startsWith('data:')) {
        continue;
      }
      final host = Uri.tryParse(entry.url)?.host ?? '';
      if (host.isEmpty) continue;
      // TikTok crashes the WebView2 engine on Windows — keep it out of quick access.
      if (host.toLowerCase().contains('tiktok')) continue;

      if (!seen.containsKey(host)) {
        seen[host] = _QuickAccessSite(
          url: entry.url,
          title: entry.title.isNotEmpty ? entry.title : host,
          host: host,
          platform: _detectPlatform(host),
        );
      }
    }
    return seen.values.take(count).toList();
  }

  static List<_QuickAccessSite> _mergeWithDefaults(
    List<_QuickAccessSite> historySites,
    int count,
  ) {
    if (historySites.length >= count) return historySites.take(count).toList();

    final merged = [...historySites];
    final existingHosts = merged.map((s) => s.host).toSet();

    for (final def in _defaultPlatforms) {
      if (merged.length >= count) break;
      final host = Uri.tryParse(def.url)?.host ?? '';
      if (!existingHosts.contains(host)) {
        merged.add(
          _QuickAccessSite(
            url: def.url,
            title: def.name,
            host: host,
            platform: def.platform,
          ),
        );
        existingHosts.add(host);
      }
    }

    return merged;
  }

  static String _detectPlatform(String host) {
    final h = host.toLowerCase();
    if (h.contains('youtube') || h.contains('youtu.be')) return 'youtube';
    if (h.contains('facebook') || h.contains('fb.com')) return 'facebook';
    if (h.contains('instagram')) return 'instagram';
    if (h.contains('tiktok')) return 'tiktok';
    if (h.contains('twitter') || h == 'x.com') return 'x';
    if (h.contains('reddit')) return 'reddit';
    if (h.contains('pinterest')) return 'pinterest';
    if (h.contains('vimeo')) return 'vimeo';
    if (h.contains('soundcloud')) return 'soundcloud';
    return '';
  }
}

// ── Mission Control Search Input ──

class _MissionControlSearch extends ConsumerStatefulWidget {
  const _MissionControlSearch({
    required this.onSearch,
    required this.onNavigate,
    required this.cardBg,
    required this.textSecondary,
  });

  final ValueChanged<String> onSearch;
  final ValueChanged<String> onNavigate;
  final Color cardBg;
  final Color textSecondary;

  @override
  ConsumerState<_MissionControlSearch> createState() =>
      _MissionControlSearchState();
}

class _MissionControlSearchState extends ConsumerState<_MissionControlSearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(selectedSearchEngineProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Crimson glow when focused — from Stitch token: 0 0 25px -5px #C41E3A
          boxShadow:
              _isFocused
                  ? [
                    BoxShadow(
                      color: AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.quarter,
                      ),
                      blurRadius: 25,
                      spreadRadius: -5,
                    ),
                  ]
                  : [],
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          style: AppTypography.appBarTitle.copyWith(
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: AppLocalizations.newTabSearchPlaceholder(engine.label),
            hintStyle: AppTypography.appBarTitle.copyWith(
              fontWeight: FontWeight.w400,
              color: widget.textSecondary.withValues(alpha: AppOpacity.overlay),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(
                Icons.search_rounded,
                color:
                    _isFocused
                        ? AppColors.accentHighlight
                        : widget.textSecondary,
                size: 22,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 46,
              minHeight: 0,
            ),
            suffixIcon: Container(
              margin: const EdgeInsets.all(AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smMd,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight.withValues(
                  alpha: AppOpacity.pressed,
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                engine.label,
                style: AppTypography.compact.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentHighlight,
                  letterSpacing: 0,
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdLg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : Theme.of(context).colorScheme.outline.withValues(
                          alpha: AppOpacity.medium,
                        ),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : Theme.of(context).colorScheme.outline.withValues(
                          alpha: AppOpacity.medium,
                        ),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkInputBorder
                        : AppColors.accentHighlight,
                width: 1,
              ),
            ),
            filled: true,
            fillColor: widget.cardBg,
          ),
          onSubmitted: (query) {
            final trimmed = query.trim();
            if (trimmed.isEmpty) return;
            // If it looks like a URL, navigate directly
            if (trimmed.contains('.') && !trimmed.contains(' ')) {
              widget.onNavigate(trimmed);
            } else {
              widget.onSearch(trimmed);
            }
          },
        ),
      ),
    );
  }
}

// ── Recent Downloads Section ──

class _RecentDownloadsSection extends StatelessWidget {
  const _RecentDownloadsSection({
    required this.downloads,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  final List<DownloadEntity> downloads;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionHeaderColor = isDark ? Colors.white : Colors.black;
    final outlineColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: AppOpacity.subtle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: AppLocalizations.homeRecentDownloads,
          icon: Icons.download_done_rounded,
          textColor: sectionHeaderColor,
        ),
        const SizedBox(height: AppSpacing.smMd),
        if (downloads.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  isDark
                      ? Border.all(color: AppColors.homeDarkBorderSubtle)
                      : Border.all(color: outlineColor),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_download_outlined,
                    size: 32,
                    color: textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.homeNoCompletedDownloads,
                    style: AppTypography.statusBadge.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textTertiary,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...downloads.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _DownloadCard(
                download: d,
                cardBg: cardBg,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _DownloadCard extends StatefulWidget {
  const _DownloadCard({
    required this.download,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  final DownloadEntity download;
  final Color cardBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  @override
  State<_DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<_DownloadCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d = widget.download;
    final platform = d.platform;
    final hasPlatformIcon =
        platform.isNotEmpty &&
        platform != 'unknown' &&
        PlatformStyleHelper.hasSvgIcon(platform);
    final platformColor =
        hasPlatformIcon
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : AppColors.accentHighlight;
    final timeAgo = _formatTimeAgo(d.updatedAt);
    final sizeText =
        d.totalBytes > 0 ? FileUtils.formatBytes(d.totalBytes) : '';
    final outlineColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: AppOpacity.subtle);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.smMd,
        ),
        decoration: BoxDecoration(
          color:
              _isHovered
                  ? widget.cardBg.withValues(alpha: AppOpacity.nearOpaque)
                  : widget.cardBg.withValues(alpha: AppOpacity.overlay),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border:
              isDark
                  ? Border.all(
                    color:
                        _isHovered
                            ? AppColors.homeDarkBorderStrong
                            : AppColors.homeDarkBorderSubtle,
                  )
                  : Border.all(color: outlineColor),
        ),
        child: Row(
          children: [
            // Thumbnail / platform icon
            _RecentDownloadThumbnail(
              thumbnail: d.thumbnail,
              platform: platform,
              platformColor: platformColor,
              hasPlatformIcon: hasPlatformIcon,
            ),
            const SizedBox(width: AppSpacing.smMd),
            // Title + metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title ?? d.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.platformName.copyWith(
                      color: widget.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      if (platform.isNotEmpty && platform != 'unknown')
                        Text(
                          platform,
                          style: AppTypography.mini.copyWith(
                            color: platformColor,
                            letterSpacing: 0,
                          ),
                        ),
                      if (sizeText.isNotEmpty)
                        Text(
                          sizeText,
                          style: AppTypography.compact.copyWith(
                            color: widget.textSecondary,
                          ),
                        ),
                      Text(
                        timeAgo,
                        style: AppTypography.compact.copyWith(
                          color: widget.textTertiary,
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

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Platforms Section ──

class _PlatformsSection extends StatelessWidget {
  const _PlatformsSection({
    required this.sites,
    required this.onNavigate,
    required this.cardBg,
    required this.elevatedBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  final List<_QuickAccessSite> sites;
  final ValueChanged<String> onNavigate;
  final Color cardBg;
  final Color elevatedBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionHeaderColor = isDark ? Colors.white : Colors.black;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: AppLocalizations.newTabQuickAccess,
          icon: Icons.grid_view_rounded,
          textColor: sectionHeaderColor,
        ),
        const SizedBox(height: AppSpacing.smMd),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns =
                width >= 520
                    ? 4
                    : width >= 360
                    ? 3
                    : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: width < 360 ? 1.18 : 1.0,
              ),
              itemCount: sites.length,
              itemBuilder: (context, index) {
                final site = sites[index];
                return _PlatformTile(
                  site: site,
                  onTap: () => onNavigate(site.url),
                  cardBg: cardBg,
                  textSecondary: textSecondary,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _PlatformTile extends StatefulWidget {
  const _PlatformTile({
    required this.site,
    required this.onTap,
    required this.cardBg,
    required this.textSecondary,
  });

  final _QuickAccessSite site;
  final VoidCallback onTap;
  final Color cardBg;
  final Color textSecondary;

  @override
  State<_PlatformTile> createState() => _PlatformTileState();
}

class _PlatformTileState extends State<_PlatformTile> {
  bool _isHovered = false;

  /// Get first letter from title or host (stripping www. prefix).
  String _siteInitial(_QuickAccessSite site) {
    // Prefer title's first letter
    if (site.title.isNotEmpty) return site.title[0].toUpperCase();
    // Strip www. from host
    var host = site.host;
    if (host.startsWith('www.')) host = host.substring(4);
    return host.isNotEmpty ? host[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final platform = widget.site.platform;
    final hasPlatformIcon =
        platform.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platform);
    final platformColor =
        hasPlatformIcon
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : AppColors.accentHighlight;
    final outlineColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: AppOpacity.subtle);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color:
                _isHovered
                    ? platformColor.withValues(alpha: AppOpacity.hover)
                    : widget.cardBg.withValues(alpha: AppOpacity.medium),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                isDark
                    ? (_isHovered
                        ? Border.all(
                          color: Colors.white.withValues(
                            alpha: AppOpacity.medium,
                          ),
                        )
                        : null)
                    : Border.all(color: outlineColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      _isHovered
                          ? platformColor.withValues(alpha: AppOpacity.subtle)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child:
                      hasPlatformIcon
                          ? PlatformIcon(platform: platform, size: 22)
                          : Text(
                            _siteInitial(widget.site),
                            style: AppTypography.appBarTitle.copyWith(
                              fontSize: 18,
                              color: platformColor,
                            ),
                          ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.site.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.compact.copyWith(
                  color:
                      _isHovered
                          ? (isDark ? Colors.white : platformColor)
                          : widget.textSecondary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bookmarks Section ──

class _BookmarksSection extends StatelessWidget {
  const _BookmarksSection({
    required this.bookmarks,
    required this.onNavigate,
    required this.textTertiary,
    required this.textSecondary,
    required this.cardBg,
  });

  final List<BrowserBookmark> bookmarks;
  final ValueChanged<String> onNavigate;
  final Color textTertiary;
  final Color textSecondary;
  final Color cardBg;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outlineColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: AppOpacity.subtle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: AppLocalizations.newTabRecentBookmarks,
          icon: Icons.bookmark_outline_rounded,
          textColor: textTertiary,
        ),
        const SizedBox(height: AppSpacing.smMd),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children:
              bookmarks.map((bm) {
                final host = Uri.tryParse(bm.url)?.host ?? '';
                return ActionChip(
                  onPressed: () => onNavigate(bm.url),
                  avatar: Icon(
                    Icons.bookmark_rounded,
                    size: 13,
                    color: AppColors.accentHighlight,
                  ),
                  label: Text(
                    bm.title.isNotEmpty ? bm.title : host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.statusBadge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: textSecondary,
                      letterSpacing: 0,
                    ),
                  ),
                  backgroundColor: cardBg,
                  side:
                      isDark
                          ? BorderSide.none
                          : BorderSide(color: outlineColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

// ── System Telemetry Bar ──

class _TelemetryBar extends StatelessWidget {
  const _TelemetryBar({
    required this.totalDownloads,
    required this.totalBytes,
    required this.elevatedBg,
    required this.textTertiary,
  });

  final int totalDownloads;
  final int totalBytes;
  final Color elevatedBg;
  final Color textTertiary;

  @override
  Widget build(BuildContext context) {
    final sizeText = totalBytes > 0 ? FileUtils.formatBytes(totalBytes) : '0 B';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      color: elevatedBg,
      child: Row(
        children: [
          // System status
          Icon(Icons.circle, size: 6, color: AppColors.successGreen),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Ready',
            style: AppTypography.mini.copyWith(
              fontWeight: FontWeight.w500,
              color: textTertiary,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          // Stats
          _TelemetryStat(
            icon: Icons.download_rounded,
            label: '$totalDownloads downloads',
            color: AppColors.accentHighlight,
            textColor: textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          _TelemetryStat(
            icon: Icons.storage_rounded,
            label: '$sizeText stored',
            color: textTertiary,
            textColor: textTertiary,
          ),
        ],
      ),
    );
  }
}

class _TelemetryStat extends StatelessWidget {
  const _TelemetryStat({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.mini.copyWith(
            color: textColor,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

// ── Section Header ──

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.textColor,
  });

  final String label;
  final IconData icon;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.sectionHeader.copyWith(color: textColor),
        ),
      ],
    );
  }
}

// ── Data Models ──

class _QuickAccessSite {
  final String url;
  final String title;
  final String host;
  final String platform;

  const _QuickAccessSite({
    required this.url,
    required this.title,
    required this.host,
    this.platform = '',
  });
}

class _PlatformSite {
  final String url;
  final String name;
  final String platform;

  const _PlatformSite(this.url, this.name, this.platform);
}

/// Thumbnail for a recent-download card.
///
/// Routes through [AppCachedImage] so VidCombo legacy imports — whose
/// `download.thumbnail` is a local file path like `.../legacy_thumbnails/12.jpg`
/// — render via [FileImage] instead of [NetworkImage], which throws
/// `Invalid argument(s): No host specified in URI` on file:// schemes and
/// caused the production crash-loop on v1.6.3.
class _RecentDownloadThumbnail extends StatelessWidget {
  const _RecentDownloadThumbnail({
    required this.thumbnail,
    required this.platform,
    required this.platformColor,
    required this.hasPlatformIcon,
  });

  final String? thumbnail;
  final String platform;
  final Color platformColor;
  final bool hasPlatformIcon;

  Widget _fallback() => Center(
    child:
        hasPlatformIcon
            ? PlatformIcon(platform: platform, size: 20)
            : Icon(
              Icons.play_circle_outline_rounded,
              size: 22,
              color: platformColor,
            ),
  );

  @override
  Widget build(BuildContext context) {
    final hasThumb = thumbnail != null && thumbnail!.isNotEmpty;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: platformColor.withValues(alpha: AppOpacity.pressed),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          hasThumb
              ? AppCachedImage(
                imageUrl: thumbnail,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorWidget: _fallback(),
              )
              : _fallback(),
    );
  }
}
