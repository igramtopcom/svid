import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/post_download_action.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsDownloadsSection extends ConsumerWidget {
  const SettingsDownloadsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final maxConcurrent = PremiumLimits.maxConcurrentDownloads(isPremium);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionDownloads,
        ),
        const Gap.md(),
        settingsCard(
          context,
          children: [
            // Download location
            ListTile(
              leading: const Icon(Icons.folder, size: 20),
              title: Text(AppLocalizations.settingsDownloadLocation),
              subtitle: Tooltip(
                message: settings.downloadPath,
                child: Text(
                  settings.downloadPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showFolderPicker(context, ref),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Concurrent downloads - inline stepper (capped by tier)
            ListTile(
              leading: const Icon(Icons.speed, size: 20),
              title: Text(AppLocalizations.settingsConcurrentDownloads),
              subtitle:
                  !isPremium
                      ? Text(
                        'Free: max $maxConcurrent · Premium: up to ${PremiumLimits.premiumMaxConcurrent}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                      : null,
              trailing: SettingsCompactStepper(
                value: settings.maxConcurrentDownloads.clamp(1, maxConcurrent),
                min: 1,
                max: maxConcurrent,
                onChanged:
                    (v) => ref
                        .read(settingsProvider.notifier)
                        .updateMaxConcurrentDownloads(v),
              ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Auto start
            BrandSwitchListTile(
              secondary: const Icon(Icons.play_arrow, size: 20),
              title: Text(AppLocalizations.settingsAutoStartDownloads),
              subtitle: Text(
                AppLocalizations.settingsAutoStartDownloadsSubtitle,
              ),
              value: settings.autoStartDownloads,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleAutoStartDownloads(),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Auto clipboard
            BrandSwitchListTile(
              secondary: const Icon(Icons.content_paste_go, size: 20),
              title: Text(AppLocalizations.settingsAutoClipboardDetection),
              subtitle: Text(
                AppLocalizations.settingsAutoClipboardDetectionSubtitle,
              ),
              value: settings.autoClipboardDetection,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleAutoClipboardDetection(),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Background audio
            BrandSwitchListTile(
              secondary: const Icon(Icons.headphones, size: 20),
              title: Text(AppLocalizations.playerBackgroundAudio),
              subtitle: Text(AppLocalizations.playerBackgroundAudioDesc),
              value: settings.backgroundAudioEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleBackgroundAudioEnabled(),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // System PiP
            BrandSwitchListTile(
              secondary: const Icon(Icons.picture_in_picture_alt, size: 20),
              title: Text(AppLocalizations.playerSystemPip),
              subtitle: Text(AppLocalizations.playerSystemPipDesc),
              value: settings.systemPipEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleSystemPipEnabled(),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Post-download action
            ListTile(
              leading: const Icon(Icons.auto_awesome, size: 20),
              title: Text(AppLocalizations.postDownloadActionSectionTitle),
              subtitle: Text(AppLocalizations.postDownloadActionSectionDesc),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: DropdownButtonFormField<PostDownloadAction>(
                value: settings.postDownloadAction,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items:
                    PostDownloadAction.values.map((action) {
                      return DropdownMenuItem(
                        value: action,
                        child: Text(_postDownloadActionLabel(action)),
                      );
                    }).toList(),
                onChanged: (action) {
                  if (action != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .updatePostDownloadAction(action);
                  }
                },
              ),
            ),
            if (settings.postDownloadAction ==
                    PostDownloadAction.moveToFolder ||
                settings.postDownloadAction ==
                    PostDownloadAction.deleteAfterMove)
              ListTile(
                leading: const Icon(Icons.folder_open, size: 20),
                title: Text(AppLocalizations.postDownloadActionTargetFolder),
                subtitle: Text(
                  settings.postDownloadTargetFolder.isEmpty
                      ? AppLocalizations.postDownloadActionTargetFolderNotSet
                      : settings.postDownloadTargetFolder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final dir = await FilePicker.platform.getDirectoryPath();
                    if (!context.mounted) return;
                    if (dir != null) {
                      ref
                          .read(settingsProvider.notifier)
                          .updatePostDownloadTargetFolder(dir);
                    }
                  },
                  child: Text(AppLocalizations.postDownloadActionSelectFolder),
                ),
              ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Bandwidth limit
            SettingsBandwidthLimitTile(settings: settings),
          ],
        ),

        const Gap.md(),

        // Card: Orphaned file cleanup
        settingsCard(
          context,
          children: [
            _OrphanedFilesSection(downloadPath: settings.downloadPath),
          ],
        ),
      ],
    );
  }

  String _postDownloadActionLabel(PostDownloadAction action) {
    switch (action) {
      case PostDownloadAction.none:
        return AppLocalizations.postDownloadActionNone;
      case PostDownloadAction.openFile:
        return AppLocalizations.postDownloadActionOpenFile;
      case PostDownloadAction.openFolder:
        return AppLocalizations.postDownloadActionOpenFolder;
      case PostDownloadAction.moveToFolder:
        return AppLocalizations.postDownloadActionMoveToFolder;
      case PostDownloadAction.deleteAfterMove:
        return AppLocalizations.postDownloadActionDeleteAfterMove;
    }
  }

  Future<void> _showFolderPicker(BuildContext context, WidgetRef ref) async {
    try {
      final currentPath = ref.read(settingsProvider).downloadPath;
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: AppLocalizations.settingsDownloadLocation,
        initialDirectory: currentPath,
      );
      if (!context.mounted) return;

      if (result != null) {
        final canWrite = await FileUtils.canWriteToDirectory(result);
        if (!context.mounted) return;
        if (!canWrite) {
          if (context.mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.errorPermission(result),
            );
          }
          return;
        }

        await ref.read(settingsProvider.notifier).updateDownloadPath(result);

        if (context.mounted) {
          AppSnackBar.success(
            context,
            message: '${AppLocalizations.settingsDownloadLocation}: $result',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.error(
          context,
          message:
              '${AppLocalizations.commonError}: ${AppExceptionX.readableMessage(e)}',
        );
      }
    }
  }
}

// =============================================================================
// ORPHANED FILES SECTION (private to this file)
// =============================================================================

class _OrphanedFilesSection extends ConsumerWidget {
  final String downloadPath;

  const _OrphanedFilesSection({required this.downloadPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanupService = ref.read(orphanedFileCleanupServiceProvider);

    return FutureBuilder<List<File>>(
      future:
          downloadPath.isNotEmpty
              ? cleanupService.findOrphanedFiles(downloadPath)
              : Future.value([]),
      builder: (context, snapshot) {
        final files = snapshot.data ?? [];
        final count = files.length;
        final totalBytes = files.fold<int>(
          0,
          (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0),
        );
        final sizeLabel = FileUtils.formatBytes(totalBytes);

        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, size: 20),
              title: Text(AppLocalizations.orphanedFilesSectionTitle),
              subtitle: Text(
                count == 0
                    ? AppLocalizations.orphanedFilesNoOrphans
                    : AppLocalizations.orphanedFilesFound(count, sizeLabel),
              ),
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: Text(AppLocalizations.orphanedFilesCleanButton),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder:
                            (ctx) => AlertDialog(
                              title: Text(
                                AppLocalizations.orphanedFilesConfirmTitle,
                              ),
                              content: Text(
                                AppLocalizations.orphanedFilesConfirmBody(
                                  count,
                                  sizeLabel,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(AppLocalizations.commonCancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(ctx).colorScheme.error,
                                  ),
                                  child: Text(
                                    AppLocalizations.orphanedFilesCleanButton,
                                  ),
                                ),
                              ],
                            ),
                      );
                      if (confirmed != true || !context.mounted) return;

                      final result = await cleanupService.cleanup(downloadPath);
                      if (!context.mounted) return;

                      AppSnackBar.success(
                        context,
                        message: AppLocalizations.orphanedFilesSuccess(
                          FileUtils.formatBytes(result.bytesFreed),
                          result.filesDeleted,
                        ),
                      );
                      // Trigger FutureBuilder rebuild
                      (context as Element).markNeedsBuild();
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
