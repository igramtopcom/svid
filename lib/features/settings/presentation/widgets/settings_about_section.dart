import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../support/presentation/widgets/bug_report_dialog.dart';
import '../../../support/presentation/widgets/rating_dialog.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsAboutSection extends ConsumerStatefulWidget {
  const SettingsAboutSection({super.key});

  @override
  ConsumerState<SettingsAboutSection> createState() =>
      _SettingsAboutSectionState();
}

class _SettingsAboutSectionState extends ConsumerState<SettingsAboutSection> {
  Future<Map<String, dynamic>>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    _statsFuture = ref.read(databaseProvider).getDownloadStatistics();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _exportSettings() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final keys = prefs.getKeys();
      final data = <String, dynamic>{};
      for (final key in keys) {
        data[key] = prefs.get(key);
      }
      final export = {
        'app': AppConstants.appName,
        'version': AppConstants.appVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': data,
      };
      final json = const JsonEncoder.withIndent('  ').convert(export);

      final result = await FilePicker.platform.saveFile(
        dialogTitle: AppLocalizations.settingsExport,
        fileName: '${BrandConfig.current.brand.name}_settings_backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null) return;

      await File(result).writeAsString(json);
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.settingsExportSuccess,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.settingsImportError,
        );
      }
    }
  }

  Future<void> _importSettings() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: AppLocalizations.settingsImport,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      if (!mounted) return;
      final Map<String, dynamic> parsed = jsonDecode(content);

      if (!parsed.containsKey('settings') || !parsed.containsKey('app')) {
        if (mounted) {
          AppSnackBar.error(
            context,
            message: AppLocalizations.settingsImportError,
          );
        }
        return;
      }

      final settings = parsed['settings'] as Map<String, dynamic>;
      final prefs = ref.read(sharedPreferencesProvider);

      for (final entry in settings.entries) {
        final value = entry.value;
        if (value is String) {
          await prefs.setString(entry.key, value);
        } else if (value is int) {
          await prefs.setInt(entry.key, value);
        } else if (value is double) {
          await prefs.setDouble(entry.key, value);
        } else if (value is bool) {
          await prefs.setBool(entry.key, value);
        } else if (value is List) {
          await prefs.setStringList(entry.key, value.cast<String>());
        }
      }

      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.settingsImportSuccess,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.settingsImportError,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final registeredAsync = ref.watch(isDeviceRegisteredProvider);
    final deviceIdAsync = ref.watch(deviceIdProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isRegistered = registeredAsync.valueOrNull ?? false;
    final deviceId = deviceIdAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionAboutSupport,
        ),
        const Gap.md(),

        settingsCard(
          context,
          children: [
            // Device registration
            ListTile(
              leading: Icon(
                isRegistered ? Icons.check_circle : Icons.error_outline,
                size: 20,
                color: isRegistered ? AppColors.success(context) : cs.error,
              ),
              title: Text(
                isRegistered
                    ? AppLocalizations.settingsAccountDeviceRegistered
                    : AppLocalizations.settingsAccountDeviceNotRegistered,
              ),
              subtitle:
                  isRegistered && deviceId != null
                      ? Text(
                        AppLocalizations.settingsAccountDeviceId(
                          deviceId.length > 8
                              ? '${deviceId.substring(0, 8)}...'
                              : deviceId,
                        ),
                      )
                      : null,
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Report Bug
            ListTile(
              leading: const Icon(Icons.bug_report_outlined, size: 20),
              title: Text(AppLocalizations.settingsAccountReportBug),
              subtitle: Text(AppLocalizations.settingsAccountReportBugSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => showDialog(
                    context: context,
                    builder: (_) => const BugReportDialog(),
                  ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Rate App
            ListTile(
              leading: const Icon(Icons.star_outline, size: 20),
              title: Text(AppLocalizations.settingsAccountRateApp),
              subtitle: Text(AppLocalizations.settingsAccountRateAppSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => showDialog(
                    context: context,
                    builder: (_) => const RatingDialog(),
                  ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Support Center
            ListTile(
              leading: const Icon(Icons.support_agent_outlined, size: 20),
              title: Text(AppLocalizations.settingsAccountSupportCenter),
              subtitle: Text(
                AppLocalizations.settingsAccountSupportCenterSubtitle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => ref
                      .read(navigationProvider.notifier)
                      .navigateToTab(NavigationConstants.supportIndex),
            ),
          ],
        ),

        const Gap.lg(),

        // Usage Statistics
        settingsSectionTitle(context, AppLocalizations.usageStatsTitle),
        const Gap.md(),

        FutureBuilder<Map<String, dynamic>>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return settingsCard(
                context,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  ),
                ],
              );
            }

            final stats = snapshot.data;
            if (stats == null) {
              return const SizedBox.shrink();
            }

            final total = stats['total'] as int;
            final completed = stats['completed'] as int;
            final failed = stats['failed'] as int;
            final totalBytes = stats['totalBytes'] as int;
            final byPlatform = stats['byPlatform'] as Map<String, int>? ?? {};

            return settingsCard(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      // Stats grid
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              icon: Icons.download,
                              label: AppLocalizations.usageStatsTotalDownloads,
                              value: '$total',
                              color: AppColors.accentHighlight,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.check_circle_outline,
                              label: AppLocalizations.usageStatsCompleted,
                              value: '$completed',
                              color: AppColors.success(context),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.error_outline,
                              label: AppLocalizations.usageStatsFailed,
                              value: '$failed',
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.smMd),
                      // Total data
                      _StatTile(
                        icon: Icons.storage,
                        label: AppLocalizations.usageStatsTotalData,
                        value: _formatBytes(totalBytes),
                        color: cs.tertiary,
                      ),
                      // Platform breakdown
                      if (byPlatform.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.smMd),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppLocalizations.usageStatsByPlatform,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: AppTypography.semiBold,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children:
                              byPlatform.entries
                                  .take(8)
                                  .map(
                                    (e) => Chip(
                                      label: Text('${e.key}: ${e.value}'),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        const Gap.lg(),

        // Backup & Restore
        settingsSectionTitle(context, AppLocalizations.settingsBackupRestore),
        const Gap.md(),

        settingsCard(
          context,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file, size: 20),
              title: Text(AppLocalizations.settingsExport),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportSettings,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.download_for_offline_outlined,
                size: 20,
              ),
              title: Text(AppLocalizations.settingsImport),
              trailing: const Icon(Icons.chevron_right),
              onTap: _importSettings,
            ),
          ],
        ),

        const Gap.lg(),

        // Reset to defaults
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.errorRed,
              side: const BorderSide(color: AppColors.errorRed, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
            onPressed: () => _showResetDialog(context),
            child: Text(
              AppLocalizations.settingsResetToDefaults.toUpperCase(),
              style: AppTypography.sectionHeader.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),

        const Gap.xl(),

        // Version footer
        Center(
          child: Text(
            '${AppConstants.appName} v${AppConstants.appVersion}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? AppColors.darkMetaText : AppColors.lightMetaText,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showResetDialog(BuildContext context) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.settingsResetDialogTitle,
      message: AppLocalizations.settingsResetDialogMessage,
      confirmLabel: AppLocalizations.settingsResetDialogConfirm,
      isDestructive: true,
    );
    if (confirmed) {
      ref.read(settingsProvider.notifier).resetToDefaults();
      if (context.mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.settingsResetSuccess,
        );
      }
    }
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.hover),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: AppTypography.bold,
              color: color,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
