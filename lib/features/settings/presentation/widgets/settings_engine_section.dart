import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/binaries/binaries.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../domain/enums/download_engine.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsEngineSection extends ConsumerStatefulWidget {
  const SettingsEngineSection({super.key});

  @override
  ConsumerState<SettingsEngineSection> createState() =>
      _SettingsEngineSectionState();
}

class _SettingsEngineSectionState extends ConsumerState<SettingsEngineSection> {
  static const _binaryUpdateSnackId = 'settings_binary_update';

  bool _isUpdatingBinaries = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ytdlpVersionAsync = ref.watch(ytdlpVersionProvider);
    final ytdlpAvailableAsync = ref.watch(ytdlpAvailableProvider);
    final ffmpegVersionAsync = ref.watch(
      binaryVersionProvider(BinaryType.ffmpeg),
    );
    final ffmpegAvailableAsync = ref.watch(
      binaryAvailableProvider(BinaryType.ffmpeg),
    );
    final galleryVersionAsync = ref.watch(
      binaryVersionProvider(BinaryType.galleryDl),
    );
    final galleryAvailableAsync = ref.watch(
      binaryAvailableProvider(BinaryType.galleryDl),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionEngineComponents,
        ),
        const Gap.md(),

        // Card: Engine
        settingsCard(
          context,
          title: 'ENGINE',
          children: [
            ListTile(
              leading: const Icon(Icons.engineering, size: 20),
              title: Text(AppLocalizations.settingsDownloadEngine),
              subtitle: Text(settings.downloadEngine.description),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _showDownloadEngineDialog(
                    context,
                    ref,
                    settings.downloadEngine,
                  ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              secondary: const Icon(Icons.update, size: 20),
              title: Text(AppLocalizations.settingsBinariesAutoUpdateYtdlp),
              subtitle: Text(
                AppLocalizations.settingsBinariesAutoUpdateYtdlpDesc,
              ),
              value: settings.autoUpdateYtdlp,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleAutoUpdateYtdlp(),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Binary Components — diagnostic monitor aesthetic
        settingsCard(
          context,
          title: AppLocalizations.settingsBinaryComponentsTitle.toUpperCase(),
          children: [
            // yt-dlp
            _BinaryStatusTile(
              icon: Icons.download,
              label: 'YT-DLP',
              description: AppLocalizations.settingsBinaryComponentsYtdlp,
              versionAsync: ytdlpVersionAsync,
              availableAsync: ytdlpAvailableAsync,
              onRefresh: () => _checkYtdlpUpdates(context, ref),
              refreshTooltip:
                  AppLocalizations.settingsBinaryComponentsUpdateYtdlp,
              isRefreshEnabled: !_isUpdatingBinaries,
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // FFmpeg
            _BinaryStatusTile(
              icon: Icons.video_settings,
              label: 'FFMPEG',
              description: AppLocalizations.settingsBinaryComponentsFFmpeg,
              versionAsync: ffmpegVersionAsync,
              availableAsync: ffmpegAvailableAsync,
              onRefresh: () => _updateFFmpeg(context, ref),
              refreshTooltip:
                  AppLocalizations.settingsBinaryComponentsUpdateFFmpeg,
              isRefreshEnabled: !_isUpdatingBinaries,
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Update all
            if (BinaryManager.isGalleryDlSupported) ...[
              _BinaryStatusTile(
                icon: Icons.image_search,
                label: 'GALLERY-DL',
                description: AppLocalizations.settingsBinaryComponentsGalleryDl,
                versionAsync: galleryVersionAsync,
                availableAsync: galleryAvailableAsync,
                onRefresh:
                    () => _updateAuxBinary(context, ref, BinaryType.galleryDl),
                refreshTooltip:
                    AppLocalizations.settingsBinaryComponentsRepairGalleryDl,
                isRefreshEnabled: !_isUpdatingBinaries,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],

            // Repair/update all
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _isUpdatingBinaries
                          ? null
                          : () => _updateAllBinaries(context, ref),
                  icon:
                      _isUpdatingBinaries
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.system_update),
                  label: Text(AppLocalizations.settingsBinariesUpdateAll),
                ),
              ),
            ),

            // View update history
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showUpdateHistory(context, ref),
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(AppLocalizations.binaryUpdateHistoryTitle),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  void _showDownloadEngineDialog(
    BuildContext context,
    WidgetRef ref,
    DownloadEngine currentEngine,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            title: Text(AppLocalizations.settingsBinariesSelectEngine),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    DownloadEngine.values.map((engine) {
                      return RadioListTile<DownloadEngine>(
                        title: Text(engine.displayName),
                        subtitle: Text(engine.description),
                        value: engine,
                        groupValue: currentEngine,
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateDownloadEngine(value);
                            Navigator.pop(context);
                          }
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
            ],
          ),
    );
  }

  // ===========================================================================
  // BINARY UPDATE METHODS
  // ===========================================================================

  Future<void> _checkYtdlpUpdates(BuildContext context, WidgetRef ref) async {
    if (!_beginBinaryUpdate(context)) return;
    _showBinaryUpdateProgress(
      context,
      message: AppLocalizations.ytdlpUpdateCheckingForUpdate,
    );

    try {
      final binaryManager = ref.read(binaryManagerProvider);
      final versionService = ref.read(ytdlpVersionServiceProvider);
      final installedVersion = await binaryManager.getVersion(BinaryType.ytDlp);
      final latestVersion = await versionService.fetchLatestVersion();

      if (!context.mounted) return;

      if (latestVersion == null) {
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: AppLocalizations.binaryUpdateHintNetworkTimeout,
          success: false,
        );
        return;
      }

      final needsUpdate =
          installedVersion == null ||
          versionService.isNewerVersion(latestVersion, installedVersion);

      if (!needsUpdate) {
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: AppLocalizations.ytdlpUpdateNoUpdateNeeded,
        );
        return;
      }

      AppSnackBar.dismiss(context);
      final confirmed = await AppConfirmDialog.show(
        context,
        title: AppLocalizations.settingsUpdateYtdlpDialogTitle,
        message: AppLocalizations.settingsUpdateYtdlpDialogMessage,
        confirmLabel: AppLocalizations.settingsUpdate,
      );
      if (!context.mounted || !confirmed) return;

      _showBinaryUpdateProgress(
        context,
        message: AppLocalizations.settingsBinaryComponentsUpdatingYtdlp,
      );
      await _runYtdlpUpdate(context, ref);
    } catch (e) {
      if (!context.mounted) return;
      final errorCode = BinaryUpdateErrorCodeX.classify(e.toString());
      AppSnackBar.completeProgress(
        context,
        id: _binaryUpdateSnackId,
        message: errorCode.hint,
        success: false,
      );
    } finally {
      _endBinaryUpdate();
    }
  }

  Future<void> _runYtdlpUpdate(BuildContext context, WidgetRef ref) async {
    final binaryManager = ref.read(binaryManagerProvider);
    final historyService = ref.read(binaryUpdateHistoryServiceProvider);
    final oldVersion = await binaryManager.getVersion(BinaryType.ytDlp);

    bool success = false;
    await for (final progress in binaryManager.updateBinarySafely(
      BinaryType.ytDlp,
    )) {
      if (context.mounted) {
        _showBinaryProgress(context, BinaryType.ytDlp, progress);
      }
      if (progress.status == BinaryDownloadStatus.completed) {
        success = true;
      } else if (progress.status == BinaryDownloadStatus.error) {
        if (!context.mounted) return;
        final errorCode = BinaryUpdateErrorCodeX.classify(progress.error ?? '');
        historyService.addFailure(
          binaryType: BinaryType.ytDlp,
          errorCode: errorCode,
          oldVersion: oldVersion,
          errorDetail: progress.error,
        );
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: errorCode.hint,
          success: false,
        );
        return;
      }
    }

    if (!context.mounted) return;

    if (success) {
      final newVersion = await binaryManager.getVersion(BinaryType.ytDlp);
      historyService.addSuccess(
        binaryType: BinaryType.ytDlp,
        oldVersion: oldVersion,
        newVersion: newVersion,
      );

      ref.invalidate(ytdlpVersionProvider);
      ref.invalidate(ytdlpAvailableProvider);
      ref.invalidate(binaryVersionProvider(BinaryType.ytDlp));
      ref.invalidate(binaryAvailableProvider(BinaryType.ytDlp));

      if (!context.mounted) return;
      AppSnackBar.completeProgress(
        context,
        id: _binaryUpdateSnackId,
        message: AppLocalizations.settingsMessagesYtdlpUpdateSuccess,
      );
    } else {
      AppSnackBar.completeProgress(
        context,
        id: _binaryUpdateSnackId,
        message: AppLocalizations.settingsMessagesYtdlpUpdateFailed,
        success: false,
      );
    }
  }

  Future<void> _updateFFmpeg(BuildContext context, WidgetRef ref) async {
    await _updateAuxBinary(context, ref, BinaryType.ffmpeg);
  }

  Future<void> _updateAuxBinary(
    BuildContext context,
    WidgetRef ref,
    BinaryType type,
  ) async {
    if (!_beginBinaryUpdate(context)) return;
    _showBinaryUpdateProgress(
      context,
      message: AppLocalizations.settingsBinaryComponentsRepairingBinary(
        type.displayName,
      ),
    );

    try {
      final binaryManager = ref.read(binaryManagerProvider);
      final historyService = ref.read(binaryUpdateHistoryServiceProvider);
      final oldVersion = await binaryManager.getVersion(type);

      bool success = false;
      await for (final progress in binaryManager.updateBinarySafely(type)) {
        if (context.mounted) {
          _showBinaryProgress(context, type, progress);
        }
        if (progress.status == BinaryDownloadStatus.completed) {
          success = true;
        } else if (progress.status == BinaryDownloadStatus.error) {
          if (!context.mounted) return;
          final errorCode = BinaryUpdateErrorCodeX.classify(
            progress.error ?? '',
          );
          historyService.addFailure(
            binaryType: type,
            errorCode: errorCode,
            oldVersion: oldVersion,
            errorDetail: progress.error,
          );
          AppSnackBar.completeProgress(
            context,
            id: _binaryUpdateSnackId,
            message: errorCode.hint,
            success: false,
          );
          return;
        }
      }

      if (!context.mounted) return;

      if (success) {
        final newVersion = await binaryManager.getVersion(type);
        historyService.addSuccess(
          binaryType: type,
          oldVersion: oldVersion,
          newVersion: newVersion,
        );

        ref.invalidate(binaryVersionProvider(type));
        ref.invalidate(binaryAvailableProvider(type));

        if (!context.mounted) return;
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: AppLocalizations.settingsBinaryComponentsBinaryRepaired(
            type.displayName,
          ),
        );
      } else {
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: AppLocalizations.settingsBinaryComponentsBinaryRepairFailed(
            type.displayName,
          ),
          success: false,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final errorCode = BinaryUpdateErrorCodeX.classify(e.toString());
      AppSnackBar.completeProgress(
        context,
        id: _binaryUpdateSnackId,
        message: errorCode.hint,
        success: false,
      );
    } finally {
      _endBinaryUpdate();
    }
  }

  Future<void> _updateAllBinaries(BuildContext context, WidgetRef ref) async {
    if (!_beginBinaryUpdate(context)) return;
    _showBinaryUpdateProgress(
      context,
      message: AppLocalizations.settingsBinaryComponentsUpdatingAllBinaries,
    );

    try {
      final binaryManager = ref.read(binaryManagerProvider);
      final historyService = ref.read(binaryUpdateHistoryServiceProvider);
      final types = BinaryManager.requiredBinaries;

      int successCount = 0;
      for (final (index, type) in types.indexed) {
        final oldVersion = await binaryManager.getVersion(type);

        await for (final progress in binaryManager.updateBinarySafely(type)) {
          if (context.mounted) {
            _showBinaryProgress(
              context,
              type,
              progress,
              index: index + 1,
              total: types.length,
            );
          }
          if (progress.status == BinaryDownloadStatus.completed) {
            final newVersion = await binaryManager.getVersion(type);
            historyService.addSuccess(
              binaryType: type,
              oldVersion: oldVersion,
              newVersion: newVersion,
            );
            successCount++;
          } else if (progress.status == BinaryDownloadStatus.error) {
            final errorCode = BinaryUpdateErrorCodeX.classify(
              progress.error ?? '',
            );
            historyService.addFailure(
              binaryType: type,
              errorCode: errorCode,
              oldVersion: oldVersion,
              errorDetail: progress.error,
            );
          }
        }
      }

      if (!context.mounted) return;

      ref.invalidate(ytdlpVersionProvider);
      ref.invalidate(ytdlpAvailableProvider);
      for (final type in types) {
        ref.invalidate(binaryVersionProvider(type));
        ref.invalidate(binaryAvailableProvider(type));
      }

      final progressMsg =
          AppLocalizations.settingsBinaryComponentsUpdateProgress(
            successCount,
            types.length,
          );
      if (successCount == types.length) {
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: progressMsg,
        );
      } else {
        AppSnackBar.completeProgress(
          context,
          id: _binaryUpdateSnackId,
          message: progressMsg,
          success: false,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final errorCode = BinaryUpdateErrorCodeX.classify(e.toString());
      AppSnackBar.completeProgress(
        context,
        id: _binaryUpdateSnackId,
        message: errorCode.hint,
        success: false,
      );
    } finally {
      _endBinaryUpdate();
    }
  }

  bool _beginBinaryUpdate(BuildContext context) {
    if (_isUpdatingBinaries) {
      AppSnackBar.warning(
        context,
        message: AppLocalizations.settingsBinaryComponentsUpdateInProgress,
      );
      return false;
    }
    if (mounted) {
      setState(() => _isUpdatingBinaries = true);
    }
    return true;
  }

  void _endBinaryUpdate() {
    if (mounted) {
      setState(() => _isUpdatingBinaries = false);
    } else {
      _isUpdatingBinaries = false;
    }
  }

  void _showBinaryUpdateProgress(
    BuildContext context, {
    required String message,
  }) {
    AppSnackBar.progress(context, id: _binaryUpdateSnackId, message: message);
  }

  void _showBinaryProgress(
    BuildContext context,
    BinaryType type,
    BinaryDownloadProgress progress, {
    int? index,
    int? total,
  }) {
    final prefix = index != null && total != null ? '[$index/$total] ' : '';
    final name = type.displayName;
    final message = switch (progress.status) {
      BinaryDownloadStatus.starting =>
        prefix + AppLocalizations.settingsBinaryComponentsPreparingBinary(name),
      BinaryDownloadStatus.downloading =>
        progress.totalBytes > 0
            ? prefix +
                AppLocalizations.settingsBinaryComponentsDownloadingBinaryPercent(
                  name,
                  progress.percentage,
                )
            : prefix +
                AppLocalizations.settingsBinaryComponentsDownloadingBinary(
                  name,
                ),
      BinaryDownloadStatus.extracting =>
        prefix +
            AppLocalizations.settingsBinaryComponentsInstallingBinary(name),
      BinaryDownloadStatus.completed =>
        prefix + AppLocalizations.settingsBinaryComponentsBinaryUpdated(name),
      BinaryDownloadStatus.error =>
        prefix +
            AppLocalizations.settingsBinaryComponentsBinaryUpdateFailed(name),
    };

    AppSnackBar.progress(
      context,
      id: _binaryUpdateSnackId,
      message: message,
      value: progress.totalBytes > 0 ? progress.progress : null,
    );
  }

  void _showUpdateHistory(BuildContext context, WidgetRef ref) {
    final historyService = ref.read(binaryUpdateHistoryServiceProvider);
    final history = historyService.getHistory();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.binaryUpdateHistoryTitle),
          content: SizedBox(
            width: 400,
            height: 300,
            child:
                history.isEmpty
                    ? Center(
                      child: Text(AppLocalizations.binaryUpdateHistoryEmpty),
                    )
                    : ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final record = history[index];
                        final icon =
                            record.success
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded;
                        final color =
                            record.success
                                ? AppColors.successGreen
                                : AppColors.errorRed;
                        final newVersion = record.newVersion;
                        final subtitle =
                            record.success
                                ? (newVersion != null && newVersion.isNotEmpty
                                    ? AppLocalizations.binaryUpdateHistorySuccess(
                                      newVersion,
                                    )
                                    : AppLocalizations
                                        .binaryUpdateHistorySuccessNoVersion)
                                : AppLocalizations.binaryUpdateHistoryFailed(
                                  record.errorCode?.hint ??
                                      record.errorDetail ??
                                      '',
                                );
                        final time = _formatHistoryTime(record.timestamp);

                        return ListTile(
                          dense: true,
                          leading: Icon(icon, color: color, size: 20),
                          title: Text(
                            '${record.binaryType.displayName} - $time',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.commonClose),
            ),
          ],
        );
      },
    );
  }

  String _formatHistoryTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// =============================================================================
// BINARY STATUS TILE — Nocturne "Engine Bay" diagnostic monitor
// Shows label tag, monospace version (hero), ONLINE/OFFLINE badge, refresh.
// =============================================================================

class _BinaryStatusTile extends StatelessWidget {
  final IconData icon;
  final String label; // short uppercase tag e.g. "YT-DLP"
  final String description;
  final AsyncValue<String?> versionAsync;
  final AsyncValue<bool> availableAsync;
  final VoidCallback onRefresh;
  final String refreshTooltip;
  final bool isRefreshEnabled;

  const _BinaryStatusTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.versionAsync,
    required this.availableAsync,
    required this.onRefresh,
    required this.refreshTooltip,
    this.isRefreshEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textPrimary = cs.onSurface;
    final textSecondary = cs.onSurfaceVariant;
    final textTertiary = cs.onSurfaceVariant.withValues(alpha: 0.6);
    final errorColor = cs.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: textSecondary),
          const SizedBox(width: 14),
          // Label + version stack
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: textTertiary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                versionAsync.when(
                  data:
                      (version) => Text(
                        version ??
                            AppLocalizations
                                .settingsBinaryComponentsNotInstalled,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: version == null ? textSecondary : textPrimary,
                          height: 1.1,
                        ),
                      ),
                  loading:
                      () => Text(
                        AppLocalizations.settingsBinariesChecking,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                  error:
                      (_, __) => Text(
                        AppLocalizations.settingsBinariesErrorCheckingVersion,
                        style: TextStyle(fontSize: 12, color: errorColor),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 10, color: textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // ONLINE / OFFLINE badge
          availableAsync.when(
            data: (available) => _StatusBadge(available: available),
            loading:
                () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            error: (_, __) => const _StatusBadge(available: false),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: isRefreshEnabled ? onRefresh : null,
            tooltip: refreshTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            color: textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Diagnostic status pill: green dot + "ONLINE" or red dot + "OFFLINE".
class _StatusBadge extends StatelessWidget {
  final bool available;
  const _StatusBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.successGreen : AppColors.errorRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withAlpha(90), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            available
                ? AppLocalizations.settingsBinaryComponentsOnline
                : AppLocalizations.settingsBinaryComponentsOffline,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
