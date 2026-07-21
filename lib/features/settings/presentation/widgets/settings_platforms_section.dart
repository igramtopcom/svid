import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/core.dart';
import '../../../../core/auth/presentation/providers/auth_providers.dart';
import '../../../downloads/domain/services/download_archive_service.dart';
import '../../../downloads/domain/services/extraction_cache_service.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../domain/services/browser_cookie_import_service.dart';
import '../providers/settings_provider.dart';
import '../providers/platform_preferences_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsPlatformsSection extends ConsumerWidget {
  const SettingsPlatformsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionPlatforms,
        ),
        const Gap.md(),

        // Card: Platform Options
        settingsCard(
          context,
          title: AppLocalizations.settingsPlatformsTitle,
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.music_note, size: 20),
              title: Text(
                AppLocalizations.settingsPlatformSpecificRemoveTikTokWatermark,
              ),
              subtitle: Text(
                AppLocalizations
                    .settingsPlatformSpecificRemoveTikTokWatermarkDesc,
              ),
              value: settings.tiktokRemoveWatermark,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleTiktokRemoveWatermark(),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Saved Quality Preferences
        settingsCard(
          context,
          title: AppLocalizations.settingsPlatformPreferences.toUpperCase(),
          children: [_PlatformPreferencesSection()],
        ),

        const Gap.md(),

        // Card: Browser Cookie Import
        settingsCard(
          context,
          title: AppLocalizations.cookieImportTitle.toUpperCase(),
          children: [_BrowserCookieImportSection()],
        ),

        const Gap.md(),

        // Card: Extraction Metadata Cache
        settingsCard(
          context,
          title: AppLocalizations.extractionCacheTitle.toUpperCase(),
          children: [_ExtractionCacheSection()],
        ),

        const Gap.md(),

        // Card: Platform Logins
        settingsCard(
          context,
          title: AppLocalizations.settingsPlatformLogins.toUpperCase(),
          children: [_PlatformLoginsSection()],
        ),
      ],
    );
  }
}

// =============================================================================
// PLATFORM PREFERENCES
// =============================================================================

class _PlatformPreferencesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesState = ref.watch(platformPreferencesProvider);
    final preferences = preferencesState.preferences;

    if (preferences.isEmpty) {
      return Padding(
        padding: AppSpacing.edgeInsets.md,
        child: Text(
          AppLocalizations.settingsNoPlatformPreferences,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        ...preferences.entries.map((entry) {
          final platform = entry.key;
          final preference = entry.value;

          return ListTile(
            leading: Icon(_getPlatformIcon(platform), size: 20),
            title: Text(platform.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${preference.qualityText} (${preference.mediaType.name})',
                ),
                if (preference.hasFormatOverrides)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        if (preference.videoCodec != null)
                          _buildOverrideChip(context, preference.videoCodec!),
                        if (preference.audioCodec != null)
                          _buildOverrideChip(context, preference.audioCodec!),
                        if (preference.containerFormat != null)
                          _buildOverrideChip(
                            context,
                            preference.containerFormat!,
                          ),
                        if (preference.maxResolution != null)
                          _buildOverrideChip(
                            context,
                            '${preference.maxResolution}p',
                          ),
                        if (preference.subtitlesEnabled == true)
                          _buildOverrideChip(
                            context,
                            AppLocalizations.settingsPlatformOverrideSubs,
                          ),
                        if (preference.sponsorBlockEnabled == true)
                          _buildOverrideChip(
                            context,
                            AppLocalizations.settingsPlatformOverrideSB,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed:
                  () => _showDeletePreferenceDialog(context, ref, platform),
              tooltip: AppLocalizations.settingsRemovePreference,
            ),
          );
        }),

        if (preferences.isNotEmpty) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showClearAllPreferencesDialog(context, ref),
                icon: const Icon(Icons.clear_all),
                label: Text(AppLocalizations.settingsClearAllPreferences),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverrideChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        label,
        style: AppTypography.mini.copyWith(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }

  IconData _getPlatformIcon(VideoPlatform platform) {
    switch (platform) {
      case VideoPlatform.youtube:
        return Icons.play_circle_outline;
      case VideoPlatform.instagram:
        return Icons.camera_alt_outlined;
      case VideoPlatform.facebook:
        return Icons.facebook;
      case VideoPlatform.tiktok:
        return Icons.music_note;
      case VideoPlatform.twitter:
        return Icons.tag;
      case VideoPlatform.reddit:
        return Icons.forum_outlined;
      case VideoPlatform.pinterest:
        return Icons.push_pin_outlined;
      case VideoPlatform.threads:
        return Icons.alternate_email;
      default:
        return Icons.public;
    }
  }

  Future<void> _showDeletePreferenceDialog(
    BuildContext context,
    WidgetRef ref,
    VideoPlatform platform,
  ) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.settingsRemovePreferenceTitle,
      message: AppLocalizations.settingsRemovePreferenceMessage(
        platform.displayName,
      ),
      confirmLabel: AppLocalizations.settingsRemove,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref
        .read(platformPreferencesProvider.notifier)
        .removePreference(platform);
    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.settingsRemovedPreference(
          platform.displayName,
        ),
      );
    }
  }

  Future<void> _showClearAllPreferencesDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final count = ref.read(platformPreferencesProvider).preferences.length;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.settingsClearAllPreferencesTitle,
      message: AppLocalizations.settingsClearAllPreferencesMessage(count),
      confirmLabel: AppLocalizations.settingsClearAll,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(platformPreferencesProvider.notifier).clearAll();
    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.settingsClearedAllPreferences,
      );
    }
  }
}

// =============================================================================
// BROWSER COOKIE IMPORT
// =============================================================================

class _BrowserCookieImportSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(browserCookieImportServiceProvider);
    final selectedBrowser = service.selectedBrowser;
    final detectedBrowsers = service.detectInstalledBrowsers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            AppLocalizations.cookieImportDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cookie_outlined, size: 20),
          title: Text(AppLocalizations.cookieImportBrowser),
          trailing: DropdownButton<BrowserType?>(
            value: selectedBrowser,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem<BrowserType?>(
                value: null,
                child: Text(AppLocalizations.cookieImportNone),
              ),
              ...detectedBrowsers.map(
                (browser) => DropdownMenuItem<BrowserType?>(
                  value: browser,
                  child: Text(browser.displayName),
                ),
              ),
            ],
            onChanged: (browser) async {
              await service.setSelectedBrowser(browser);
              ref.invalidate(browserCookieImportServiceProvider);
              ref.invalidate(cookiesFromBrowserProvider);
            },
          ),
        ),
        if (detectedBrowsers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              AppLocalizations.cookieImportNoBrowsers,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (selectedBrowser != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppColors.accentHighlight,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppLocalizations.cookieImportActive(
                      selectedBrowser.displayName,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.accentHighlight,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// EXTRACTION CACHE
// =============================================================================

class _ExtractionCacheSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheAsync = ref.watch(extractionCacheServiceProvider);

    return cacheAsync.when(
      data: (cacheService) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                AppLocalizations.extractionCacheDescription,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FutureBuilder<List<int>>(
              future: Future.wait([
                cacheService.getCacheSize(),
                cacheService.getEntryCount(),
              ]),
              builder: (context, snapshot) {
                final size = snapshot.data?[0] ?? 0;
                final count = snapshot.data?[1] ?? 0;

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storage_outlined, size: 20),
                      title: Text(AppLocalizations.extractionCacheCacheSize),
                      trailing: Text(
                        ExtractionCacheService.formatSize(size),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined, size: 20),
                      title: Text(
                        AppLocalizations.extractionCacheEntries(count),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(
                            AppLocalizations.extractionCacheClearCache,
                          ),
                          onPressed:
                              count == 0
                                  ? null
                                  : () async {
                                    await cacheService.clear();
                                    ref.invalidate(
                                      extractionCacheServiceProvider,
                                    );
                                    if (context.mounted) {
                                      AppSnackBar.success(
                                        context,
                                        message:
                                            AppLocalizations
                                                .extractionCacheCacheCleared,
                                      );
                                    }
                                  },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
      loading:
          () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// =============================================================================
// PLATFORM LOGINS
// =============================================================================

class _PlatformLoginsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cookiesAsync = ref.watch(allPlatformCookiesProvider);

    return cookiesAsync.when(
      data: (cookies) {
        if (cookies.isEmpty) {
          return Padding(
            padding: AppSpacing.edgeInsets.md,
            child: Text(
              AppLocalizations.settingsNoPlatformLogins,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return Column(
          children: [
            ...cookies.map((cookie) {
              return ListTile(
                leading: Icon(_getLoginPlatformIcon(cookie.platform), size: 20),
                title: Text(cookie.platformDisplayName),
                subtitle: Text(
                  AppLocalizations.settingsLoggedInOn(
                    _formatDate(cookie.savedAt),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed:
                      () =>
                          _showDeleteLoginDialog(context, ref, cookie.platform),
                  tooltip: AppLocalizations.settingsRemoveLogin,
                ),
              );
            }),

            if (cookies.isNotEmpty) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        () => _showClearAllLoginsDialog(
                          context,
                          ref,
                          cookies.length,
                        ),
                    icon: const Icon(Icons.clear_all),
                    label: Text(AppLocalizations.settingsClearAllLogins),
                  ),
                ),
              ),
            ],
          ],
        );
      },
      loading:
          () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stack) => Padding(
            padding: AppSpacing.edgeInsets.md,
            child: Text(
              AppLocalizations.settingsErrorLoadingLogins(error.toString()),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
    );
  }

  IconData _getLoginPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_outline;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'facebook':
        return Icons.facebook;
      case 'tiktok':
        return Icons.music_note;
      case 'twitter':
      case 'x':
        return Icons.tag;
      case 'reddit':
        return Icons.forum;
      case 'pinterest':
        return Icons.push_pin;
      default:
        return Icons.public;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _showDeleteLoginDialog(
    BuildContext context,
    WidgetRef ref,
    String platform,
  ) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.settingsRemoveLoginTitle,
      message: AppLocalizations.settingsRemoveLoginMessage(platform),
      confirmLabel: AppLocalizations.settingsRemove,
      isDestructive: true,
    );
    if (confirmed) {
      final removeCookiesUseCase = ref.read(
        removePlatformCookiesUseCaseProvider,
      );
      await removeCookiesUseCase(platform);
      if (context.mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.settingsRemovedLogin(platform),
        );
        ref.invalidate(getAllPlatformCookiesUseCaseProvider);
      }
    }
  }

  Future<void> _showClearAllLoginsDialog(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.settingsClearAllLoginsTitle,
      message: AppLocalizations.settingsClearAllLoginsMessage(count),
      confirmLabel: AppLocalizations.settingsClearAll,
      isDestructive: true,
    );
    if (confirmed) {
      final removeAllCookiesUseCase = ref.read(
        removeAllPlatformCookiesUseCaseProvider,
      );
      final result = await removeAllCookiesUseCase();
      if (context.mounted) {
        if (result.isSuccess) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.settingsClearedAllLogins,
          );
          ref.invalidate(allPlatformCookiesProvider);
        } else {
          AppSnackBar.error(
            context,
            message: AppLocalizations.settingsPlatformClearLoginsError(
              AppExceptionX.readableMessage(
                result.exceptionOrNull ?? Exception('Unknown'),
              ),
            ),
          );
        }
      }
    }
  }
}

// =============================================================================
// DOWNLOAD ARCHIVE SECTION
// =============================================================================

class SettingsDownloadArchiveSection extends ConsumerWidget {
  final String downloadPath;

  const SettingsDownloadArchiveSection({super.key, required this.downloadPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archiveService = DownloadArchiveService();

    Future<String> resolveArchivePath() async {
      if (downloadPath.isNotEmpty) {
        return '$downloadPath/.${BrandConfig.current.brand.name}_archive.txt';
      }
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/.${BrandConfig.current.brand.name}_archive.txt';
    }

    return FutureBuilder<String>(
      future: resolveArchivePath(),
      builder: (context, pathSnapshot) {
        if (!pathSnapshot.hasData) return const SizedBox.shrink();
        final archivePath = pathSnapshot.data!;

        return FutureBuilder<int>(
          future: archiveService.getArchiveCount(archivePath),
          builder: (context, countSnapshot) {
            final count = countSnapshot.data ?? 0;

            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.list_alt_outlined, size: 20),
                  title: Text(AppLocalizations.downloadArchiveSectionTitle),
                  subtitle: Text(
                    AppLocalizations.downloadArchiveEntryCount(count),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: Text(
                            AppLocalizations.downloadArchiveClearArchive,
                          ),
                          onPressed:
                              count == 0
                                  ? null
                                  : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder:
                                          (ctx) => AlertDialog(
                                            content: Text(
                                              AppLocalizations
                                                  .downloadArchiveClearArchiveConfirm,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      ctx,
                                                      false,
                                                    ),
                                                child: Text(AppLocalizations.commonCancel),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      ctx,
                                                      true,
                                                    ),
                                                child: Text(
                                                  AppLocalizations
                                                      .downloadArchiveClearArchive,
                                                ),
                                              ),
                                            ],
                                          ),
                                    );
                                    if (confirmed == true && context.mounted) {
                                      await archiveService.clearArchive(
                                        archivePath,
                                      );
                                      if (context.mounted) {
                                        AppSnackBar.success(
                                          context,
                                          message:
                                              AppLocalizations
                                                  .downloadArchiveClearArchiveSuccess,
                                        );
                                        // Rebuild to show updated count
                                        (context as Element).markNeedsBuild();
                                      }
                                    }
                                  },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: Text(
                            AppLocalizations.downloadArchiveExportArchive,
                          ),
                          onPressed:
                              count == 0
                                  ? null
                                  : () async {
                                    final file = await archiveService
                                        .exportArchive(archivePath);
                                    if (file == null) {
                                      if (context.mounted) {
                                        AppSnackBar.warning(
                                          context,
                                          message:
                                              AppLocalizations
                                                  .downloadArchiveExportArchiveEmpty,
                                        );
                                      }
                                      return;
                                    }
                                    final savePath = await FilePicker.platform
                                        .saveFile(
                                          dialogTitle:
                                              AppLocalizations
                                                  .downloadArchiveExportArchive,
                                          fileName:
                                              '${BrandConfig.current.brand.name}_archive.txt',
                                        );
                                    if (savePath != null) {
                                      await file.copy(savePath);
                                    }
                                  },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
