import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/core.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/auto_update_service.dart';
import '../../../../core/widgets/update_dialog.dart';

/// Banner shown when a new app version is available.
///
/// Integrates with [autoUpdateProvider] to show inline progress:
/// - Update available → "Update Now" button
/// - Downloading → progress bar with percentage
/// - Ready → "Restart to Update" button
/// - Failed → "Retry" button
/// - Mandatory → auto-triggers download, non-dismissible
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  bool _autoDownloadTriggered = false;
  String? _visibleEventVersionFired;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider);
    if (update == null || !update.updateAvailable) {
      return const SizedBox.shrink();
    }

    final updateState = ref.watch(autoUpdateProvider);
    final isMandatory = update.isMandatory;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    // `update_banner_visible` — fires once the banner widget is actually
    // mounted and rendered, paired with `update_available` from the
    // startup-side check. Funnel difference (available − visible) tells
    // us how often users have an update detected but never reach home
    // screen (legacy_thumbnails crash-loop, app stays on first-launch
    // setup, etc.). Re-fires only when the version changes so a user
    // who dismisses then re-opens doesn't double-count.
    if (_visibleEventVersionFired != update.latestVersion) {
      _visibleEventVersionFired = update.latestVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          ref.read(analyticsServiceProvider).track('update_banner_visible', {
            'version': update.latestVersion ?? '',
            'is_mandatory': update.isMandatory,
          });
        } catch (_) {
          /* non-critical */
        }
      });
    }

    // Auto-start download for mandatory updates. Telemetry-tagged
    // separately so the funnel `update_install_clicked` only counts
    // intentional user clicks, not mandatory auto-flows.
    if (isMandatory &&
        updateState.isIdle &&
        !_autoDownloadTriggered &&
        _canDownloadInApp(update)) {
      _autoDownloadTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startDownloadInternal(
          update.downloadUrl,
          update.checksum,
          update.latestVersion,
          source: 'mandatory_auto',
        );
      });
    }

    final bgColor =
        isMandatory
            ? Color.alphaBlend(
              cs.error.withValues(
                alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
              ),
              isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest,
            )
            : (isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest);
    final accentColor = isMandatory ? cs.error : AppColors.accentHighlight;
    final borderColor =
        isMandatory
            ? accentColor.withValues(alpha: AppOpacity.scrim)
            : (isDark
                ? AppColors.homeDarkBorderSubtle
                : cs.outlineVariant.withValues(alpha: 0.40));

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accentColor.withValues(alpha: isDark ? 0.055 : 0.025),
            bgColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: isDark ? 0.18 : 0.03),
              blurRadius: isDark ? 22 : 14,
              offset: Offset(0, isDark ? 10 : 3),
              spreadRadius: isDark ? -16 : -8,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final title = Text(
              _titleForState(
                updateState,
                update.latestVersion ?? '',
                isMandatory,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: updateState.isFailed ? cs.error : cs.onSurface,
              ),
            );
            final subtitle = _subtitleForState(updateState, update);
            final actions = _buildActions(
              context,
              updateState,
              update,
              accentColor,
            );

            return InkWell(
              onTap:
                  updateState.isIdle ? () => _showUpdateDialog(context) : null,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd,
                      vertical: compact ? AppSpacing.sm : AppSpacing.smMd,
                    ),
                    child:
                        compact
                            ? _CompactUpdateBannerContent(
                              icon: _buildStatusIcon(
                                context,
                                updateState,
                                isMandatory,
                                accentColor,
                              ),
                              title: title,
                              subtitle: subtitle,
                              actions: actions,
                            )
                            : Row(
                              children: [
                                _buildStatusIcon(
                                  context,
                                  updateState,
                                  isMandatory,
                                  accentColor,
                                ),
                                const SizedBox(width: AppSpacing.smMd),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      title,
                                      if (subtitle != null) ...[
                                        const SizedBox(height: AppSpacing.xxs),
                                        subtitle,
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.smMd),
                                actions,
                              ],
                            ),
                  ),
                  if (updateState.isDownloading ||
                      updateState.status == UpdateStatus.verifying)
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(AppRadius.card),
                        bottomRight: Radius.circular(AppRadius.card),
                      ),
                      child: LinearProgressIndicator(
                        value:
                            updateState.isDownloading
                                ? updateState.progress
                                : null,
                        minHeight: 3,
                        color: accentColor,
                        backgroundColor: accentColor.withValues(
                          alpha: AppOpacity.quarter,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusIcon(
    BuildContext context,
    UpdateState state,
    bool isMandatory,
    Color accentColor,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = state.isFailed ? cs.error : accentColor;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isMandatory || isDark ? 0.18 : 0.10),
        border: Border.all(
          color: tone.withValues(alpha: isMandatory || isDark ? 0.30 : 0.18),
        ),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Icon(_iconForState(state, isMandatory), size: 19, color: tone),
    );
  }

  /// Manual click on the inline banner's "Update Now" button.
  /// Telemetry is emitted from inside [AutoUpdateNotifier.downloadUpdate]
  /// AFTER the race guard, so this site no longer fires its own event.
  /// We just pass `source:` to identify the surface that initiated.
  void _startDownload(String? url, String? checksum, String? version) {
    _startDownloadInternal(url, checksum, version, source: 'banner_click');
  }

  bool _canDownloadInApp(UpdateCheckResponse update) =>
      BrandConfig.current.canAutoDownloadUpdate &&
      update.downloadUrl != null &&
      update.downloadUrl!.isNotEmpty;

  void _openWebsiteDownload() {
    launchUrl(
      Uri.parse(BrandConfig.current.websiteUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _startDownloadInternal(
    String? url,
    String? checksum,
    String? version, {
    required String source,
  }) {
    if (url == null || url.isEmpty) return;
    ref
        .read(autoUpdateProvider.notifier)
        .downloadUpdate(url, checksum ?? '', version ?? '', source: source);
  }

  /// Centralised dismiss handler so the analytics event fires from a
  /// single point regardless of which X button the user pressed (idle /
  /// downloading / readyToInstall / failed all expose dismiss).
  void _dismissBanner() {
    final current = ref.read(appUpdateProvider);
    try {
      ref.read(analyticsServiceProvider).track('update_banner_dismissed', {
        'version': current?.latestVersion ?? '',
      });
    } catch (_) {
      /* non-critical */
    }
    ref.read(appUpdateProvider.notifier).state = null;
  }

  void _showUpdateDialog(BuildContext context) {
    UpdateDialog.showFromProvider(context, ref);
  }

  IconData _iconForState(UpdateState state, bool isMandatory) {
    return switch (state.status) {
      UpdateStatus.idle =>
        isMandatory ? Icons.warning_rounded : Icons.system_update,
      UpdateStatus.downloading => Icons.downloading,
      UpdateStatus.verifying => Icons.verified_user,
      UpdateStatus.readyToInstall => Icons.check_circle,
      UpdateStatus.installing => Icons.install_desktop,
      UpdateStatus.failed => Icons.error_outline,
    };
  }

  String _titleForState(UpdateState state, String version, bool isMandatory) {
    return switch (state.status) {
      UpdateStatus.idle =>
        isMandatory
            ? AppLocalizations.homeRequiredUpdate(version)
            : AppLocalizations.homeUpdateAvailable(version),
      UpdateStatus.downloading => AppLocalizations.autoUpdateDownloading,
      UpdateStatus.verifying => AppLocalizations.autoUpdateVerifying,
      UpdateStatus.readyToInstall => AppLocalizations.autoUpdateRestartRequired,
      UpdateStatus.installing => AppLocalizations.autoUpdateInstalling,
      UpdateStatus.failed => AppLocalizations.autoUpdateFailed,
    };
  }

  Widget? _subtitleForState(UpdateState state, UpdateCheckResponse update) {
    if (state.isDownloading && state.totalBytes > 0) {
      final percent = (state.progress * 100).toInt();
      return Text(
        '$percent% — ${formatBytes(state.receivedBytes)} / ${formatBytes(state.totalBytes)}',
        style: AppTypography.metadata,
      );
    }
    if (state.isFailed && state.error != null) {
      return Text(
        state.error!,
        style: AppTypography.metadata,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (state.isIdle && update.releaseNotes != null) {
      return Text(
        update.releaseNotes!,
        style: AppTypography.metadata,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return null;
  }

  Widget _buildActions(
    BuildContext context,
    UpdateState state,
    UpdateCheckResponse update,
    Color accentColor,
  ) {
    final isMandatory = update.isMandatory;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: switch (state.status) {
        UpdateStatus.idle => [
          if (_canDownloadInApp(update))
            _UpdateBannerAction(
              onPressed:
                  () => _startDownload(
                    update.downloadUrl,
                    update.checksum,
                    update.latestVersion,
                  ),
              label: AppLocalizations.updateNow,
              accent: accentColor,
              filled: isMandatory,
            )
          else
            _UpdateBannerAction(
              onPressed: _openWebsiteDownload,
              label: AppLocalizations.updateDownloadUpdate,
              accent: accentColor,
              filled: isMandatory,
            ),
          if (!isMandatory) ...[
            const SizedBox(width: AppSpacing.xs),
            _UpdateBannerDismissButton(onPressed: _dismissBanner),
          ],
        ],
        UpdateStatus.downloading || UpdateStatus.verifying => [
          if (!isMandatory)
            _UpdateBannerDismissButton(onPressed: _dismissBanner),
        ],
        UpdateStatus.readyToInstall => [
          _UpdateBannerAction(
            onPressed: () {
              ref.read(autoUpdateProvider.notifier).installAndRestart();
            },
            label: AppLocalizations.updateRestartToUpdate,
            accent: accentColor,
            filled: true,
          ),
          if (!isMandatory) ...[
            const SizedBox(width: AppSpacing.xs),
            _UpdateBannerDismissButton(onPressed: _dismissBanner),
          ],
        ],
        UpdateStatus.installing => [],
        UpdateStatus.failed => [
          if (_canDownloadInApp(update))
            _UpdateBannerAction(
              onPressed: () {
                ref.read(autoUpdateProvider.notifier).reset();
                _autoDownloadTriggered = false;
                _startDownload(
                  update.downloadUrl,
                  update.checksum,
                  update.latestVersion,
                );
              },
              label: AppLocalizations.updateRetry,
              accent: accentColor,
              filled: true,
            )
          else
            _UpdateBannerAction(
              onPressed: _openWebsiteDownload,
              label: AppLocalizations.updateDownloadUpdate,
              accent: accentColor,
              filled: true,
            ),
          if (!isMandatory) ...[
            const SizedBox(width: AppSpacing.xs),
            _UpdateBannerDismissButton(onPressed: _dismissBanner),
          ],
        ],
      },
    );
  }
}

class _CompactUpdateBannerContent extends StatelessWidget {
  final Widget icon;
  final Widget title;
  final Widget? subtitle;
  final Widget actions;

  const _CompactUpdateBannerContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon,
            const SizedBox(width: AppSpacing.smMd),
            Expanded(child: title),
            const SizedBox(width: AppSpacing.sm),
            actions,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 28 + AppSpacing.smMd),
            child: subtitle,
          ),
        ],
      ],
    );
  }
}

class _UpdateBannerAction extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final Color accent;
  final bool filled;

  const _UpdateBannerAction({
    required this.onPressed,
    required this.label,
    required this.accent,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = filled ? cs.onPrimary : accent;
    final background =
        filled ? accent : accent.withValues(alpha: AppOpacity.hover);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.xs,
        ),
        foregroundColor: foreground,
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppTypography.metadata.copyWith(fontWeight: FontWeight.w700),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _UpdateBannerDismissButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _UpdateBannerDismissButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.close_rounded,
          size: 17,
          color: cs.onSurface.withValues(alpha: AppOpacity.secondary),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// Shows the first active backend announcement as a dismissible banner.
class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(announcementsProvider);
    if (announcements.isEmpty) return const SizedBox.shrink();

    final announcement = announcements.first;
    final cs = Theme.of(context).colorScheme;
    final isWarning =
        announcement.type == 'warning' || announcement.type == 'critical';
    final bgColor = isWarning ? cs.errorContainer : cs.secondaryContainer;
    final iconColor = isWarning ? cs.error : cs.secondary;
    final icon =
        isWarning ? Icons.campaign_rounded : Icons.info_outline_rounded;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: iconColor.withValues(alpha: AppOpacity.scrim),
          ),
        ),
        child: ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(
            announcement.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            announcement.content,
            style: AppTypography.metadata,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              final current = ref.read(announcementsProvider);
              ref.read(announcementsProvider.notifier).state =
                  current.where((a) => a.id != announcement.id).toList();
            },
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.xs,
          ),
        ),
      ),
    );
  }
}
