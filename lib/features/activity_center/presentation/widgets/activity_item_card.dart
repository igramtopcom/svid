import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/core.dart';
import '../../../../core/services/notification_center_service.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../support/presentation/screens/ticket_chat_screen.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../domain/entities/activity_item.dart';

/// Rich card rendering for a single activity item.
/// Left colored accent bar indicates status; hover reveals action buttons.
class ActivityItemCard extends ConsumerStatefulWidget {
  final ActivityItem item;

  const ActivityItemCard({super.key, required this.item});

  @override
  ConsumerState<ActivityItemCard> createState() => _ActivityItemCardState();
}

class _ActivityItemCardState extends ConsumerState<ActivityItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: switch (widget.item) {
        DownloadActivityItem(:final download) => _buildDownloadCard(
          context,
          download,
        ),
        SystemActivityItem(:final notification) => _buildSystemCard(
          context,
          notification,
        ),
      },
    );
  }

  // ── Download Item Card ──────────────────────────────────────────────────

  Widget _buildDownloadCard(BuildContext context, DownloadEntity download) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = _statusAccentColor(download.status, isDark);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left accent bar (4px)
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                  vertical: AppSpacing.smMd,
                ),
                child: Row(
                  children: [
                    // Platform badge
                    _PlatformBadge(platform: download.platform),
                    const SizedBox(width: AppSpacing.smMd),

                    // Title + subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            download.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          _buildSubtitle(theme, download),
                        ],
                      ),
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Status badge
                    _StatusBadge(status: download.status),

                    const SizedBox(width: AppSpacing.smMd),

                    // Relative time
                    Text(
                      Formatters.formatRelativeTime(download.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        fontSize: 11,
                      ),
                    ),

                    // Action buttons on hover — always mounted; opacity-toggled.
                    // Conditional mounting on _isHovered triggers mouse_tracker.dart:203
                    // assertion when ListView rebuilds during pointer dispatch.
                    const SizedBox(width: AppSpacing.sm),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isHovered,
                        child: _buildDownloadActions(context, download),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitle(ThemeData theme, DownloadEntity download) {
    final parts = <String>[];
    parts.add(download.filename);
    if (download.qualityLabel != null &&
        download.qualityLabel!.isNotEmpty &&
        download.qualityLabel != 'unknown') {
      parts.add(download.qualityLabel!);
    }
    if (download.totalBytes > 0) {
      parts.add(FileUtils.formatBytes(download.totalBytes));
    }

    return Text(
      parts.join(' \u00B7 '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
        fontSize: 11,
      ),
    );
  }

  Widget _buildDownloadActions(BuildContext context, DownloadEntity download) {
    final actions = <Widget>[];

    if (download.isCompleted) {
      actions.add(
        _ActionButton(
          icon: Icons.play_circle_outline,
          tooltip: AppLocalizations.activityCenterOpenFile,
          onTap: () => _openFile(download),
        ),
      );
      actions.add(
        _ActionButton(
          icon: Icons.folder_open_outlined,
          tooltip: AppLocalizations.activityCenterShowInFolder,
          onTap: () => _showInFolder(download),
        ),
      );
      actions.add(
        _ActionButton(
          icon: Icons.copy_rounded,
          tooltip: AppLocalizations.activityCenterCopyUrl,
          onTap: () => _copyUrl(context, download.url),
        ),
      );
    } else if (download.isFailed) {
      actions.add(
        _ActionButton(
          icon: Icons.refresh_rounded,
          tooltip: AppLocalizations.activityCenterRetry,
          onTap: () => _retryDownload(download.id),
        ),
      );
      actions.add(
        _ActionButton(
          icon: Icons.copy_rounded,
          tooltip: AppLocalizations.activityCenterCopyUrl,
          onTap: () => _copyUrl(context, download.url),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  void _openFile(DownloadEntity download) {
    final filePath = p.join(download.savePath, download.filename);
    if (Platform.isMacOS) {
      ProcessHelper.openFileWithSystem(filePath).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.openFileWithSystem(filePath).ignore();
    } else {
      ProcessHelper.openFileWithSystem(filePath).ignore();
    }
  }

  void _showInFolder(DownloadEntity download) {
    final filePath = p.join(download.savePath, download.filename);
    if (Platform.isMacOS) {
      ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      ).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      ).ignore();
    } else {
      ProcessHelper.openDirectoryInFileManager(download.savePath).ignore();
    }
  }

  void _copyUrl(BuildContext context, String url) {
    ClipboardService.setText(url);
    AppSnackBar.success(
      context,
      message: AppLocalizations.activityCenterUrlCopied,
    );
  }

  void _retryDownload(int id) {
    ref.read(downloadsNotifierProvider.notifier).retryDownload(id);
  }

  // ── System Notification Card ────────────────────────────────────────────

  Widget _buildSystemCard(BuildContext context, AppNotification notification) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = _notificationAccentColor(notification.type, isDark);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    // Tappable for actionable notifications (e.g., ticket replies, new videos)
    final isTappable =
        (notification.type == AppNotificationType.ticketReply &&
            notification.metadata?['ticketId'] != null) ||
        (notification.type == AppNotificationType.youtubeNewVideo &&
            notification.metadata?['channelUrl'] != null);

    Widget card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left accent bar (4px)
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                  vertical: AppSpacing.smMd,
                ),
                child: Row(
                  children: [
                    // Type icon
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: AppOpacity.subtle),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Icon(
                        _notificationIcon(notification.type),
                        size: 14,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smMd),

                    // Title + body
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                          if (notification.body.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              notification.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: AppOpacity.overlay,
                                ),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: AppSpacing.smMd),

                    // Relative time
                    Text(
                      Formatters.formatRelativeTime(notification.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        fontSize: 11,
                      ),
                    ),

                    // Unread indicator
                    if (!notification.isRead) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentHighlight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isTappable) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _handleNotificationTap(context, notification),
          child: card,
        ),
      );
    }

    return card;
  }

  void _handleNotificationTap(
    BuildContext context,
    AppNotification notification,
  ) {
    if (notification.type == AppNotificationType.ticketReply) {
      final ticketId = notification.metadata?['ticketId'];
      if (ticketId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketChatScreen(ticketId: ticketId),
          ),
        );
      }
    } else if (notification.type == AppNotificationType.youtubeNewVideo) {
      final channelUrl = notification.metadata?['channelUrl'];
      if (channelUrl != null) {
        ref
            .read(navigationProvider.notifier)
            .navigateToTab(NavigationConstants.youtubeIndex);
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Color _statusAccentColor(DownloadStatus status, bool isDark) {
    return switch (status) {
      DownloadStatus.completed =>
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted,
      DownloadStatus.failed || DownloadStatus.cancelled =>
        isDark ? AppColors.errorRed : AppColors.lightStatusFailed,
      DownloadStatus.downloading ||
      DownloadStatus.pending ||
      DownloadStatus.queued ||
      DownloadStatus.postProcessing ||
      // RC10.3: new sub-states share the same accent as generic
      // post-processing (brand color — active/in-flight).
      DownloadStatus.merging ||
      DownloadStatus.remuxing ||
      DownloadStatus.converting => AppColors.brand,
      DownloadStatus.paused || DownloadStatus.waitingForNetwork =>
        isDark ? AppColors.warningAmber : AppColors.warningAmberLight,
    };
  }

  Color _notificationAccentColor(AppNotificationType type, bool isDark) {
    return switch (type) {
      AppNotificationType.downloadComplete ||
      AppNotificationType.ytdlpUpdateCompleted ||
      AppNotificationType.ffmpegUpdateCompleted ||
      AppNotificationType.licenseActivated =>
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted,
      AppNotificationType.downloadFailed ||
      AppNotificationType.ytdlpUpdateFailed ||
      AppNotificationType.ffmpegUpdateFailed ||
      AppNotificationType.licenseActivationFailed ||
      AppNotificationType.licenseDeactivated =>
        isDark ? AppColors.errorRed : AppColors.lightStatusFailed,
      AppNotificationType.qualityFallbackApplied ||
      AppNotificationType.subscriptionExpiryWarning =>
        isDark ? AppColors.warningAmber : AppColors.warningAmberLight,
      AppNotificationType.ticketReply =>
        isDark ? AppColors.brand : AppColors.accentHighlight,
      AppNotificationType.youtubeNewVideo =>
        isDark ? AppColors.brand : AppColors.accentHighlight,
    };
  }

  IconData _notificationIcon(AppNotificationType type) {
    return switch (type) {
      AppNotificationType.downloadComplete => Icons.download_done_rounded,
      AppNotificationType.downloadFailed => Icons.error_outline_rounded,
      AppNotificationType.ytdlpUpdateCompleted ||
      AppNotificationType
          .ffmpegUpdateCompleted => Icons.system_update_alt_rounded,
      AppNotificationType.ytdlpUpdateFailed ||
      AppNotificationType.ffmpegUpdateFailed => Icons.update_disabled_rounded,
      AppNotificationType.qualityFallbackApplied => Icons.warning_amber_rounded,
      AppNotificationType.licenseActivated => Icons.verified_rounded,
      AppNotificationType.licenseActivationFailed => Icons.block_rounded,
      AppNotificationType.licenseDeactivated =>
        Icons.workspace_premium_outlined,
      AppNotificationType.subscriptionExpiryWarning => Icons.schedule_rounded,
      AppNotificationType.ticketReply => Icons.mail_outline_rounded,
      AppNotificationType.youtubeNewVideo => Icons.subscriptions_rounded,
    };
  }
}

/// Platform badge using real SVG brand logos (consistent with Home screen).
/// Falls back to colored initial letter for platforms without SVG assets.
class _PlatformBadge extends StatelessWidget {
  final String platform;

  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    final hasSvg = PlatformStyleHelper.hasSvgIcon(platform);
    final color = PlatformStyleHelper.getColorForPlatform(platform);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Center(
        child:
            hasSvg
                ? PlatformIcon(platform: platform, size: 14, color: color)
                : Text(
                  platform.isNotEmpty && platform != 'unknown'
                      ? platform[0].toUpperCase()
                      : '?',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
      ),
    );
  }
}

/// Colored pill badge for download status.
class _StatusBadge extends StatelessWidget {
  final DownloadStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _badgeColor(status, isDark);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.pressed),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        _statusLabel(status),
        style: AppTypography.compact.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _statusLabel(DownloadStatus status) {
    return switch (status) {
      DownloadStatus.pending => AppLocalizations.activityCenterStatusPending,
      DownloadStatus.queued => AppLocalizations.activityCenterStatusQueued,
      DownloadStatus.downloading =>
        AppLocalizations.activityCenterStatusDownloading,
      DownloadStatus.postProcessing ||
      // RC10.3: new sub-states share the existing "Converting" label
      // in the compact activity-card UI (the activity-card has
      // limited space; the full distinction is rendered in the main
      // download list). For RC10.3 v1 keep activity card behavior
      // identical to pre-RC10.3.
      DownloadStatus.merging ||
      DownloadStatus.remuxing ||
      DownloadStatus
          .converting => AppLocalizations.activityCenterStatusConverting,
      DownloadStatus.paused => AppLocalizations.activityCenterStatusPaused,
      DownloadStatus.completed =>
        AppLocalizations.activityCenterStatusCompleted,
      DownloadStatus.failed => AppLocalizations.activityCenterStatusFailed,
      DownloadStatus.cancelled =>
        AppLocalizations.activityCenterStatusCancelled,
      DownloadStatus.waitingForNetwork =>
        AppLocalizations.activityCenterStatusWaitingForNetwork,
    };
  }

  Color _badgeColor(DownloadStatus status, bool isDark) {
    return switch (status) {
      DownloadStatus.completed =>
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted,
      DownloadStatus.failed || DownloadStatus.cancelled =>
        isDark ? AppColors.errorRed : AppColors.lightStatusFailed,
      DownloadStatus.downloading =>
        isDark ? AppColors.infoBlue : AppColors.infoBlueLight,
      DownloadStatus.pending || DownloadStatus.queued =>
        isDark ? AppColors.statusQueued : AppColors.statusQueuedLight,
      DownloadStatus.postProcessing ||
      // RC10.3: new sub-states share post-processing badge color.
      DownloadStatus.merging ||
      DownloadStatus.remuxing ||
      DownloadStatus.converting =>
        isDark
            ? AppColors.statusPostProcessing
            : AppColors.statusPostProcessingLight,
      DownloadStatus.paused || DownloadStatus.waitingForNetwork =>
        isDark ? AppColors.warningAmber : AppColors.warningAmberLight,
    };
  }
}

/// Small icon button for hover actions (open file, show in folder, etc.).
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.overlay,
            ),
          ),
        ),
      ),
    );
  }
}
