import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../data/datasources/extraction_cache.dart';
import '../../domain/entities/video_info.dart';
import '../providers/extraction_cache_provider.dart';

/// The Evidence Room — Extraction history drawer (Nocturne Cinematic v2)
/// Design ref: Stitch screen 9e803ae8c4b44982942aed880188893e
class ExtractionHistoryDrawer extends ConsumerWidget {
  final void Function(VideoInfo videoInfo)? onItemTap;
  final VoidCallback? onClose;

  const ExtractionHistoryDrawer({super.key, this.onItemTap, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(extractionHistoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final borderColor = isDark
        ? AppColors.homeDarkBorderStrong
        : cs.outlineVariant.withValues(alpha: AppOpacity.strong);
    const radius = Radius.circular(18);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.base(context),
        borderRadius: const BorderRadius.only(
          topLeft: radius,
          bottomLeft: radius,
        ),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
            blurRadius: 28,
            offset: const Offset(-10, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context, ref, history.length, isDark),
          Expanded(
            child:
                history.isEmpty
                    ? _buildEmptyState(context, isDark)
                    : _buildHistoryList(context, ref, history, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    int count,
    bool isDark,
  ) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.mdLg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderSubtle
                    : cs.outlineVariant.withValues(alpha: AppOpacity.strong),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: isDark ? 0.16 : 0.08),
                    AppColors.surface2(context),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.extractionHistoryTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (count > 0)
                _HeaderButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: AppLocalizations.extractionHistoryClearAllTooltip,
                  onPressed: () => _showClearDialog(context, ref, isDark),
                  isDark: isDark,
                ),
              _HeaderButton(
                icon: Icons.close,
                tooltip: AppLocalizations.extractionHistoryCloseTooltip,
                onPressed: onClose,
                isDark: isDark,
              ),
            ],
          ),
          // Cache-retention pill — only when there's something cached. The
          // long "recently extracted URLs…" description is dropped here (it
          // duplicates the empty-state copy and only truncated awkwardly).
          if (count > 0) ...[
            const SizedBox(height: AppSpacing.smMd),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2(context),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                    color: AppColors.border(
                      context,
                    ).withValues(alpha: isDark ? AppOpacity.strong : 1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cached_rounded,
                      size: 12,
                      color: AppColors.metaText(context),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      AppLocalizations.extractionHistoryCacheInfo(count),
                      style: AppTypography.compact.copyWith(
                        color: AppColors.metaText(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(alpha: isDark ? 0.16 : 0.08),
                  AppColors.surface1(context),
                ),
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.34 : 0.22),
                ),
              ),
              child: _BreathingIcon(isDark: isDark),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppLocalizations.extractionHistoryEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.extractionHistoryEmptySubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: AppColors.metaText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(
    BuildContext context,
    WidgetRef ref,
    List<CacheEntry> history,
    bool isDark,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final entry = history[index];
        return _EvidenceItem(
          entry: entry,
          isDark: isDark,
          onTap: () => onItemTap?.call(entry.videoInfo),
          onDelete: () => _deleteItem(ref, entry.videoInfo.url),
        );
      },
    );
  }

  void _deleteItem(WidgetRef ref, String url) {
    ref.read(extractionHistoryProvider.notifier).removeItem(url);
  }

  void _showClearDialog(BuildContext context, WidgetRef ref, bool isDark) {
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface2 : cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            title: Text(AppLocalizations.extractionHistoryClearTitle),
            content: Text(AppLocalizations.extractionHistoryClearMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref.read(extractionHistoryProvider.notifier).clearAll();
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                child: Text(AppLocalizations.extractionHistoryClearConfirm),
              ),
            ],
          ),
    );
  }
}

/// Breathing radar icon — slow pulse for empty state atmosphere
class _BreathingIcon extends StatefulWidget {
  final bool isDark;
  const _BreathingIcon({required this.isDark});

  @override
  State<_BreathingIcon> createState() => _BreathingIconState();
}

class _BreathingIconState extends State<_BreathingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.5 + (_controller.value * 0.3); // 0.5 → 0.8
        return Icon(
          Icons.manage_search_rounded,
          size: 28,
          color:
              widget.isDark
                  ? BrandConfig.current.colors.gradientTail.withValues(
                    alpha: pulse,
                  )
                  : AppColors.accentHighlight.withValues(alpha: pulse),
        );
      },
    );
  }
}

/// Thin header action button
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDark;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;

    return Tooltip(
      message: tooltip,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        color: AppColors.metaText(context),
        hoverColor: accent.withValues(alpha: isDark ? 0.16 : 0.08),
        splashColor: accent.withValues(alpha: AppOpacity.pressed),
        splashRadius: 17,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }
}

/// History item — Surveillance log layout from Stitch v2:
/// Row 1: PLATFORM (left) + time (right)
/// Row 2: Title + quality badge (inline)
class _EvidenceItem extends StatefulWidget {
  final CacheEntry entry;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _EvidenceItem({
    required this.entry,
    required this.isDark,
    this.onTap,
    this.onDelete,
  });

  @override
  State<_EvidenceItem> createState() => _EvidenceItemState();
}

class _EvidenceItemState extends State<_EvidenceItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final videoInfo = widget.entry.videoInfo;
    final timeAgo = _formatTimeAgo(widget.entry.extractedAt);
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;
    final surface = widget.isDark ? AppColors.homeDarkCardBg : cs.surface;
    final hoverSurface =
        widget.isDark ? AppColors.homeDarkCardHover : AppColors.lightSurface2;
    final borderColor =
        widget.isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outlineVariant.withValues(alpha: AppOpacity.strong);

    return Dismissible(
      key: Key(videoInfo.url),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete?.call(),
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.errorRed.withValues(alpha: AppOpacity.nearOpaque),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: AppSpacing.mdLg),
            child: Icon(Icons.delete_outline, color: Colors.white, size: 18),
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTransitions.fast,
            curve: AppTransitions.curveSymmetric,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _isHovered ? hoverSurface : surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    _isHovered
                        ? accent.withValues(alpha: widget.isDark ? 0.34 : 0.24)
                        : borderColor,
              ),
              boxShadow:
                  _isHovered
                      ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: widget.isDark ? 0.18 : 0.05,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppTransitions.fast,
                  width: 3,
                  height: 52,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color:
                        _isHovered
                            ? accent
                            : accent.withValues(alpha: AppOpacity.quarter),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                _NoirThumbnail(
                  imageUrl: videoInfo.thumbnail ?? '',
                  isDark: widget.isDark,
                ),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              videoInfo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          _MetaPill(
                            icon: Icons.public_rounded,
                            label: videoInfo.platform ?? 'Web',
                            isDark: widget.isDark,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _MetaPill(
                            icon: Icons.schedule_rounded,
                            label: timeAgo,
                            isDark: widget.isDark,
                          ),
                          if (videoInfo.availableQualities.isNotEmpty) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: _MetaPill(
                                icon: Icons.high_quality_rounded,
                                label:
                                    AppLocalizations.extractionHistoryQualities(
                                      videoInfo.availableQualities.length,
                                    ),
                                isDark: widget.isDark,
                                accent: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);

    if (diff.inMinutes < 1) {
      return AppLocalizations.extractionHistoryTimeJustNow;
    } else if (diff.inMinutes < 60) {
      return AppLocalizations.extractionHistoryTimeMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return AppLocalizations.extractionHistoryTimeHoursAgo(diff.inHours);
    } else {
      return AppLocalizations.extractionHistoryTimeDaysAgo(diff.inDays);
    }
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool accent;

  const _MetaPill({
    required this.icon,
    required this.label,
    required this.isDark,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        accent ? AppColors.accentHighlight : AppColors.metaText(context);
    final bg = Color.alphaBlend(
      color.withValues(alpha: isDark ? 0.14 : 0.07),
      isDark ? AppColors.homeDarkCardBg : AppColors.surface2(context),
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.24 : 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mini.copyWith(
                color: color,
                fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact thumbnail aligned with Home V2 download rows.
class _NoirThumbnail extends StatelessWidget {
  final String imageUrl;
  final bool isDark;

  const _NoirThumbnail({required this.imageUrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        width: 76,
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppCachedImage(
              imageUrl: imageUrl,
              width: 76,
              height: 48,
              borderRadius: BorderRadius.circular(AppRadius.card),
              errorWidget: _buildPlaceholder(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.lightBorder.withValues(
                            alpha: AppOpacity.strong,
                          ),
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: isDark ? AppColors.darkBg : AppColors.lightSurface2,
      child: Center(
        child: Icon(
          Icons.videocam_outlined,
          size: 16,
          color:
              isDark
                  ? AppColors.brand.withValues(alpha: AppOpacity.quarter)
                  : AppColors.lightBorder,
        ),
      ),
    );
  }
}
