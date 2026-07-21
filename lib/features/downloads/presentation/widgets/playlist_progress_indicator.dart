import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/downloads_notifier.dart';
import '../../domain/services/playlist_download_service.dart';

/// Compact banner shown at the top of the downloads list while a large
/// playlist / channel download is in progress.
///
/// Reads [PlaylistSession] from [downloadsNotifierProvider] and hides itself
/// when [PlaylistSession.isActive] becomes false.
class PlaylistProgressIndicator extends ConsumerWidget {
  const PlaylistProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(
      downloadsNotifierProvider.select((s) => s.activePlaylist),
    );

    if (session == null || !session.isActive) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fraction = session.progress;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: isDark ? Border.all(color: AppColors.darkElevated) : null,
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.playlist_play_rounded,
                size: 18,
                color: AppColors.brand,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _phaseLabel(session),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (session.failed > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    '${session.failed} failed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warningAmber,
                    ),
                  ),
                ),
              if (session.skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    AppLocalizations.playlistSkippedLabel(session.skipped),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.overlay,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor:
                  isDark ? AppColors.darkElevated : AppColors.lightSurface3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(PlaylistSession session) {
    final count = AppLocalizations.playlistProgressLabel(
      session.completed,
      session.total,
    );
    return switch (session.phase) {
      PlaylistSessionPhase.extracting => 'Preparing selected videos...',
      PlaylistSessionPhase.selecting => 'Waiting for quality choices... $count',
      PlaylistSessionPhase.queueing => count,
      PlaylistSessionPhase.finished => count,
    };
  }
}
