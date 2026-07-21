import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/playlist_library_provider.dart';

class PlaylistLibraryView extends StatelessWidget {
  final List<PlaylistLibraryItem> playlists;
  final void Function(PlaylistLibraryItem playlist) onOpen;
  final void Function(PlaylistLibraryItem playlist) onPlay;
  final VoidCallback onCreate;

  const PlaylistLibraryView({
    super.key,
    required this.playlists,
    required this.onOpen,
    required this.onPlay,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            itemCount: playlists.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) {
              if (index == 0) {
                return PlaylistCreateCard(onCreate: onCreate);
              }
              final playlist = playlists[index - 1];
              return PlaylistLibraryCard(
                playlist: playlist,
                onOpen: () => onOpen(playlist),
                onPlay: () => onPlay(playlist),
              );
            },
          );
        }

        final columns = constraints.maxWidth < 1180 ? 2 : 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          itemCount: playlists.length + 1,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            mainAxisExtent: 150,
          ),
          itemBuilder: (_, index) {
            if (index == 0) {
              return PlaylistCreateCard(onCreate: onCreate);
            }
            final playlist = playlists[index - 1];
            return PlaylistLibraryCard(
              playlist: playlist,
              onOpen: () => onOpen(playlist),
              onPlay: () => onPlay(playlist),
            );
          },
        );
      },
    );
  }
}

class PlaylistCreateCard extends StatelessWidget {
  final VoidCallback onCreate;

  const PlaylistCreateCard({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;
    final surfaceColor =
        isDark
            ? AppColors.homeDarkCardBg
            : accent.withValues(alpha: AppOpacity.subtle);
    final borderColor = accent.withValues(alpha: isDark ? 0.42 : 0.24);
    final titleColor = isDark ? AppColors.darkLightText : cs.onSurface;
    final metaColor = isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCreate,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.smMd,
              AppSpacing.sm,
              AppSpacing.smMd,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.30 : 0.20),
                    ),
                  ),
                  child: Icon(Icons.add_rounded, size: 32, color: accent),
                ),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.playlistManageCreateTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        AppLocalizations.playlistManageCreateCardSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.compact.copyWith(color: metaColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.30 : 0.20),
                    ),
                  ),
                  child: Icon(
                    Icons.playlist_add_rounded,
                    size: 22,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlaylistLibraryCard extends StatelessWidget {
  final PlaylistLibraryItem playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  const PlaylistLibraryCard({
    super.key,
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final stats = _PlaylistStats.from(playlist);
    final accent =
        playlist.kind == PlaylistLibraryKind.user
            ? AppColors.accentHighlight
            : AppColors.infoBlue;
    final kindIcon =
        playlist.kind == PlaylistLibraryKind.user
            ? Icons.bookmark_rounded
            : Icons.smart_display_rounded;
    final kindLabel =
        playlist.kind == PlaylistLibraryKind.user
            ? AppLocalizations.rightPanelTabsPlaylist
            : AppLocalizations.youtubePlaylistTitle;
    final titleColor = isDark ? AppColors.darkLightText : cs.onSurface;
    final metaColor = isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;
    final surfaceColor =
        isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant.withValues(alpha: 0.72);
    final railColor = accent.withValues(alpha: isDark ? 0.82 : 0.74);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor, width: 1),
            boxShadow:
                isDark
                    ? null
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        spreadRadius: -14,
                      ),
                    ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: railColor,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(AppRadius.card),
                    ),
                  ),
                  child: const SizedBox(width: 3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.smMd,
                  AppSpacing.sm,
                  AppSpacing.smMd,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    _PlaylistCover(playlist: playlist, accent: accent),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              _PlaylistKindBadge(
                                icon: kindIcon,
                                label: kindLabel,
                                color: accent,
                              ),
                              const Spacer(),
                              if (stats.updatedLabel.isNotEmpty)
                                Text(
                                  stats.updatedLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.mini.copyWith(
                                    color: metaColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            playlist.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _PlaylistPill(
                                icon: Icons.video_library_rounded,
                                label:
                                    AppLocalizations.rightPanelPlaylistItemCount(
                                      playlist.count,
                                    ),
                                color: accent,
                                emphasized: playlist.count > 0,
                              ),
                              if (stats.completed > 0)
                                _PlaylistPill(
                                  icon: Icons.check_circle_rounded,
                                  label:
                                      '${stats.completed} ${DownloadStatus.completed.displayLabel}',
                                  color: AppColors.successGreen,
                                ),
                              if (stats.active > 0)
                                _PlaylistPill(
                                  icon: Icons.downloading_rounded,
                                  label:
                                      '${stats.active} ${AppLocalizations.statusActive}',
                                  color: AppColors.statusDownloading,
                                ),
                              if (stats.failed > 0)
                                _PlaylistPill(
                                  icon: Icons.error_rounded,
                                  label:
                                      '${stats.failed} ${DownloadStatus.failed.displayLabel}',
                                  color: AppColors.errorRed,
                                ),
                            ],
                          ),
                          if (playlist.count == 0) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              AppLocalizations.playlistAddDialogEmpty,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.compact.copyWith(
                                color: metaColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _PlaylistPlayButton(
                      accent: accent,
                      enabled: playlist.count > 0,
                      onPressed: onPlay,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final PlaylistLibraryItem playlist;
  final Color accent;

  const _PlaylistCover({required this.playlist, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbnails =
        playlist.downloads
            .map((d) => d.thumbnail)
            .whereType<String>()
            .where((url) => url.trim().isNotEmpty)
            .take(4)
            .toList();

    return SizedBox(
      width: 120,
      height: 84,
      child: Stack(
        children: [
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              width: 94,
              height: 58,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: 104,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child:
                  thumbnails.isEmpty
                      ? ColoredBox(
                        color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                        child: Icon(
                          playlist.kind == PlaylistLibraryKind.user
                              ? Icons.bookmark_rounded
                              : Icons.playlist_play_rounded,
                          color: accent,
                          size: 34,
                        ),
                      )
                      : thumbnails.length == 1
                      ? AppCachedImage(
                        imageUrl: thumbnails.first,
                        width: 104,
                        height: 68,
                        fit: BoxFit.cover,
                        errorWidget: ColoredBox(
                          color: accent.withValues(alpha: 0.14),
                          child: Icon(
                            Icons.playlist_play_rounded,
                            color: accent,
                          ),
                        ),
                      )
                      : GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        crossAxisCount: 2,
                        children:
                            thumbnails
                                .map(
                                  (url) => AppCachedImage(
                                    imageUrl: url,
                                    width: 52,
                                    height: 34,
                                    fit: BoxFit.cover,
                                    errorWidget: ColoredBox(
                                      color: accent.withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.playlist_play_rounded,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 6,
            child: Container(
              height: 22,
              constraints: const BoxConstraints(minWidth: 28),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                '${playlist.count}',
                style: AppTypography.compact.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool emphasized;

  const _PlaylistPill({
    required this.icon,
    required this.label,
    required this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: emphasized ? (isDark ? 0.22 : 0.13) : (isDark ? 0.16 : 0.08),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.22 : 0.16),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mini.copyWith(
              color: color,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistKindBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _PlaylistKindBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 24,
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.26 : 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mini.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPlayButton extends StatelessWidget {
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  const _PlaylistPlayButton({
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledColor = AppColors.metaText(context);
    return Tooltip(
      message: AppLocalizations.playerPlay,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: AppTransitions.controls,
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                enabled
                    ? accent.withValues(alpha: isDark ? 0.20 : 0.10)
                    : disabledColor.withValues(alpha: isDark ? 0.10 : 0.06),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  enabled
                      ? accent.withValues(alpha: isDark ? 0.34 : 0.22)
                      : disabledColor.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            size: 22,
            color: enabled ? accent : disabledColor.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }
}

class _PlaylistStats {
  final int completed;
  final int active;
  final int failed;
  final String updatedLabel;

  const _PlaylistStats({
    required this.completed,
    required this.active,
    required this.failed,
    required this.updatedLabel,
  });

  factory _PlaylistStats.from(PlaylistLibraryItem playlist) {
    var completed = 0;
    var active = 0;
    var failed = 0;
    for (final download in playlist.downloads) {
      if (download.isCompleted) {
        completed++;
      } else if (download.isFailed) {
        failed++;
      } else if (download.status.isActive || download.isWaitingForNetwork) {
        active++;
      }
    }

    return _PlaylistStats(
      completed: completed,
      active: active,
      failed: failed,
      updatedLabel:
          playlist.count == 0 ? '' : Formatters.formatDate(playlist.updatedAt),
    );
  }
}
